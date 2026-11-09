from __future__ import annotations

import random
from pathlib import Path

import pytest

from asm import isa
from asm.disasm import disasm, disasm_at
from asm.rvasm import assemble

SW = Path(__file__).resolve().parents[1]
ALL32 = SW / "tests" / "data" / "all32.s"
PROGRAMS = SW.parent / "programs"

ROWS = [
    (0x003100B3, "add x1, x2, x3"),
    (0x00500093, "addi x1, x0, 5"),
    (0xFFB00093, "addi x1, x0, -5"),
    (0x80008093, "addi x1, x1, -2048"),
    (0x7FF08093, "addi x1, x1, 2047"),
    (0x41F0D093, "srai x1, x1, 31"),
    (0x00009093, "slli x1, x1, 0"),
    (0xFFC12283, "lw x5, -4(x2)"),
    (0x00512423, "sw x5, 8(x2)"),
    (0xFE20AE23, "sw x2, -4(x1)"),
    (0xFE311CE3, "bne x2, x3, -8"),
    (0xFE000EE3, "beq x0, x0, -4"),
    (0x00000263, "beq x0, x0, 4"),
    (0x7E000FE3, "beq x0, x0, 4094"),
    (0x80000063, "beq x0, x0, -4096"),
    (0x010000EF, "jal x1, 16"),
    (0xFFDFF06F, "jal x0, -4"),
    (0x7FFFF06F, "jal x0, 1048574"),
    (0x8000006F, "jal x0, -1048576"),
    (0x00008067, "jalr x0, 0(x1)"),
    (0x123450B7, "lui x1, 0x12345"),
    (0x800000B7, "lui x1, 0x80000"),
    (0x00000073, "halt"),
    (0x00000013, "nop"),
]


@pytest.mark.parametrize("word,text", ROWS)
def test_tabla(word: int, text: str) -> None:
    assert disasm(word) == text


@pytest.mark.parametrize("word", [
    0x00000000, 0xFFFFFFFF,
    0x40007033,                       # and con funct7 alterno
    0x40004033,                       # xor con funct7 alterno
    0x40001093 | (1 << 25),           # slli con funct7 distinto
    0x40009093,                       # slli con funct7 alterno
    0x00004063,                       # blt
    0x00003003,                       # ld (funct3 inválido en load)
    0x00003023,                       # sd (funct3 inválido en store)
    0x00001067,                       # jalr con funct3 != 0
    0x00100073,                       # ebreak
    0x00000017,                       # auipc
])
def test_fuera_del_subconjunto(word: int) -> None:
    assert disasm(word) == "???"


def test_todas_las_instrucciones_de_all32() -> None:
    words = assemble(ALL32.read_text(encoding="utf-8"))
    assert "???" not in [disasm(w) for w in words]


def test_disasm_at() -> None:
    words = [0x00500093, 0x00000073]
    assert disasm_at(words, 0) == "addi x1, x0, 5"
    assert disasm_at(words, 4) == "halt"
    assert disasm_at(words, 8) == "???"
    assert disasm_at(words, -4) == "???"
    assert disasm_at([], 0) == "???"


def roundtrip(words: list[int]) -> list[int]:
    return assemble("\n".join(disasm(w) for w in words))


def test_ida_y_vuelta_all32() -> None:
    w = assemble(ALL32.read_text(encoding="utf-8"))
    assert roundtrip(w) == w


def test_ida_y_vuelta_programs() -> None:
    for path in sorted(PROGRAMS.glob("*.s")):
        w = assemble(path.read_text(encoding="utf-8"))
        assert roundtrip(w) == w, path.name


def test_ida_y_vuelta_aleatoria() -> None:
    """Toda palabra que desensambla a algo distinto de '???' vuelve a ensamblar a sí misma."""
    rng = random.Random(20)
    opcodes = [isa.OP_R, isa.OP_I, isa.OP_LOAD, isa.OP_JALR, isa.OP_STORE, isa.OP_BRANCH, isa.OP_JAL,
               isa.OP_LUI]
    valid = 0
    for _ in range(20000):
        w = (rng.getrandbits(25) << 7) | rng.choice(opcodes)
        text = disasm(w)
        if text == "???":
            continue
        valid += 1
        assert assemble(text)[0] == w, (hex(w), text)
    assert valid > 1000

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

from asm.rvasm import AsmError, assemble, to_bin, to_hex

SW = Path(__file__).resolve().parents[1]
TOOLS = SW.parent / "tools"
JAR = TOOLS / "rars1_6.jar"
ALL32 = SW / "tests" / "data" / "all32.s"


def body(src: str) -> list[int]:
    """Palabras de src sin el HALT final (se agrega uno propio para no depender del automático)."""
    return assemble(src + "\nhalt")[:-1]


FIXED = [
    ("addi x1, x0, 5", [0x00500093]),
    ("addi x1, x1, -2048", [0x80008093]),
    ("addi x1, x1, -1", [0xFFF08093]),
    ("addi x1, x1, 0", [0x00008093]),
    ("addi x1, x1, 2047", [0x7FF08093]),
    ("sw x2, -4(x1)", [0xFE20AE23]),
    ("beq x0, x0, -4", [0xFE000EE3]),
    ("beq x0, x0, 4", [0x00000263]),
    ("beq x0, x0, 4094", [0x7E000FE3]),
    ("beq x0, x0, -4096", [0x80000063]),
    ("jal x0, -4", [0xFFDFF06F]),
    ("jal x0, 4", [0x0040006F]),
    ("jal x0, 1048574", [0x7FFFF06F]),
    ("jal x0, -1048576", [0x8000006F]),
    ("lui x1, 0x12345", [0x123450B7]),
    ("srai x1, x1, 31", [0x41F0D093]),
    ("slli x1, x1, 0", [0x00009093]),
    ("nop", [0x00000013]),
    ("halt", [0x00000073]),
    ("ecall", [0x00000073]),
    ("ret", [0x00008067]),
]


@pytest.mark.parametrize("src,expected", FIXED)
def test_valores_fijos(src: str, expected: list[int]) -> None:
    assert body(src) == expected


LI = [
    ("li x1, 0x12345FFF", "lui x1, 0x12346\naddi x1, x1, -1"),
    ("li x1, 0x00000800", "lui x1, 0x1\naddi x1, x1, -2048"),
    ("li x1, 0xFFFFF800", "addi x1, x0, -2048"),
    ("li x1, 0x7FFFFFFF", "lui x1, 0x80000\naddi x1, x1, -1"),
    ("li x1, -1", "addi x1, x0, -1"),
    ("li x1, 0x12345000", "lui x1, 0x12345\naddi x1, x1, 0"),
]


@pytest.mark.parametrize("src,equiv", LI)
def test_li(src: str, equiv: str) -> None:
    assert body(src) == body(equiv)
    assert len(body(src)) == len(body(equiv))


def test_li_tamanos() -> None:
    assert len(body("li x1, 2047")) == 1
    assert len(body("li x1, 2048")) == 2
    assert len(body("li x1, -2048")) == 1
    assert len(body("li x1, -2049")) == 2
    assert len(body("li x1, 0x12345000")) == 2
    assert len(body("li x1, 0xFFFFFFFF")) == 1
    assert len(body("li x1, -2147483648")) == 2


def test_pseudos() -> None:
    assert body("mv x3, x4") == body("addi x3, x4, 0")
    assert body("j 8") == body("jal x0, 8")
    assert body("jal 8") == body("jal ra, 8")
    assert body("jalr x5") == body("jalr ra, 0(x5)")
    assert body("jalr x1, x2, 8") == body("jalr x1, 8(x2)")
    assert body("lw x1, (x2)") == body("lw x1, 0(x2)")


def test_registros_y_mayusculas() -> None:
    assert body("ADD A0, SP, T6") == body("add x10, x2, x31")
    assert body("addi fp, s0, 1") == body("addi x8, x8, 1")


def test_inmediatos() -> None:
    assert body("addi x1, x0, -0x10") == body("addi x1, x0, -16")
    assert body("addi x1, x0, +4") == body("addi x1, x0, 4")
    assert body("addi x1, x0, 0X1F") == body("addi x1, x0, 31")


def test_halt_automatico() -> None:
    assert len(assemble("addi x1,x0,1")) == 2
    assert assemble("addi x1,x0,1")[-1] == 0x73
    assert len(assemble("addi x1,x0,1\nhalt")) == 2
    assert len(assemble("addi x1,x0,1\necall")) == 2
    assert assemble("") == [0x73]


def test_etiquetas() -> None:
    by_label = assemble("loop: addi x1, x1, -1\nbne x1, x0, loop")
    numeric = assemble("addi x1, x1, -1\nbne x1, x0, -4")
    assert by_label == numeric
    fwd = assemble("beq x0, x0, fin\nnop\nfin: halt")
    assert fwd == assemble("beq x0, x0, 8\nnop\nhalt")


def test_etiquetas_misma_direccion() -> None:
    w = assemble("a:\nb: nop\nbeq x0, x0, a\nbeq x0, x0, b")
    assert w[1] == assemble("nop\nbeq x0, x0, -4")[1]
    assert w[2] == assemble("nop\nnop\nbeq x0, x0, -8")[2]


def test_to_bin_y_to_hex() -> None:
    assert to_bin([0x00500093]) == b"\x93\x00\x50\x00"
    assert to_hex([0x00500093, 0xFFF08093]) == "00500093\nfff08093\n"


def test_comentarios_y_directiva_text() -> None:
    src = "  .text\n# comentario\n\nstart: addi x1, x0, 1   # fin\n"
    assert body(src) == [0x00100093]


ERRORS = [
    ("xyz x1, x2", 1, "instrucción desconocida 'xyz'"),
    ("nop\nadd x1, x32, x2", 2, "registro inválido 'x32'"),
    ("add x1, x2", 1, "'add' espera 3 operandos, recibió 2"),
    ("addi x1, x0, 4096", 1, "inmediato 4096 fuera de rango [-2048, 2047]"),
    ("addi x1, x0, -2049", 1, "inmediato -2049 fuera de rango [-2048, 2047]"),
    ("slli x1, x1, 32", 1, "inmediato 32 fuera de rango [0, 31]"),
    ("lui x1, 0x100000", 1, "inmediato 1048576 fuera de rango [0, 1048575]"),
    ("beq x0, x0, 4096", 1, "inmediato 4096 fuera de rango [-4096, 4094]"),
    ("jal x0, 1048576", 1, "inmediato 1048576 fuera de rango [-1048576, 1048574]"),
    ("li x1, 4294967296", 1, "inmediato 4294967296 fuera de rango [-2147483648, 4294967295]"),
    ("beq x0, x0, 3", 1, "destino a desplazamiento impar (3)"),
    ("nop\nj loop2", 2, "etiqueta 'loop2' no definida"),
    ("nop\nnop\nnop\nloop: nop\nnop\nloop: nop", 6, "etiqueta 'loop' repetida (primera en línea 4)"),
    (".data", 1, "directiva no soportada '.data'"),
    ("nop\n.word 5", 2, "directiva no soportada '.word'"),
    ("addi x1, x0, 12z", 1, "inmediato inválido '12z'"),
]


@pytest.mark.parametrize("src,line,msg", ERRORS)
def test_errores(src: str, line: int, msg: str) -> None:
    with pytest.raises(AsmError) as exc:
        assemble(src)
    assert exc.value.line == line
    assert exc.value.msg == msg
    assert str(exc.value) == f"línea {line}: {msg}"


def test_primer_error_por_linea() -> None:
    # el 'li' inválido (línea 3) y la etiqueta repetida (línea 4) no tapan el error de la línea 1
    with pytest.raises(AsmError) as exc:
        assemble("foo x1\nnop\nli x1, 12z\na: nop\na: nop")
    assert exc.value.line == 1


def test_excede_imem() -> None:
    assert len(assemble("nop\n" * 255)) == 256
    with pytest.raises(AsmError) as exc:
        assemble("nop\n" * 256)
    assert exc.value.line == 0
    assert exc.value.msg == "programa de 257 palabras excede imem (256)"


def test_all32() -> None:
    words = assemble(ALL32.read_text(encoding="utf-8"))
    assert len(words) == 33
    assert words[-1] == 0x73
    assert len(set(w & 0x7F for w in words[:-1])) == 8


def test_cli_ok(tmp_path: Path) -> None:
    out = tmp_path / "out"
    r = subprocess.run([sys.executable, "-m", "asm.rvasm", str(ALL32), "-o", str(out)], cwd=SW)
    assert r.returncode == 0
    words = assemble(ALL32.read_text(encoding="utf-8"))
    assert (out / "all32.hex").read_text() == to_hex(words)
    assert (out / "all32.bin").read_bytes() == to_bin(words)


def test_cli_sin_o_escribe_junto_al_fuente(tmp_path: Path) -> None:
    src = tmp_path / "p.s"
    src.write_text("addi x1, x0, 5\n", encoding="utf-8")
    r = subprocess.run([sys.executable, "-m", "asm.rvasm", str(src)], cwd=SW)
    assert r.returncode == 0
    assert (tmp_path / "p.hex").read_text() == "00500093\n00000073\n"
    assert (tmp_path / "p.bin").read_bytes() == b"\x93\x00\x50\x00\x73\x00\x00\x00"


def test_cli_error(tmp_path: Path) -> None:
    src = tmp_path / "bad.s"
    src.write_text("nop\nadd x1, x2\n", encoding="utf-8")
    out = tmp_path / "out"
    r = subprocess.run([sys.executable, "-m", "asm.rvasm", str(src), "-o", str(out)], cwd=SW,
                       capture_output=True, text=True, encoding="utf-8",
                       env={**os.environ, "PYTHONIOENCODING": "utf-8"})
    assert r.returncode == 1
    assert r.stderr.strip() == f"{src}:2: error: 'add' espera 3 operandos, recibió 2"
    assert not out.exists() and not (tmp_path / "bad.hex").exists()


RARS_SRC = """\
li x1, 0x12345FFF
li x1, 0x00000800
li x1, 0xFFFFF800
li x1, 0x7FFFFFFF
li x1, -1
li x1, 0x12345000
loop: addi x1, x1, -1
bne x1, x0, loop
beq x0, x0, fin
nop
fin: halt
"""


def rars_words(src: Path, tmp_path: Path) -> list[int]:
    out = tmp_path / "rars.hex"
    r = subprocess.run([sys.executable, str(TOOLS / "rars_ref.py"), "encode", str(src), "-o", str(out)])
    assert r.returncode == 0
    return [int(line, 16) for line in out.read_text().split()]


@pytest.mark.skipif(not JAR.exists(), reason="sin RARS")
def test_rars_all32(tmp_path: Path) -> None:
    words = assemble(ALL32.read_text(encoding="utf-8"))
    assert rars_words(ALL32, tmp_path)[:len(words)] == words


@pytest.mark.skipif(not JAR.exists(), reason="sin RARS")
def test_rars_etiquetas_y_li(tmp_path: Path) -> None:
    src = tmp_path / "li_etiquetas.s"
    src.write_text(RARS_SRC, encoding="utf-8")
    words = assemble(RARS_SRC)
    assert rars_words(src, tmp_path)[:len(words)] == words

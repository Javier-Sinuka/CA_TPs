"""Desensamblador del subconjunto de 32 instrucciones (B-20). La salida vuelve a ensamblar a la misma palabra."""
from __future__ import annotations

from . import isa

_R = {v: k for k, v in isa.R_TYPE.items()}          # (funct3, funct7) -> nombre
_I = {v: k for k, v in isa.I_ARITH.items()}         # funct3 -> nombre
_SHIFT = {v: k for k, v in isa.I_SHIFT.items()}     # (funct3, funct7) -> nombre
_LOAD = {v: k for k, v in isa.LOADS.items()}
_STORE = {v: k for k, v in isa.STORES.items()}
_BRANCH = {v: k for k, v in isa.BRANCHES.items()}

UNKNOWN = "???"


def _sext(value: int, bits: int) -> int:
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def disasm(word: int) -> str:
    w = word & 0xFFFFFFFF
    op = w & 0x7F
    rd = (w >> 7) & 0x1F
    f3 = (w >> 12) & 0x7
    rs1 = (w >> 15) & 0x1F
    rs2 = (w >> 20) & 0x1F
    f7 = w >> 25

    if w == isa.HALT_WORD:
        return "halt"
    if w == 0x00000013:
        return "nop"
    if op == isa.OP_R:
        name = _R.get((f3, f7))
        return f"{name} x{rd}, x{rs1}, x{rs2}" if name else UNKNOWN
    if op == isa.OP_I:
        imm = _sext(w >> 20, 12)
        if f3 in (0b001, 0b101):
            name = _SHIFT.get((f3, f7))
            return f"{name} x{rd}, x{rs1}, {rs2}" if name else UNKNOWN
        name = _I.get(f3)
        return f"{name} x{rd}, x{rs1}, {imm}" if name else UNKNOWN
    if op == isa.OP_LOAD:
        name = _LOAD.get(f3)
        return f"{name} x{rd}, {_sext(w >> 20, 12)}(x{rs1})" if name else UNKNOWN
    if op == isa.OP_JALR:
        return f"jalr x{rd}, {_sext(w >> 20, 12)}(x{rs1})" if f3 == 0 else UNKNOWN
    if op == isa.OP_STORE:
        name = _STORE.get(f3)
        imm = _sext((f7 << 5) | rd, 12)
        return f"{name} x{rs2}, {imm}(x{rs1})" if name else UNKNOWN
    if op == isa.OP_BRANCH:
        name = _BRANCH.get(f3)
        imm = _sext(((w >> 31) << 12) | (((w >> 7) & 1) << 11) | (((w >> 25) & 0x3F) << 5)
                    | (((w >> 8) & 0xF) << 1), 13)
        return f"{name} x{rs1}, x{rs2}, {imm}" if name else UNKNOWN
    if op == isa.OP_JAL:
        imm = _sext(((w >> 31) << 20) | (((w >> 12) & 0xFF) << 12) | (((w >> 20) & 1) << 11)
                    | (((w >> 21) & 0x3FF) << 1), 21)
        return f"jal x{rd}, {imm}"
    if op == isa.OP_LUI:
        return f"lui x{rd}, 0x{w >> 12:05x}"
    return UNKNOWN


def disasm_at(words: list[int], pc: int) -> str:
    """Desensambla words[pc >> 2] si existe; si no, '???'."""
    idx = pc >> 2
    if 0 <= idx < len(words):
        return disasm(words[idx])
    return UNKNOWN

"""Ensamblador RV32I de dos pasadas (B-19).

CLI (cwd = TP3_FINAL/sw): py -m asm.rvasm <prog.s> [-o <dir>]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from . import isa

IMEM_WORDS = 256

_NUM = re.compile(r"^[+-]?(?:0[xX][0-9a-fA-F]+|[0-9]+)$")
_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_LABEL = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:")
_MEM = re.compile(r"^(.*)\(([^()]*)\)$")

_IMM12 = (-2048, 2047)


class AsmError(Exception):
    def __init__(self, line: int, msg: str) -> None:
        super().__init__(f"línea {line}: {msg}")
        self.line = line
        self.msg = msg


def _num(text: str, line: int) -> int:
    t = text.strip()
    if not _NUM.match(t):
        raise AsmError(line, f"inmediato inválido '{t}'")
    sign = -1 if t[0] == "-" else 1
    body = t.lstrip("+-")
    return sign * (int(body, 16) if body[:2].lower() == "0x" else int(body, 10))


def _reg(text: str, line: int) -> int:
    t = text.strip()
    if t.lower() not in isa.REGS:
        raise AsmError(line, f"registro inválido '{t}'")
    return isa.REGS[t.lower()]


def _range(v: int, lo: int, hi: int, line: int) -> int:
    if not lo <= v <= hi:
        raise AsmError(line, f"inmediato {v} fuera de rango [{lo}, {hi}]")
    return v


def _imm12(text: str, line: int) -> int:
    return _range(_num(text, line), *_IMM12, line)


def _mem(text: str, line: int) -> tuple[int, int]:
    """'imm(reg)' o '(reg)' -> (imm, reg)."""
    m = _MEM.match(text.strip())
    if not m:
        raise AsmError(line, f"operando de memoria inválido '{text.strip()}'")
    imm_text = m.group(1).strip()
    imm = _imm12(imm_text, line) if imm_text else 0
    return imm, _reg(m.group(2), line)


def _target(text: str, pc: int, labels: dict[str, tuple[int, int]], line: int) -> int:
    """Desplazamiento en bytes hacia una etiqueta o un número."""
    t = text.strip()
    if _IDENT.match(t):
        if t not in labels:
            raise AsmError(line, f"etiqueta '{t}' no definida")
        return labels[t][0] - pc
    return _num(t, line)


def _offset(off: int, lo: int, hi: int, line: int) -> int:
    if off % 2:
        raise AsmError(line, f"destino a desplazamiento impar ({off})")
    return _range(off, lo, hi, line)


def _expect(mn: str, ops: list[str], n: int, line: int) -> None:
    if len(ops) != n:
        raise AsmError(line, f"'{mn}' espera {n} operando{'' if n == 1 else 's'}, recibió {len(ops)}")


def _expect_any(mn: str, ops: list[str], allowed: tuple[int, ...], line: int) -> None:
    if len(ops) not in allowed:
        text = " o ".join(str(n) for n in allowed)
        raise AsmError(line, f"'{mn}' espera {text} operandos, recibió {len(ops)}")


def _li_parts(v: int) -> tuple[int, ...]:
    """(s,) si cabe en una palabra (addi), (hi, lo) si no (lui + addi). v ya está en [-2^31, 2^32-1]."""
    v &= 0xFFFFFFFF
    s = v - (1 << 32) if v >= 1 << 31 else v
    if -2048 <= s <= 2047:
        return (s,)
    hi = ((v + 0x800) >> 12) & 0xFFFFF
    lo = (v - (hi << 12)) & 0xFFFFFFFF
    if lo >= 1 << 31:
        lo -= 1 << 32
    return (hi, lo)


def _li_size(ops: list[str]) -> int:
    """Tamaño de un 'li' en la primera pasada; si es inválido, 1 (el error sale en la segunda)."""
    try:
        v = _num(ops[1], 0)
    except (AsmError, IndexError):
        return 1
    if not -(1 << 31) <= v <= (1 << 32) - 1:
        return 1
    return len(_li_parts(v))


def _encode(mn: str, ops: list[str], pc: int, labels: dict[str, tuple[int, int]], line: int) -> list[int]:
    m = mn.lower()
    if m in isa.R_TYPE:
        _expect(m, ops, 3, line)
        f3, f7 = isa.R_TYPE[m]
        return [isa.enc_r(isa.OP_R, f3, f7, _reg(ops[0], line), _reg(ops[1], line), _reg(ops[2], line))]
    if m in isa.I_ARITH:
        _expect(m, ops, 3, line)
        rd, rs1 = _reg(ops[0], line), _reg(ops[1], line)
        return [isa.enc_i(isa.OP_I, isa.I_ARITH[m], rd, rs1, _imm12(ops[2], line))]
    if m in isa.I_SHIFT:
        _expect(m, ops, 3, line)
        f3, f7 = isa.I_SHIFT[m]
        rd, rs1 = _reg(ops[0], line), _reg(ops[1], line)
        shamt = _range(_num(ops[2], line), 0, 31, line)
        return [isa.enc_r(isa.OP_I, f3, f7, rd, rs1, shamt)]
    if m in isa.LOADS:
        _expect(m, ops, 2, line)
        rd = _reg(ops[0], line)
        imm, rs1 = _mem(ops[1], line)
        return [isa.enc_i(isa.OP_LOAD, isa.LOADS[m], rd, rs1, imm)]
    if m in isa.STORES:
        _expect(m, ops, 2, line)
        rs2 = _reg(ops[0], line)
        imm, rs1 = _mem(ops[1], line)
        return [isa.enc_s(isa.OP_STORE, isa.STORES[m], rs1, rs2, imm)]
    if m in isa.BRANCHES:
        _expect(m, ops, 3, line)
        rs1, rs2 = _reg(ops[0], line), _reg(ops[1], line)
        off = _offset(_target(ops[2], pc, labels, line), -4096, 4094, line)
        return [isa.enc_b(isa.OP_BRANCH, isa.BRANCHES[m], rs1, rs2, off)]
    if m in ("jal", "j"):
        if m == "j":
            _expect(m, ops, 1, line)
            rd, dest = 0, ops[0]
        else:
            _expect_any(m, ops, (1, 2), line)
            rd, dest = (1, ops[0]) if len(ops) == 1 else (_reg(ops[0], line), ops[1])
        off = _offset(_target(dest, pc, labels, line), -1048576, 1048574, line)
        return [isa.enc_j(isa.OP_JAL, rd, off)]
    if m == "jalr":
        _expect_any(m, ops, (1, 2, 3), line)
        if len(ops) == 1:
            rd, rs1, imm = 1, _reg(ops[0], line), 0
        elif len(ops) == 2:
            rd = _reg(ops[0], line)
            imm, rs1 = _mem(ops[1], line)
        else:
            rd, rs1, imm = _reg(ops[0], line), _reg(ops[1], line), _imm12(ops[2], line)
        return [isa.enc_i(isa.OP_JALR, 0, rd, rs1, imm)]
    if m == "lui":
        _expect(m, ops, 2, line)
        rd = _reg(ops[0], line)
        return [isa.enc_u(isa.OP_LUI, rd, _range(_num(ops[1], line), 0, 0xFFFFF, line))]
    if m in ("halt", "ecall"):
        _expect(m, ops, 0, line)
        return [isa.HALT_WORD]
    if m == "nop":
        _expect(m, ops, 0, line)
        return [isa.enc_i(isa.OP_I, 0, 0, 0, 0)]
    if m == "ret":
        _expect(m, ops, 0, line)
        return [isa.enc_i(isa.OP_JALR, 0, 0, 1, 0)]
    if m == "mv":
        _expect(m, ops, 2, line)
        return [isa.enc_i(isa.OP_I, 0, _reg(ops[0], line), _reg(ops[1], line), 0)]
    if m == "li":
        _expect(m, ops, 2, line)
        rd = _reg(ops[0], line)
        v = _range(_num(ops[1], line), -(1 << 31), (1 << 32) - 1, line)
        parts = _li_parts(v)
        if len(parts) == 1:
            return [isa.enc_i(isa.OP_I, 0, rd, 0, parts[0])]
        return [isa.enc_u(isa.OP_LUI, rd, parts[0]), isa.enc_i(isa.OP_I, 0, rd, rd, parts[1])]
    raise AsmError(line, f"instrucción desconocida '{mn}'")


def assemble(src: str) -> list[int]:
    """Palabras de 32 bits; levanta AsmError con el primer error (por número de línea)."""
    errors: list[AsmError] = []
    labels: dict[str, tuple[int, int]] = {}          # nombre -> (dirección, línea)
    items: list[tuple[int, str, list[str], int]] = []  # (línea, mnemónico, operandos, pc)

    pc = 0
    for n, raw in enumerate(src.splitlines(), 1):
        text = raw.split("#", 1)[0].strip()
        while True:
            m = _LABEL.match(text)
            if not m:
                break
            name = m.group(1)
            if name in labels:
                errors.append(AsmError(n, f"etiqueta '{name}' repetida (primera en línea {labels[name][1]})"))
            else:
                labels[name] = (pc, n)
            text = text[m.end():].strip()
        if not text:
            continue
        if text.startswith("."):
            d = text.split()[0]
            if d.lower() != ".text":
                errors.append(AsmError(n, f"directiva no soportada '{d}'"))
            continue
        parts = text.split(None, 1)
        mn = parts[0]
        ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
        items.append((n, mn, ops, pc))
        pc += 4 * (_li_size(ops) if mn.lower() == "li" else 1)

    words: list[int] = []
    for n, mn, ops, ipc in items:
        try:
            words += _encode(mn, ops, ipc, labels, n)
        except AsmError as e:
            errors.append(e)
    if errors:
        raise min(errors, key=lambda e: e.line)

    if not words or words[-1] != isa.HALT_WORD:
        words.append(isa.HALT_WORD)
    if len(words) > IMEM_WORDS:
        raise AsmError(0, f"programa de {len(words)} palabras excede imem ({IMEM_WORDS})")
    return words


def to_hex(words: list[int]) -> str:
    return "".join(f"{w & 0xFFFFFFFF:08x}\n" for w in words)


def to_bin(words: list[int]) -> bytes:
    return b"".join((w & 0xFFFFFFFF).to_bytes(4, "little") for w in words)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="asm.rvasm")
    ap.add_argument("source")
    ap.add_argument("-o", dest="outdir", help="directorio de salida (por defecto, junto al .s)")
    a = ap.parse_args(argv)
    src_path = Path(a.source)
    try:
        words = assemble(src_path.read_text(encoding="utf-8-sig"))
    except AsmError as e:
        print(f"{a.source}:{e.line}: error: {e.msg}", file=sys.stderr)
        return 1
    outdir = Path(a.outdir) if a.outdir else src_path.parent
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / f"{src_path.stem}.hex").write_bytes(to_hex(words).encode("ascii"))
    (outdir / f"{src_path.stem}.bin").write_bytes(to_bin(words))
    return 0


if __name__ == "__main__":
    sys.exit(main())

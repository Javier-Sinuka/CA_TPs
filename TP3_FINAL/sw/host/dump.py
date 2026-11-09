"""Codificación y decodificación del dump v1 (doc/documentation/dump.md)."""
from __future__ import annotations

import struct
from dataclasses import dataclass

HEADER = 0xA5
FORMAT_VERSION = 0x01
N_FIXED_WORDS = 52          # W0..W51
N_REGS = 32
N_LATCHES = 16
MAX_DIRTY = 256
MASK32 = 0xFFFF_FFFF


class DumpError(Exception):
    """Dump mal formado: cabecera, largo o checksum."""


# (campo, bit menos significativo, ancho) - dump.md §3.1
_INFO_FIELDS: tuple[tuple[str, int, int], ...] = (
    ("rd", 0, 5), ("rs1", 5, 5), ("rs2", 10, 5), ("funct3", 15, 3),
    ("alu_op", 18, 4), ("alu_src_b", 22, 1), ("mem_read", 23, 1),
    ("mem_write", 24, 1), ("mem_to_reg", 25, 1), ("reg_write", 26, 1),
    ("branch", 27, 1), ("jump", 28, 1), ("jalr", 29, 1), ("lui", 30, 1),
    ("halt", 31, 1),
)


@dataclass(frozen=True)
class LatchInfo:
    rd: int = 0
    rs1: int = 0
    rs2: int = 0
    funct3: int = 0
    alu_op: int = 0
    alu_src_b: bool = False
    mem_read: bool = False
    mem_write: bool = False
    mem_to_reg: bool = False
    reg_write: bool = False
    branch: bool = False
    jump: bool = False
    jalr: bool = False
    lui: bool = False
    halt: bool = False

    @staticmethod
    def unpack(word: int) -> "LatchInfo":
        fields: dict[str, int | bool] = {}
        for name, lsb, width in _INFO_FIELDS:
            value = (word >> lsb) & ((1 << width) - 1)
            fields[name] = bool(value) if width == 1 else value
        return LatchInfo(**fields)  # type: ignore[arg-type]

    def pack(self) -> int:
        word = 0
        for name, lsb, width in _INFO_FIELDS:
            value = int(getattr(self, name))
            if not 0 <= value < (1 << width):
                raise ValueError(f"{name}={value} no entra en {width} bits")
            word |= value << lsb
        return word


@dataclass(frozen=True)
class Dump:
    halted: bool
    timeout: bool
    aborted: bool
    version: int
    cycles: int
    pc: int
    x: tuple[int, ...]                  # 32 valores
    latches: tuple[int, ...]            # 16 palabras crudas
    mem: tuple[tuple[int, int], ...]    # (dirección en bytes, dato), ascendente

    @property
    def info_ex(self) -> LatchInfo:
        return LatchInfo.unpack(self.latches[6])

    @property
    def info_mem(self) -> LatchInfo:
        return LatchInfo.unpack(self.latches[10])

    @property
    def info_wb(self) -> LatchInfo:
        return LatchInfo.unpack(self.latches[14])

    def _flag(self, bit: int) -> bool:
        return bool((self.latches[15] >> bit) & 1)

    @property
    def valid_id(self) -> bool:
        return self._flag(0)

    @property
    def valid_ex(self) -> bool:
        return self._flag(1)

    @property
    def valid_mem(self) -> bool:
        return self._flag(2)

    @property
    def valid_wb(self) -> bool:
        return self._flag(3)

    @property
    def load_use_stall(self) -> bool:
        return self._flag(5)

    @property
    def take_ex(self) -> bool:
        return self._flag(6)

    @property
    def stop_fetch(self) -> bool:
        return self._flag(7)


def expected_length(m: int) -> int:
    """Largo total en bytes de un dump con m palabras sucias."""
    return 1 + 4 * N_FIXED_WORDS + 8 * m + 1


def _status_word(d: Dump) -> int:
    return (int(d.halted) | (int(d.timeout) << 1) | (int(d.aborted) << 2)
            | ((d.version & 0xFF) << 8))


def encode(d: Dump) -> bytes:
    if len(d.x) != N_REGS or len(d.latches) != N_LATCHES:
        raise ValueError("x debe tener 32 valores y latches 16")
    if len(d.mem) > MAX_DIRTY:
        raise ValueError("más de 256 palabras sucias")
    words = [_status_word(d), d.cycles, d.pc, *d.x, *d.latches, len(d.mem)]
    for addr, data in d.mem:
        words += [addr, data]
    body = b"".join(struct.pack("<I", w & MASK32) for w in words)
    return bytes([HEADER]) + body + bytes([sum(body) & 0xFF])


def decode(b: bytes) -> Dump:
    b = bytes(b)
    if len(b) < expected_length(0):
        raise DumpError(f"dump corto: {len(b)} bytes, mínimo {expected_length(0)}")
    if b[0] != HEADER:
        raise DumpError(f"cabecera 0x{b[0]:02x}, se esperaba 0x{HEADER:02x}")
    m = struct.unpack_from("<I", b, 1 + 4 * 51)[0]
    if m > MAX_DIRTY:
        raise DumpError(f"M = {m} > {MAX_DIRTY}")
    if len(b) != expected_length(m):
        raise DumpError(f"largo {len(b)}, se esperaba {expected_length(m)} para M = {m}")
    body = b[1:-1]
    if sum(body) & 0xFF != b[-1]:
        raise DumpError(f"checksum 0x{b[-1]:02x}, calculado 0x{sum(body) & 0xFF:02x}")
    words = struct.unpack(f"<{len(body) // 4}I", body)
    status = words[0]
    pairs = words[N_FIXED_WORDS:]
    return Dump(
        halted=bool(status & 1),
        timeout=bool((status >> 1) & 1),
        aborted=bool((status >> 2) & 1),
        version=(status >> 8) & 0xFF,
        cycles=words[1],
        pc=words[2],
        x=tuple(words[3:35]),
        latches=tuple(words[35:51]),
        mem=tuple((pairs[2 * i], pairs[2 * i + 1]) for i in range(m)),
    )

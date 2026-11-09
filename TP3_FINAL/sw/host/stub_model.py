"""Modelo Python de cpu_stub.v (doc/documentation/interfaz_cpu.md §8)."""
from __future__ import annotations

from host.dump import FORMAT_VERSION, MASK32, Dump

DIRTY_WORDS = (4, 16, 63)


def stub_dump(cycles: int, halt_at: int, timeout: bool = False,
              aborted: bool = False) -> Dump:
    """Dump que la Debug Unit tiene que enviar con el stub en `cycles` ciclos."""
    if cycles < 0 or (halt_at != 0 and cycles > halt_at):
        raise ValueError(f"cycles={cycles} imposible con halt_at={halt_at}")
    halted = halt_at != 0 and cycles == halt_at
    x = tuple(0 if i == 0 else (((cycles & 0xFF_FFFF) << 8) | i) for i in range(32))
    latches = tuple(0x1A00_0000 | (k << 16) | (cycles & 0xFFFF) for k in range(16))
    mem = tuple((i * 4, 0xD000_0000 | i) for i in DIRTY_WORDS) if cycles >= 1 else ()
    return Dump(halted=halted, timeout=timeout, aborted=aborted,
                version=FORMAT_VERSION, cycles=cycles & MASK32,
                pc=(cycles << 2) & MASK32, x=x, latches=latches, mem=mem)


def stub_state_words(cycles: int, halt_at: int) -> list[int]:
    """Estado del stub visto por sus puertos, en el orden de tb_cpu_stub (563 palabras):
    [0] o_dbg_pc, [1] o_imem_addr, [2] o_halted, [3..34] x0..x31,
    [35..50] latch 0..15, [51..306] dirty de la palabra 0..255, [307..562] dato 0..255."""
    d = stub_dump(cycles, halt_at)
    data = {addr // 4: value for addr, value in d.mem}
    return ([d.pc, d.pc, int(d.halted)] + list(d.x) + list(d.latches)
            + [1 if i in data else 0 for i in range(256)]
            + [data.get(i, 0) for i in range(256)])

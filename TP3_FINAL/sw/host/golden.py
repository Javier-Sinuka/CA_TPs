"""Comparación del estado de la placa contra el golden model (ISS) (B-26 §B).

Lógica pura: ejecuta `iss.exe` sobre el programa cargado y compara x1..x31 y la memoria
de datos con un dump. Las claves de divergencia son "x5" y "mem[0x00000008]".
"""
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

from host import proto
from host.dump import Dump


def retired_after(dumps: list[Dump]) -> int:
    """Instrucciones retiradas tras `len(dumps) - 1` pasos.

    r(n) = cantidad de dumps D0 .. D(n-1) con valid_wb = 1 y info_wb.halt = 0: la instrucción
    que está en WB en un dump escribe en el flanco del paso siguiente, por eso el último
    dump no cuenta.
    """
    return sum(1 for d in dumps[:-1] if d.valid_wb and not d.info_wb.halt)


def store_en_wb(dumps: list[Dump]) -> bool:
    """El último dump tiene un store en WB: ya escribió dmem, pero `retired_after` no lo cuenta.

    `dmem` se escribe en el flanco que termina MEM, un paso antes de que el store escriba en WB
    (que es lo que cuenta `retired_after`). El store en WB del último dump es el que estaba en
    MEM del dump anterior (`valid_mem` y `info_mem.mem_write`); la memoria se compara entonces
    contra el ISS con una instrucción más retirada que los registros (C-02).
    """
    if len(dumps) < 2:
        return False
    prev, cur = dumps[-2], dumps[-1]
    return (prev.valid_mem and prev.info_mem.mem_write
            and cur.valid_wb and not cur.info_wb.halt)


class Golden:
    def __init__(self, iss_exe: str | Path, words: list[int]) -> None:
        self._exe = str(iss_exe)
        self._tmp = tempfile.TemporaryDirectory(prefix="golden_")
        self._hex = Path(self._tmp.name) / "prog.hex"
        padded = list(words) + [proto.HALT_WORD] * (proto.IMEM_WORDS - len(words))
        self._hex.write_text("".join(f"{w:08x}\n" for w in padded), encoding="ascii")
        self._cache: dict[int | None, dict] = {}

    def close(self) -> None:
        self._tmp.cleanup()

    def _run(self, max_instr: int | None) -> dict:
        if max_instr not in self._cache:
            cmd = [self._exe, str(self._hex), "--full"]
            if max_instr is not None:
                cmd += ["--max-instr", str(max_instr)]
            r = subprocess.run(cmd, capture_output=True)
            if r.returncode != 0:
                raise RuntimeError(f"iss.exe terminó con código {r.returncode}: "
                                   f"{r.stderr.decode('utf-8', 'replace').strip()}")
            self._cache[max_instr] = json.loads(r.stdout)
        return self._cache[max_instr]

    def state_after(self, retired: int) -> dict:
        """Estado canónico del ISS tras `retired` instrucciones."""
        return self._run(retired)

    def final_state(self) -> dict:
        """Estado canónico del ISS al terminar (HALT o su límite por defecto)."""
        return self._run(None)

    def diverging(self, d: Dump, retired: int, mem_retired: int | None = None) -> set[str]:
        """Claves donde `d` difiere del ISS tras `retired` instrucciones.

        La memoria se compara tras `mem_retired` (por defecto, las mismas `retired`).
        """
        mem_state = None if mem_retired is None else self.state_after(mem_retired)
        return _compare(d, self.state_after(retired), mem_state)

    def diverging_final(self, d: Dump) -> set[str]:
        """Claves donde `d` difiere del estado final del ISS (tras `Ejecutar`)."""
        return _compare(d, self.final_state())


def check(golden: Golden | None, dumps: list[Dump], ran: bool) -> tuple[set[str], str]:
    """Política de comparación de la GUI: (claves divergentes, texto de estado).

    `dumps` son los dumps del diagrama (D0 = tras load/reset); `ran` indica que hubo un
    `Ejecutar` desde el último load/reset (después de él no se conoce la cantidad de
    instrucciones retiradas, así que solo se compara el estado final con el ISS).
    """
    if golden is None:
        return set(), "sin golden"
    d = dumps[-1]
    if ran:
        if d.halted:
            keys = golden.diverging_final(d)
        elif d.timeout:
            return set(), "sin comparar (timeout)"
        elif d.aborted:
            return set(), "sin comparar (abortado)"
        else:
            return set(), "sin comparar (tras Ejecutar)"
    else:
        r = retired_after(dumps)
        keys = golden.diverging(d, r, r + 1 if store_en_wb(dumps) else r)
    return keys, f"golden: {len(keys)} divergencias" if keys else "golden: ok"


def _compare(d: Dump, state: dict, mem_state: dict | None = None) -> set[str]:
    out: set[str] = set()
    for i in range(1, 32):
        if d.x[i] != int(state["x"][i], 16):
            out.add(f"x{i}")
    got = dict(d.mem)
    want = {int(a, 16): int(v, 16) for a, v in (mem_state or state)["mem"]}
    for addr in got.keys() | want.keys():
        if got.get(addr) != want.get(addr):
            out.add(f"mem[0x{addr:08x}]")
    return out

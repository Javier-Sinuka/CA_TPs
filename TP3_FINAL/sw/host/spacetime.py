"""Diagrama espacio-tiempo del pipeline a partir de dumps consecutivos (B-26 §A).

Lógica pura: sin I/O ni tkinter. Entrada: D0, D1, ... (D0 = estado tras load/reset,
cada Dk = estado tras un paso). Salida: una fila por instancia dinámica de instrucción.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from asm.disasm import disasm_at
from host.dump import Dump

STAGES = ("IF", "ID", "EX", "MEM", "WB")


@dataclass
class Row:
    pc: int
    # columna -> "IF", "ID", "EX", "MEM", "WB", "IF*", "ID*" (stall), "IF×", "ID×" (anulada)
    cells: dict[int, str] = field(default_factory=dict)


def stage_pcs(d: Dump) -> dict[str, int]:
    """pc de cada etapa válida del dump."""
    out: dict[str, int] = {}
    if not d.stop_fetch and not d.halted:
        out["IF"] = d.pc
    if d.valid_id:
        out["ID"] = d.latches[0]
    if d.valid_ex:
        out["EX"] = d.latches[2]
    if d.valid_mem:
        out["MEM"] = d.latches[7]
    if d.valid_wb:
        out["WB"] = d.latches[11]
    return out


def build(dumps: list[Dump]) -> list[Row]:
    rows: list[Row] = []
    prev: Dump | None = None
    prev_pcs: dict[str, int] = {}
    prev_assign: dict[str, int] = {}
    for t, d in enumerate(dumps):
        pcs = stage_pcs(d)
        assign: dict[str, int] = {}
        taken: set[int] = set()
        for s in reversed(STAGES):                      # WB, MEM, EX, ID, IF
            if s not in pcs:
                continue
            x = pcs[s]
            idx = STAGES.index(s)
            row: int | None = None
            label = s
            if prev is not None:
                if idx > 0:
                    before = STAGES[idx - 1]
                    r = prev_assign.get(before)
                    if r is not None and prev_pcs[before] == x and r not in taken:
                        row = r
                if row is None and s in ("IF", "ID") and prev.load_use_stall:
                    r = prev_assign.get(s)
                    if r is not None and prev_pcs[s] == x and r not in taken:
                        row = r
                        label = s + "*"
            if row is None:
                rows.append(Row(pc=x))
                row = len(rows) - 1
            rows[row].cells[t] = label
            assign[s] = row
            taken.add(row)
        if prev is not None:
            present = set(assign.values())
            cancelled = []
            if prev.take_ex:
                cancelled += ["IF", "ID"]
            if prev.stop_fetch:
                cancelled.append("ID")
            for s in cancelled:
                r = prev_assign.get(s)
                if r is not None and r not in present:
                    rows[r].cells[t - 1] = s + "×"
        prev, prev_pcs, prev_assign = d, pcs, assign
    return rows


def row_label(row: Row, words: list[int]) -> str:
    return f"0x{row.pc:08x} {disasm_at(words, row.pc)}"

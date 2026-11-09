"""Formato canónico de resultados (doc/documentation/dump.md §6)."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from host.dump import Dump


def hex32(value: int) -> str:
    return f"0x{value & 0xFFFF_FFFF:08x}"


def from_dump(d: Dump) -> dict[str, Any]:
    """Dump de una parada (halted o timeout) a formato canónico."""
    if d.halted:
        stop = "halt"
    elif d.timeout:
        stop = "limit"
    else:
        raise ValueError("el dump no es de una parada: ni halted ni timeout")
    return {
        "stop": stop,
        "pc": hex32(d.latches[11]) if stop == "halt" else None,
        "x": [hex32(v) for v in d.x],
        "mem": [[hex32(a), hex32(v)] for a, v in d.mem],
    }


def load(path: str | Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def save(result: dict[str, Any], path: str | Path) -> None:
    Path(path).write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")


def diff(a: dict[str, Any], b: dict[str, Any], la: str = "a", lb: str = "b") -> list[str]:
    """Una línea por diferencia. Lista vacía = iguales."""
    if a["stop"] != b["stop"]:
        return [f"stop: {la}={a['stop']} {lb}={b['stop']}"]
    if a["stop"] == "limit":
        return []
    out: list[str] = []
    if a["pc"] != b["pc"]:
        out.append(f"pc: {la}={a['pc']} {lb}={b['pc']}")
    for i, (va, vb) in enumerate(zip(a["x"], b["x"])):
        if va != vb:
            out.append(f"x{i}: {la}={va} {lb}={vb}")
    ma = {addr: val for addr, val in a["mem"]}
    mb = {addr: val for addr, val in b["mem"]}
    for addr in sorted(set(ma) | set(mb), key=lambda s: int(s, 16)):
        va, vb = ma.get(addr, "-"), mb.get(addr, "-")
        if va != vb:
            out.append(f"mem[{addr}]: {la}={va} {lb}={vb}")
    return out

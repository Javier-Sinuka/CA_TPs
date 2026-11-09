"""Guion de B-16 contra la placa con el stub (B-17).

Uso (cwd = TP3_FINAL/sw):
    py -m host.guion_debug --port COM5 --repeat 20
Corre `--repeat` veces los 10 pasos de la tabla de B-16 (V, L A, 5 x S, R, D, X, L B, R B,
invalido, D final) usando solo la API pública de `Link`, y compara cada dump con
`stub_dump`. Código de salida: 0 si salen N de N repeticiones, 1 si falla alguna, 2 si no se
pudo abrir el puerto.
"""
from __future__ import annotations

import argparse
import dataclasses
import sys

from host import proto
from host.dump import Dump
from host.link import Link, LinkError, Version
from host.stub_model import stub_dump

HALT_AT = 20
PROG_A = [0xA000_0000 + i for i in range(37)]
PROG_B = [0x0050_0093, 0x0000_0073]


class GuionError(Exception):
    """Un paso del guion no dio lo esperado."""

    def __init__(self, step: str, detail: str) -> None:
        self.step = step
        self.detail = detail
        super().__init__(f"{step}: {detail}")


def _diff(got: Dump, want: Dump) -> str:
    parts = []
    for f in dataclasses.fields(Dump):
        a, b = getattr(got, f.name), getattr(want, f.name)
        if a == b:
            continue
        if isinstance(a, tuple):
            idx = [i for i, (p, q) in enumerate(zip(a, b)) if p != q]
            parts.append(f"{f.name} distinto (primer índice {idx[0] if idx else min(len(a), len(b))})")
        else:
            parts.append(f"{f.name} recibido {a!r}, esperado {b!r}")
    return "dump distinto: " + "; ".join(parts)


def _check_dump(step: str, got: Dump, want: Dump) -> None:
    if got != want:
        raise GuionError(step, _diff(got, want))


def run_once(link: Link) -> None:
    """Una repetición del guion. Lanza GuionError con el paso que falló."""
    step = "V"
    final = stub_dump(HALT_AT, HALT_AT)
    try:
        want = Version(proto.PROTO_VERSION, proto.IMEM_WORDS, proto.DMEM_WORDS)
        got = link.connect()
        if got != want:
            raise GuionError(step, f"versión {got}, esperada {want}")
        step = "L A"
        link.load(PROG_A)
        for k in range(1, 6):
            step = f"S {k}"
            _check_dump(step, link.step(), stub_dump(k, HALT_AT))
        step = "R"
        _check_dump(step, link.run(), final)
        step = "D"
        _check_dump(step, link.dump(), final)
        step = "X"
        link.reset()
        step = "L B"
        link.load(PROG_B)
        step = "R B"
        _check_dump(step, link.run(), final)
        step = "invalido"
        code = link.raw_error(0x7A)
        if code != proto.ERR_UNKNOWN_CMD:
            raise GuionError(step, f"código de error {code}, esperado {proto.ERR_UNKNOWN_CMD}")
        step = "D final"
        _check_dump(step, link.dump(), final)
    except LinkError as e:
        raise GuionError(step, str(e)) from e


def run(link: Link, repeat: int, out=print) -> int:
    """Corre `repeat` repeticiones; devuelve cuántas salieron bien."""
    ok = 0
    for n in range(1, repeat + 1):
        try:
            run_once(link)
        except GuionError as e:
            out(f"rep {n}: FAIL {e.step}: {e.detail}")
        else:
            out(f"rep {n}: OK")
            ok += 1
    return ok


def main(argv: list[str] | None = None, opener=Link.open) -> int:
    p = argparse.ArgumentParser(description="Guion de B-16 contra la placa con el stub")
    p.add_argument("--port", required=True, help="por ejemplo COM5")
    p.add_argument("--repeat", type=int, default=20)
    p.add_argument("--baud", type=int, default=proto.BAUD_RATE)
    a = p.parse_args(argv)
    if a.repeat < 1:
        p.error("--repeat debe ser >= 1")
    try:
        link = opener(a.port, a.baud)
    except OSError as e:
        print(f"error: no se pudo abrir {a.port}: {e}", file=sys.stderr)
        return 2
    try:
        ok = run(link, a.repeat)
    finally:
        link.close()
    verdict = "PASS" if ok == a.repeat else "FAIL"
    print(f"{verdict} guion_debug: {ok}/{a.repeat}")
    return 0 if ok == a.repeat else 1


if __name__ == "__main__":
    sys.exit(main())

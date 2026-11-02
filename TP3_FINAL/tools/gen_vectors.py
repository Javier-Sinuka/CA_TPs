"""Genera los vectores esperados de los TB de la Debug Unit desde stub_model.

Uso, desde la raíz del repo:
    py TP3_FINAL/tools/gen_vectors.py           # escribe los archivos
    py TP3_FINAL/tools/gen_vectors.py --check   # devuelve 1 si alguno difiere
Formato: dump_*.hex = un byte por línea (2 dígitos hex); stub_state_*.hex =
una palabra por línea (8 dígitos hex). Minúsculas, fin de línea LF.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

TP3 = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TP3 / "sw"))

from host.dump import encode  # noqa: E402
from host.stub_model import stub_dump, stub_state_words  # noqa: E402

OUT = TP3 / "VIVADO" / "TP_FINAL" / "tb" / "debug" / "vectors"


def _bytes(b: bytes) -> str:
    return "".join(f"{v:02x}\n" for v in b)


def _words(ws: list[int]) -> str:
    return "".join(f"{w & 0xFFFF_FFFF:08x}\n" for w in ws)


def vectors() -> dict[str, str]:
    v: dict[str, str] = {}
    for c in (0, 1, 7, 20):
        v[f"stub_state_c{c}_h20.hex"] = _words(stub_state_words(c, 20))
    v["stub_state_c25_h0.hex"] = _words(stub_state_words(25, 0))
    for c in [*range(0, 11), 20]:
        v[f"dump_c{c}_h20.hex"] = _bytes(encode(stub_dump(c, 20)))
    v["dump_c0_h0.hex"] = _bytes(encode(stub_dump(0, 0)))
    v["dump_c1000_h0_t.hex"] = _bytes(encode(stub_dump(1000, 0, timeout=True)))
    return v


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    expected = vectors()
    bad: list[str] = []
    OUT.mkdir(parents=True, exist_ok=True)
    for name, text in sorted(expected.items()):
        path = OUT / name
        if args.check:
            if not path.exists() or path.read_text(encoding="ascii") != text:
                bad.append(name)
        else:
            path.write_text(text, encoding="ascii", newline="\n")
    extra = sorted(p.name for p in OUT.glob("*.hex") if p.name not in expected)
    if args.check and extra:
        bad += [f"{n} (sobra)" for n in extra]
    if bad:
        print("FAIL vectors: " + ", ".join(bad))
        return 1
    print(f"PASS vectors: {len(expected)} archivos")
    return 0


if __name__ == "__main__":
    sys.exit(main())

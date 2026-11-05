"""Referencia RARS: ensambla un .s con RARS 1.6 y vuelca .text en hex (B-19, §F).

Uso: py TP3_FINAL/tools/rars_ref.py encode <prog.s> -o <out.hex>
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parents[1]
BUILD = REPO / "TP3_FINAL" / "build"
JAR = TOOLS / "rars1_6.jar"

_LABELS = re.compile(r"^\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)*")
_HALT = re.compile(r"\bhalt\b", re.IGNORECASE)


def prepare(src: str) -> str:
    """halt -> ecall; agrega ecall al final si la última instrucción no es halt/ecall."""
    out: list[str] = []
    last = ""
    for line in src.splitlines():
        code, sep, comment = line.partition("#")
        code = _HALT.sub("ecall", code)
        out.append(code + sep + comment)
        body = code[_LABELS.match(code).end():].strip()
        if body:
            last = body.split()[0].lower()
    if last != "ecall":
        out.append("ecall")
    return "\n".join(out) + "\n"


def encode(src: Path, out: Path) -> int:
    if not JAR.exists():
        print("falta TP3_FINAL/tools/rars1_6.jar (ver B-19)")
        return 2
    work = BUILD / "rars"
    work.mkdir(parents=True, exist_ok=True)
    prepared = work / f"{src.stem}.s"
    prepared.write_text(prepare(src.read_text(encoding="utf-8-sig")), encoding="utf-8")
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["java", "-jar", str(JAR), "a", "mc", "CompactTextAtZero",
           "dump", ".text", "HexText", str(out.resolve()), str(prepared)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.stdout.write(res.stdout)
        sys.stderr.write(res.stderr)
    return res.returncode


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="rars_ref.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    pe = sub.add_parser("encode")
    pe.add_argument("source", type=Path)
    pe.add_argument("-o", dest="out", type=Path, required=True)
    a = ap.parse_args(argv)
    return encode(a.source, a.out)


if __name__ == "__main__":
    sys.exit(main())

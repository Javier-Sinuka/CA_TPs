"""Genera .hex, .bin y .expected.json de TP3_FINAL/programs/*.s con el ISS (B-22).

Uso (desde la raíz del repo): py TP3_FINAL/tools/gen_expected.py
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

TP3 = Path(__file__).resolve().parents[1]
SW = TP3 / "sw"
PROGRAMS = TP3 / "programs"
BUILD = TP3 / "build"
ISS_SRC = [SW / "iss" / "iss.cpp", SW / "iss" / "iss_main.cpp"]
ISS_EXE = BUILD / "iss.exe"


def build_iss() -> None:
    """Igual que conftest.build_iss(): compila build/iss.exe si falta o si algún fuente es más nuevo."""
    BUILD.mkdir(exist_ok=True)
    newest = max(p.stat().st_mtime for p in ISS_SRC + [SW / "iss" / "iss.hpp"])
    if not ISS_EXE.exists() or ISS_EXE.stat().st_mtime < newest:
        cmd = ["g++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
               "-o", str(ISS_EXE), *map(str, ISS_SRC)]
        subprocess.run(cmd, check=True)


def main() -> int:
    build_iss()
    for src in sorted(PROGRAMS.glob("*.s")):
        base = src.stem
        r = subprocess.run([sys.executable, "-m", "asm.rvasm", str(src), "-o", str(PROGRAMS)], cwd=SW)
        if r.returncode != 0:
            return r.returncode
        expected = PROGRAMS / f"{base}.expected.json"
        r = subprocess.run([str(ISS_EXE), str(PROGRAMS / f"{base}.hex"), "-o", str(expected)])
        if r.returncode != 0:
            return r.returncode
        d = json.loads(expected.read_text(encoding="utf-8"))
        print(f"{base}: {d['stop']} pc={d['pc']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

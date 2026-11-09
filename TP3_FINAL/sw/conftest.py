"""Configuración común de pytest para TP3_FINAL/sw."""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

SW = Path(__file__).resolve().parent
TP3 = SW.parent
BUILD = TP3 / "build"
ISS_SRC = [SW / "iss" / "iss.cpp", SW / "iss" / "iss_main.cpp"]
ISS_EXE = BUILD / "iss.exe"


def build_iss() -> Path:
    """Compila build/iss.exe si falta o si algún fuente es más nuevo."""
    if not ISS_SRC[0].exists():
        pytest.skip("sw/iss/iss.cpp todavía no existe (B-21)")
    BUILD.mkdir(exist_ok=True)
    newest = max(p.stat().st_mtime for p in ISS_SRC + [SW / "iss" / "iss.hpp"])
    if not ISS_EXE.exists() or ISS_EXE.stat().st_mtime < newest:
        cmd = ["g++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
               "-o", str(ISS_EXE), *map(str, ISS_SRC)]
        subprocess.run(cmd, check=True)
    return ISS_EXE


@pytest.fixture(scope="session")
def iss_exe() -> Path:
    return build_iss()

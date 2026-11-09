"""B-27: la regresión (tools/regress.py) detecta un bug inyectado y pasa con el ISS real."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

TP3 = Path(__file__).resolve().parents[2]
REPO = TP3.parent
RUN = TP3 / "tools" / "run.py"


def regress(*args: str) -> subprocess.CompletedProcess:
    env = {**os.environ, "PYTHONIOENCODING": "utf-8"}
    return subprocess.run([sys.executable, str(RUN), "regress", *args], cwd=REPO,
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace", env=env)


def test_mutante_sra_se_detecta(iss_exe):
    r = regress("--levels", "iss", "--iss-mutant", "sra")
    assert r.returncode == 1, r.stdout
    assert "alu_nodep [iss] x10: esperado=0xffffffff iss=0x01ffffff" in r.stdout.splitlines()
    rows = {line.split()[0]: line.split()[1] for line in r.stdout.splitlines()[1:10]}
    assert rows["alu_nodep"] == "FAIL"
    assert rows["suma"] == "OK"


def test_iss_y_fake_pasan(iss_exe):
    r = regress("--levels", "iss,fake")
    assert r.returncode == 0, r.stdout
    assert "FALLAS" not in r.stdout
    assert "suma         OK    OK" in r.stdout


def test_un_programa(iss_exe):
    r = regress("--levels", "iss", "--program", "suma")
    assert r.returncode == 0, r.stdout
    rows = [line.split() for line in r.stdout.splitlines()]
    assert ["suma", "OK", "-", "-", "-"] in rows
    assert not any(row and row[0] == "branches" for row in rows)


def test_programa_inexistente():
    r = regress("--program", "no_existe")
    assert r.returncode == 2
    assert "no existe programs/no_existe.s" in r.stdout


def test_mutante_sin_nivel_iss():
    r = regress("--levels", "fake", "--iss-mutant", "sra")
    assert r.returncode == 2


def test_board_sin_puerto():
    r = regress("--levels", "iss,board")
    assert r.returncode == 2
    assert "--board" in r.stdout

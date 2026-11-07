from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from asm.rvasm import assemble, to_bin
from host import canonical

SW = Path(__file__).resolve().parents[1]
TP3 = SW.parent
PROGRAMS = TP3 / "programs"
RARS_REF = TP3 / "tools" / "rars_ref.py"
RARS_JAR = TP3 / "tools" / "rars1_6.jar"

NAMES = ["alu_nodep", "branches", "call_ret", "const32", "load_use",
         "mem_bytes", "no_halt", "raw_hazards", "suma"]

_EXPECT = re.compile(r"^#\s*expect:\s*(.*)$", re.MULTILINE)
_IGNORE = re.compile(r"^#\s*rars-ignore:\s*(.*)$", re.MULTILINE)
_NO_RARS = re.compile(r"^#\s*rars:\s*no\s*$", re.MULTILINE)


def _expects(src: str) -> list[str]:
    return [tok for m in _EXPECT.finditer(src) for tok in m.group(1).split()]


def test_cantidad():
    assert sorted(p.stem for p in PROGRAMS.glob("*.s")) == NAMES


@pytest.mark.parametrize("name", NAMES)
def test_al_dia(name):
    src = (PROGRAMS / f"{name}.s").read_text(encoding="utf-8")
    words = assemble(src)
    hex_words = [int(line, 16) for line in (PROGRAMS / f"{name}.hex").read_text().split()]
    assert words == hex_words
    assert to_bin(words) == (PROGRAMS / f"{name}.bin").read_bytes()


@pytest.mark.parametrize("name", NAMES)
def test_iss_reproduce(name, iss_exe, tmp_path):
    out = tmp_path / "out.json"
    res = subprocess.run([str(iss_exe), str(PROGRAMS / f"{name}.hex"), "-o", str(out)])
    assert res.returncode == 0
    got = canonical.load(out)
    exp = canonical.load(PROGRAMS / f"{name}.expected.json")
    assert canonical.diff(got, exp, "iss", "expected") == []
    assert got == exp


@pytest.mark.parametrize("name", NAMES)
def test_valores_a_mano(name):
    src = (PROGRAMS / f"{name}.s").read_text(encoding="utf-8")
    d = canonical.load(PROGRAMS / f"{name}.expected.json")
    mem = {int(a, 16): int(v, 16) for a, v in d["mem"]}
    toks = _expects(src)
    assert toks, "el programa no tiene líneas # expect:"
    for tok in toks:
        key, _, val = tok.partition("=")
        if key == "stop":
            assert d["stop"] == val, tok
        elif key == "pc":
            assert d["pc"] is not None and int(d["pc"], 16) == int(val, 16), tok
        elif key == "mem" and val == "none":
            assert d["mem"] == [], tok
        elif key.startswith("mem["):
            addr = int(key[4:-1], 16)
            assert mem.get(addr) == int(val, 16), tok
        elif re.fullmatch(r"x\d+", key):
            assert int(d["x"][int(key[1:])], 16) == int(val, 16), tok
        else:
            pytest.fail(f"clave de expect desconocida: {tok}")


@pytest.mark.parametrize("name", NAMES)
def test_rars(name, tmp_path):
    src = (PROGRAMS / f"{name}.s").read_text(encoding="utf-8")
    if _NO_RARS.search(src):
        pytest.skip("# rars: no")
    if not RARS_JAR.exists() or shutil.which("java") is None:
        pytest.skip("falta rars1_6.jar o java")
    out = tmp_path / "regs.json"
    res = subprocess.run([sys.executable, str(RARS_REF), "regs", str(PROGRAMS / f"{name}.s"),
                          "-o", str(out)], capture_output=True, text=True)
    assert res.returncode == 0, res.stdout + res.stderr
    rars = json.loads(out.read_text(encoding="utf-8"))
    ignore = {t.strip() for m in _IGNORE.finditer(src) for t in m.group(1).split(",") if t.strip()}
    assert set(rars.get("ignore", [])) == ignore
    exp = canonical.load(PROGRAMS / f"{name}.expected.json")
    difs = [f"x{i}: iss={exp['x'][i]} rars={rars['x'][i]}"
            for i in range(1, 32)
            if f"x{i}" not in ignore and exp["x"][i] != rars["x"][i]]
    assert difs == []

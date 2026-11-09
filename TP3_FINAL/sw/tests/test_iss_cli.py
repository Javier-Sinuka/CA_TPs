from __future__ import annotations

import json
import subprocess

from asm.rvasm import assemble, to_hex

SUMA = """\
        addi x1, x0, 0
        addi x2, x0, 1
        addi x3, x0, 11
loop:   add  x1, x1, x2
        addi x2, x2, 1
        bne  x2, x3, loop
        sw   x1, 0(x0)
        halt
"""


def _write_suma(tmp_path):
    hex_path = tmp_path / "suma.hex"
    hex_path.write_text(to_hex(assemble(SUMA)))
    return hex_path


def test_cli_halt(iss_exe, tmp_path):
    hex_path = _write_suma(tmp_path)
    out = tmp_path / "out.json"
    res = subprocess.run([str(iss_exe), str(hex_path), "-o", str(out)])
    assert res.returncode == 0
    d = json.loads(out.read_text())
    assert d["stop"] == "halt"
    assert d["pc"] == "0x0000001c"
    assert d["x"][1] == "0x00000037"
    assert len(d["x"]) == 32
    assert d["mem"] == [["0x00000000", "0x00000037"]]
    assert "instret" not in d


def test_cli_stdout(iss_exe, tmp_path):
    hex_path = _write_suma(tmp_path)
    res = subprocess.run([str(iss_exe), str(hex_path)], capture_output=True, text=True)
    assert res.returncode == 0
    assert json.loads(res.stdout)["pc"] == "0x0000001c"


def test_cli_limit_full(iss_exe, tmp_path):
    hex_path = _write_suma(tmp_path)
    out = tmp_path / "out.json"
    res = subprocess.run([str(iss_exe), str(hex_path), "-o", str(out),
                          "--max-instr", "3", "--full"])
    assert res.returncode == 0
    d = json.loads(out.read_text())
    assert d["stop"] == "limit"
    assert d["pc"] is None
    assert d["instret"] == 3
    assert d["next_pc"] == "0x0000000c"


def test_cli_instret_full_halt(iss_exe, tmp_path):
    hex_path = _write_suma(tmp_path)
    res = subprocess.run([str(iss_exe), str(hex_path), "--full"], capture_output=True, text=True)
    d = json.loads(res.stdout)
    assert d["stop"] == "halt"
    assert d["instret"] == 34
    assert d["next_pc"] == "0x0000001c"


def test_cli_errors(iss_exe, tmp_path):
    bad = tmp_path / "bad.hex"
    bad.write_text("00000013\nzz\n")
    res = subprocess.run([str(iss_exe), str(bad)], capture_output=True, encoding="utf-8")
    assert res.returncode == 2
    assert "línea 2 inválida" in res.stderr
    assert subprocess.run([str(iss_exe)], capture_output=True).returncode == 2
    assert subprocess.run([str(iss_exe), str(tmp_path / "nada.hex")],
                          capture_output=True).returncode == 2

"""Tests de host/fakeboard.py (placa simulada sobre el ISS) a través de Link."""
from pathlib import Path

import pytest

from host import canonical, proto
from host.fakeboard import FakeBoard
from host.link import Link, LinkError, Version

PROGRAMS = Path(__file__).resolve().parents[2] / "programs"
WITH_HALT = ["alu_nodep", "branches", "call_ret", "const32", "load_use",
             "mem_bytes", "raw_hazards", "suma"]


def _words(name: str) -> list[int]:
    return [int(line, 16) for line in
            (PROGRAMS / f"{name}.hex").read_text().split() if line]


def _expected(name: str) -> dict:
    return canonical.load(PROGRAMS / f"{name}.expected.json")


def test_connect(iss_exe):
    assert Link(FakeBoard(iss_exe)).connect() == Version(1, 256, 256)


@pytest.mark.parametrize("name", WITH_HALT)
def test_programa_de_b22(iss_exe, name):
    link = Link(FakeBoard(iss_exe))
    link.load(_words(name))
    d = link.run()
    assert d.halted and not d.timeout
    assert canonical.diff(canonical.from_dump(d), _expected(name), "placa", "esperado") == []


def test_no_halt_da_limit(iss_exe):
    link = Link(FakeBoard(iss_exe, run_limit=10_000))
    link.load(_words("no_halt"))
    d = link.run()
    assert d.timeout and not d.halted and d.cycles == 10_000
    r = canonical.from_dump(d)
    assert r["stop"] == "limit"
    assert canonical.diff(r, _expected("no_halt")) == []


def test_suma_paso_a_paso(iss_exe):
    link = Link(FakeBoard(iss_exe))
    link.load(_words("suma"))
    for _ in range(3):
        d = link.step()
    assert d.cycles == 3 and not d.halted and d.valid_wb
    assert (d.x[1], d.x[2], d.x[3]) == (0, 1, 11)

    steps = 3
    while not d.halted:
        d = link.step()
        steps += 1
        assert steps <= 100
    assert d.cycles == steps == 34
    assert d.latches[11] == 0x1C and d.info_wb.halt and d.valid_wb
    assert d.latches[15] == 0x18

    ref = Link(FakeBoard(iss_exe))
    ref.load(_words("suma"))
    assert d == ref.run()
    assert link.step() == d


def test_reset_pone_ciclos_en_cero(iss_exe):
    link = Link(FakeBoard(iss_exe))
    link.load(_words("suma"))
    for _ in range(3):
        link.step()
    link.reset()
    d = link.dump()
    assert d.cycles == 0 and d.x[2] == 0


def test_load_vacio_llena_con_halt(iss_exe):
    link = Link(FakeBoard(iss_exe))
    link.load([])
    d = link.run()
    assert d.halted and d.latches[11] == 0


def test_errores(iss_exe):
    board = FakeBoard(iss_exe)
    link = Link(board)
    with pytest.raises(LinkError):
        link.load([0] * 257)
    assert board.read(10) == b""

    board.write(b"\x4c\x01\x01")
    assert board.read(10) == b"\x45\x02"
    assert link.raw_error(0x7A) == proto.ERR_UNKNOWN_CMD == 1
    assert link.connect() == Version(1, 256, 256)


def test_fault_reemplaza_registro(iss_exe):
    link = Link(FakeBoard(iss_exe, fault={"x5": 0xDEAD}))
    link.load(_words("branches"))
    assert link.run().x[5] == 0xDEAD
    assert link.dump().x[5] == 0xDEAD


@pytest.mark.parametrize("key", ["x0", "x32", "pc", "5"])
def test_fault_clave_invalida(iss_exe, key):
    with pytest.raises(ValueError, match="fault"):
        FakeBoard(iss_exe, fault={key: 1})

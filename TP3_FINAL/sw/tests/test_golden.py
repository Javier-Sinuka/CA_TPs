"""B-26 §B: comparación contra el golden model."""
import dataclasses
from pathlib import Path

import pytest

from host.cli import Session
from host.dump import Dump
from host.fakeboard import FakeBoard
from host.golden import Golden, check, retired_after, store_en_wb
from host.link import Link

PROGRAMS = Path(__file__).resolve().parents[2] / "programs"


@pytest.fixture
def make(iss_exe):
    made = []

    def mk(program, **kw):
        link = Link(FakeBoard(iss_exe, **kw))
        s = Session(link)
        s.load_path(PROGRAMS / program)
        g = Golden(iss_exe, s.words)
        made.append((link, g))
        return s, g

    yield mk
    for link, g in made:
        link.close()
        g.close()


def _step_hasta_halt(s, limite=200):
    """Dumps D0, D1, ... hasta el primero con halted."""
    dumps = [s.cur]
    while not s.cur.halted:
        assert len(dumps) < limite, "no llegó a halted"
        s.execute("step")
        dumps.append(s.cur)
    return dumps


def _dw(valid_wb, halt=False):
    lat = [0] * 16
    lat[15] = 0x8 if valid_wb else 0
    lat[14] = 0x8000_0000 if halt else 0
    return Dump(halted=False, timeout=False, aborted=False, version=1, cycles=0, pc=0,
                x=(0,) * 32, latches=tuple(lat), mem=())


# ---------------------------------------------------------------- retired_after

def test_retired_after_cuenta_wb_validos_sin_halt_y_sin_el_ultimo_dump():
    assert retired_after([]) == 0
    assert retired_after([_dw(True)]) == 0
    assert retired_after([_dw(True), _dw(True)]) == 1
    assert retired_after([_dw(True), _dw(False), _dw(True, halt=True), _dw(True)]) == 1
    assert retired_after([_dw(True), _dw(True), _dw(True), _dw(False)]) == 3


# ---------------------------------------------------------------- sin fallas

def test_suma_paso_a_paso_no_diverge_nunca(make):
    s, g = make("suma.s")
    dumps = [s.cur]
    assert g.diverging(s.cur, retired_after(dumps)) == set()
    while not s.cur.halted:
        assert len(dumps) < 200
        s.execute("step")
        dumps.append(s.cur)
        assert g.diverging(s.cur, retired_after(dumps)) == set(), f"paso {len(dumps) - 1}"
    assert len(dumps) - 1 == 34 and retired_after(dumps) == 34


def test_halted_seguido_de_mas_pasos_no_cambia_retirados(make):
    s, g = make("suma.s")
    dumps = _step_hasta_halt(s)
    for _ in range(3):
        s.execute("step")
        dumps.append(s.cur)
        assert retired_after(dumps) == 34
        assert g.diverging(s.cur, retired_after(dumps)) == set()


def test_ejecutar_halted_coincide_con_el_estado_final(make):
    s, g = make("suma.s")
    s.execute("run")
    assert s.cur.halted
    assert g.diverging_final(s.cur) == set()
    assert s.cur.x[1] == 0x37 and s.cur.mem == ((0, 0x37),)


def test_estados_del_iss(make):
    _, g = make("suma.s")
    assert g.state_after(33)["stop"] == "limit"
    assert g.state_after(34)["stop"] == "halt"
    assert g.final_state()["stop"] == "halt"
    assert int(g.state_after(0)["x"][1], 16) == 0


# ---------------------------------------------------------------- con fallas

def test_registro_alterado_diverge_desde_el_primer_paso(make):
    s, g = make("branches.s", fault={"x5": 0xdead})
    dumps = [s.cur]
    for _ in range(5):
        s.execute("step")
        dumps.append(s.cur)
        assert g.diverging(s.cur, retired_after(dumps)) == {"x5"}


def test_falla_en_ejecutar_se_detecta_contra_el_final(make):
    s, g = make("suma.s", fault={"x1": 0x36})
    s.execute("run")
    assert g.diverging_final(s.cur) == {"x1"}


def test_memoria_distinta_diverge(make):
    s, g = make("suma.s")
    s.execute("run")
    d = s.cur
    assert g.diverging_final(dataclasses.replace(d, mem=((0, 0x38),))) == {"mem[0x00000000]"}
    assert g.diverging_final(dataclasses.replace(d, mem=())) == {"mem[0x00000000]"}
    assert g.diverging_final(dataclasses.replace(d, mem=((0, 0x37), (4, 1)))) == {"mem[0x00000004]"}


def test_x31_se_compara(make):
    s, g = make("suma.s", fault={"x31": 7})
    s.execute("run")
    assert g.diverging_final(s.cur) == {"x31"}


def test_par_de_memoria_con_valor_cero_que_el_iss_no_tiene_diverge(make):
    s, g = make("suma.s")
    s.execute("run")
    d = dataclasses.replace(s.cur, mem=s.cur.mem + ((4, 0),))
    assert g.diverging_final(d) == {"mem[0x00000004]"}


def test_los_estados_del_iss_se_cachean(make, monkeypatch):
    import host.golden as golden_mod
    _, g = make("suma.s")
    llamadas = []
    real = golden_mod.subprocess.run
    monkeypatch.setattr(golden_mod.subprocess, "run",
                        lambda *a, **k: llamadas.append(a) or real(*a, **k))
    g.state_after(3)
    g.state_after(3)
    g.final_state()
    g.final_state()
    assert len(llamadas) == 2


def test_check_sin_golden(make):
    s, _ = make("suma.s")
    assert check(None, [s.cur], ran=False) == (set(), "sin golden")


def test_check_paso_a_paso(make):
    s, g = make("branches.s")
    assert check(g, [s.cur], ran=False) == (set(), "golden: ok")
    s2, g2 = make("branches.s", fault={"x5": 0xdead})
    assert check(g2, [s2.cur], ran=False) == ({"x5"}, "golden: 1 divergencias")


def test_check_tras_ejecutar_compara_contra_el_final(make):
    s, g = make("suma.s")
    dumps = [s.cur]
    s.execute("run")
    dumps.append(s.cur)
    assert retired_after(dumps) == 1                    # el estado final no es el de 1 instrucción
    assert check(g, dumps, ran=True) == (set(), "golden: ok")
    s2, g2 = make("suma.s", fault={"x1": 0x36})
    s2.execute("run")
    assert check(g2, [s2.cur], ran=True) == ({"x1"}, "golden: 1 divergencias")


def test_check_tras_ejecutar_timeout_abortado_y_otros(make):
    s, g = make("suma.s", run_limit=5)
    s.execute("run")
    assert s.cur.timeout and not s.cur.halted
    assert check(g, [s.cur], ran=True) == (set(), "sin comparar (timeout)")
    ab = dataclasses.replace(s.cur, timeout=False, aborted=True)
    assert check(g, [ab], ran=True) == (set(), "sin comparar (abortado)")
    otro = dataclasses.replace(s.cur, timeout=False)
    assert check(g, [otro], ran=True) == (set(), "sin comparar (tras Ejecutar)")


def test_x0_no_se_compara(make):
    s, g = make("suma.s")
    s.execute("run")
    x = (1,) + s.cur.x[1:]
    assert g.diverging_final(dataclasses.replace(s.cur, x=x)) == set()


def _dump_iss(state, lat):
    return Dump(halted=False, timeout=False, aborted=False, version=1, cycles=0, pc=0,
                x=tuple(int(v, 16) for v in state["x"]), latches=tuple(lat),
                mem=tuple((int(a, 16), int(v, 16)) for a, v in state["mem"]))


def test_store_en_wb_ya_escribio_dmem_y_no_es_divergencia(make):
    """C-02: con el CPU real, dmem se escribe en el flanco que termina MEM, un paso antes del WB."""
    _, g = make("suma.s")
    k = next(n for n in range(1, 40) if g.state_after(n)["mem"])    # el store es la k-ésima
    ant, post = g.state_after(k - 1), g.state_after(k)
    en_mem = [0] * 16
    en_mem[10] = 1 << 24                                            # info_mem.mem_write
    en_mem[15] = 0x4                                                # valid_mem
    en_wb = [0] * 16
    en_wb[15] = 0x8                                                 # valid_wb
    # registros del ISS tras k-1 y memoria ya escrita (la del ISS tras k)
    dumps = [_dw(True)] * (k - 1) + [_dump_iss(ant, en_mem),
                                     _dump_iss({"x": ant["x"], "mem": post["mem"]}, en_wb)]
    assert retired_after(dumps) == k - 1
    assert store_en_wb(dumps)
    assert check(g, dumps, ran=False) == (set(), "golden: ok")
    # sin el store en MEM del dump anterior, esa memoria sí sería una divergencia
    dumps[-2] = _dump_iss(ant, [0] * 16)
    assert not store_en_wb(dumps)
    assert check(g, dumps, ran=False) == ({"mem[0x00000000]"}, "golden: 1 divergencias")

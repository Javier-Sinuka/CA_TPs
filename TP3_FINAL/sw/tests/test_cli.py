"""Tests de host/cli.py: sesión guionada sobre la placa simulada y un test por comando."""
import subprocess
import sys
from pathlib import Path

import pytest

from host.cli import Session, run_script
from host.fakeboard import FakeBoard
from host.link import Link
from host.stub_model import stub_dump

SW = Path(__file__).resolve().parents[1]
DATA = SW / "tests" / "data"


@pytest.fixture
def make_session(iss_exe, monkeypatch):
    """Session sobre FakeBoard con cwd = TP3_FINAL/sw (las rutas del guion son relativas)."""
    monkeypatch.chdir(SW)
    links = []

    def make(**kw):
        link = Link(FakeBoard(iss_exe, **kw))
        links.append(link)
        return Session(link)

    yield make
    for link in links:
        link.close()


@pytest.fixture
def s(make_session):
    return make_session()


def _cli(*args):
    return subprocess.run([sys.executable, "-m", "host.cli", *args], cwd=SW,
                          capture_output=True, text=True, encoding="utf-8")


# ---------------------------------------------------------------- sesión guionada

def test_sesion_guionada_igual_al_esperado(s):
    lines = (DATA / "session1.txt").read_text(encoding="utf-8").splitlines()
    out = s.start() + list(run_script(s, lines))
    expected = (DATA / "session1.expected.txt").read_text(encoding="utf-8").splitlines()
    assert out == expected
    assert s.errors == 1


def test_cli_fake_script_codigo_1(iss_exe):
    r = _cli("--fake", "--script", "tests/data/session1.txt")
    assert r.returncode == 1
    expected = (DATA / "session1.expected.txt").read_text(encoding="utf-8")
    assert r.stdout.splitlines() == expected.splitlines()


def test_cli_script_b16_sin_errores_en_placa_simulada(iss_exe):
    r = _cli("--fake", "--script", "tests/data/b16_script.txt")
    assert r.returncode == 0, r.stdout
    assert "error:" not in r.stdout
    assert "cargado: 37 palabras (tests/data/b16_progA.hex)" in r.stdout
    assert "cargado: 2 palabras (tests/data/b16_progB.hex)" in r.stdout
    assert "raw: E 01" in r.stdout


def test_cli_falta_iss():
    r = _cli("--fake", "--iss", "no/existe/iss.exe")
    assert r.returncode == 2
    assert r.stderr.strip() == "error: falta no/existe/iss.exe (py TP3_FINAL/tools/run.py iss)"


def test_cli_script_inexistente(iss_exe):
    r = _cli("--fake", "--script", "no_existe.txt")
    assert r.returncode == 2 and r.stderr.startswith("error: ")


def test_cli_exige_port_o_fake():
    assert _cli().returncode == 2


# ---------------------------------------------------------------- un test por comando

def test_version(s):
    assert s.execute("version") == ["conectado: protocolo 1, imem 256, dmem 256 palabras"]


def test_load_s_y_hex(s):
    assert s.execute("load ../programs/suma.s") == ["cargado: 8 palabras (../programs/suma.s)"]
    assert s.prev is None and s.cur.cycles == 0
    assert s.execute("load ../programs/suma.hex") == ["cargado: 8 palabras (../programs/suma.hex)"]


def test_reset(s):
    s.execute("load ../programs/suma.s")
    s.execute("step 3")
    assert s.execute("reset") == ["reset: ok"]
    assert s.cur.cycles == 0 and s.prev.cycles == 3


def test_step(s):
    s.execute("load ../programs/suma.s")
    assert s.execute("step") == ["paso: ciclos=1 pc=0x00000004"]
    assert s.execute("step 2") == ["paso: ciclos=2 pc=0x00000008",
                                   "paso: ciclos=3 pc=0x0000000c"]


def test_step_con_cpu_detenido(s):
    s.execute("load ../programs/suma.s")
    s.execute("run")
    assert s.execute("step") == ["paso: ciclos=34 pc=0x0000001c halted"]


def test_run_halt(s):
    s.execute("load ../programs/suma.s")
    assert s.execute("run") == ["run: halt ciclos=34 pc=0x0000001c"]


def test_run_timeout(make_session):
    sess = make_session(run_limit=100)
    sess.execute("load ../programs/no_halt.s")
    assert sess.execute("run") == ["run: timeout ciclos=100 pc=0x00000008"]


def test_dump(s):
    s.execute("load ../programs/suma.s")
    assert s.execute("dump") == ["dump: ciclos=0 pc=0x00000000 halted=0"]
    s.execute("run")
    assert s.execute("dump") == ["dump: ciclos=34 pc=0x0000001c halted=1"]


def test_regs(s):
    s.execute("load ../programs/suma.s")
    first = s.execute("regs")
    assert len(first) == 8
    assert first[0] == "x0 =0x00000000  x1 =0x00000000  x2 =0x00000000  x3 =0x00000000"
    assert first[2] == "x8 =0x00000000  x9 =0x00000000  x10=0x00000000  x11=0x00000000"
    s.execute("step 2")
    assert s.execute("regs")[0] == "x0 =0x00000000  x1 =0x00000000  x2 =0x00000001* x3 =0x00000000"


def test_mem(s):
    s.execute("load ../programs/suma.s")
    assert s.execute("mem") == ["(sin palabras escritas)"]
    s.execute("run")
    assert s.execute("mem") == ["0x00000000: 0x00000037"]


def test_pipe(s):
    s.execute("load ../programs/suma.s")
    s.execute("step 3")
    assert s.execute("pipe") == [
        "IF  0x0000000c  add x1, x1, x2",
        "ID  --",
        "EX  --",
        "MEM --",
        "WB  0x00000000  addi x1, x0, 0",
    ]


def test_pipe_detenido(s):
    s.execute("load ../programs/suma.s")
    s.execute("run")
    assert s.execute("pipe") == [
        "IF  --",
        "ID  --",
        "EX  --",
        "MEM --",
        "WB  0x0000001c  halt",
    ]


def test_raw(s):
    assert s.execute("raw 7a") == ["raw: E 01"]


def test_quit(s):
    assert s.execute("quit") == [] and s.done


# ---------------------------------------------------------------- errores

def test_comando_desconocido(s):
    assert s.execute("foo bar") == ["error: comando desconocido 'foo'"]
    assert s.errors == 1


@pytest.mark.parametrize("cmd", ["regs", "mem", "pipe"])
def test_sin_estado(s, cmd):
    assert s.execute(cmd) == ["error: no hay estado (usar dump)"]


@pytest.mark.parametrize("line, msg", [
    ("step 0", "uso: step [n]"), ("step x", "uso: step [n]"), ("step 1 2", "uso: step [n]"),
    ("load", "uso: load <ruta>"), ("raw", "uso: raw <hh>"), ("raw zz", "uso: raw <hh>"),
    ("raw 100", "uso: raw <hh>"),
])
def test_argumentos_invalidos(s, line, msg):
    assert s.execute(line) == [f"error: {msg}"]


def test_load_path_acepta_rutas_con_espacios(s, tmp_path):
    d = tmp_path / "carpeta con espacios"
    d.mkdir()
    p = d / "un programa.s"
    p.write_text("addi x1, x0, 5\n", encoding="utf-8")
    words = s.load_path(p)
    assert words[0] == 0x00500093 and s.words == words
    assert s.prev is None and s.cur is not None and s.cur.cycles == 0


def test_load_errores(s, tmp_path):
    assert s.execute("load prog.txt") == [
        "error: extensión no soportada '.txt' (usar .s o .hex)"]
    bad = tmp_path / "bad.hex"
    bad.write_text("00000013\n\nzz\n", encoding="utf-8")
    assert s.execute(f"load {bad}") == [f"error: {bad}:3: palabra inválida 'zz'"]
    assert s.execute("load no_existe.s")[0].startswith("error: ")
    src = tmp_path / "bad.s"
    src.write_text("nop\nadd x1, x2\n", encoding="utf-8")
    assert s.execute(f"load {src}")[0].startswith("error: ")


def test_load_hex_ignora_lineas_vacias(s, tmp_path):
    p = tmp_path / "p.hex"
    p.write_text("\n00000013\n\n00000073\n", encoding="utf-8")
    assert s.execute(f"load {p}") == [f"cargado: 2 palabras ({p})"]


def test_el_error_no_corta_el_guion(s):
    out = list(run_script(s, ["foo", "# comentario", "", "version"]))
    assert out == ["> foo", "error: comando desconocido 'foo'", "> version",
                   "conectado: protocolo 1, imem 256, dmem 256 palabras"]


def test_load_descarta_el_estado_anterior(s):
    s.execute("load ../programs/suma.s")
    s.execute("step 3")
    s.execute("load ../programs/suma.s")
    assert s.prev is None
    assert not any("*" in line for line in s.execute("regs"))


class _RunLink:
    """Link mínimo cuyo run() devuelve un dump fijo (con el pc de WB distinto de W2)."""

    def __init__(self, d):
        self.d = d

    def run(self):
        return self.d


@pytest.mark.parametrize("d, line", [
    # con halt, el pc sale del latch 11 (pc_wb), no de W2
    (stub_dump(20, 20), "run: halt ciclos=20 pc=0x1a0b0014"),
    (stub_dump(20, 0, timeout=True), "run: timeout ciclos=20 pc=0x00000050"),
    (stub_dump(7, 20, aborted=True), "run: abort ciclos=7 pc=0x0000001c"),
])
def test_run_motivos(d, line):
    assert Session(_RunLink(d)).execute("run") == [line]

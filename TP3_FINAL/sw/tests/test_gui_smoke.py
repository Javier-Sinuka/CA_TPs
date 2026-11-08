"""Prueba de humo de la GUI (B-26 §C): abre la ventana (oculta) sobre la placa simulada.

Se saltea si no hay pantalla (tk.TclError) o con RV_SKIP_GUI=1.
"""
import dataclasses
import faulthandler
import os
import subprocess
import sys
import tkinter as tk
from pathlib import Path

import pytest

from host import gui
from host.cli import Session
from host.dump import Dump
from host.fakeboard import FakeBoard
from host.golden import Golden
from host.link import Link

SW = Path(__file__).resolve().parents[1]
PROGRAMS = SW.parent / "programs"
TIMEOUT_S = 90


@pytest.fixture(scope="module")
def tk_root():
    """Una sola raíz de Tk para todo el módulo (crear y destruir muchas falla a veces)."""
    if os.environ.get("RV_SKIP_GUI") == "1":
        pytest.skip("RV_SKIP_GUI=1")
    try:
        root = tk.Tk()
    except tk.TclError as e:
        pytest.skip(f"sin pantalla: {e}")
    root.withdraw()
    yield root
    root.destroy()


@pytest.fixture
def make_app(iss_exe, monkeypatch, tk_root):
    root = tk_root
    errors: list[str] = []
    monkeypatch.setattr(gui.App, "_error", lambda self, message: errors.append(message))
    made = []
    faulthandler.dump_traceback_later(TIMEOUT_S, exit=True)     # timeout propio: no colgar el runner

    def make(**fake):
        link = Link(FakeBoard(iss_exe, **fake))
        app = gui.App(root, Session(link), lambda words: Golden(iss_exe, words))
        made.append((app, link))
        return app, errors

    try:
        yield make
    finally:
        faulthandler.cancel_dump_traceback_later()
        for app, link in made:
            app.close()
            link.close()
        for widget in root.winfo_children():
            widget.destroy()


def _yellow(app):
    return {i for i, lab in enumerate(app.reg_labels) if lab.cget("bg") == gui.YELLOW}


def _red(app):
    return {i for i, lab in enumerate(app.reg_labels) if lab.cget("bg") == gui.RED}


def test_suma_paso_a_paso_con_cambios_en_amarillo(make_app):
    app, errors = make_app()
    app.load(str(PROGRAMS / "suma.s"))
    assert app.status_var.get() == "ciclos=0 pc=0x00000000"
    for n in range(1, 11):
        app.buttons["Paso"].invoke()
        assert app.status_var.get().startswith(f"ciclos={n} ")
    assert len(app.dumps) == 11
    a, b = app.dumps[-2], app.dumps[-1]
    assert _yellow(app) == {i for i in range(32) if a.x[i] != b.x[i]} != set()
    assert app.bottom_var.get() == "golden: ok"
    assert errors == []


def test_ejecutar_deja_halted_y_el_resultado_final(make_app):
    app, errors = make_app()
    app.load(str(PROGRAMS / "suma.s"))
    app.buttons["Ejecutar"].invoke()
    assert "halted" in app.status_var.get()
    assert app.reg_labels[1].cget("text") == "x1 =0x00000037"
    assert list(app.mem.get(0, "end")) == ["0x00000000: 0x00000037"]
    assert app.bottom_var.get() == "golden: ok"
    assert len(app.dumps) == 2                         # D0 + una sola columna de Ejecutar
    app.buttons["Dump"].invoke()
    app.buttons["Paso"].invoke()
    assert len(app.dumps) == 2                         # Dump y Paso con el CPU detenido no agregan
    assert errors == []


def test_ejecutar_con_el_cpu_detenido_no_agrega_columna(make_app):
    app, _ = make_app()
    app.load(str(PROGRAMS / "suma.s"))
    app.buttons["Ejecutar"].invoke()
    app.buttons["Ejecutar"].invoke()
    assert len(app.dumps) == 2 and app.ran
    app.load(str(PROGRAMS / "suma.s"))
    assert app.ran is False and len(app.dumps) == 1


def test_la_marca_roja_gana_sobre_el_amarillo_y_marca_la_memoria(make_app, monkeypatch):
    app, _ = make_app()
    app.load(str(PROGRAMS / "suma.s"))
    monkeypatch.setattr(gui, "check", lambda g, dumps, ran: (
        {f"x{i}" for i in range(32)} | {"mem[0x00000000]"}, "v"))
    app.step(3)
    a, b = app.dumps[-2], app.dumps[-1]
    assert any(a.x[i] != b.x[i] for i in range(1, 32))   # hay un registro que cambió y diverge
    assert _red(app) == set(range(32)) and _yellow(app) == set()
    assert app.mem.itemcget(0, "bg") != gui.RED          # sin palabras escritas
    app.buttons["Ejecutar"].invoke()
    assert app.mem.get(0) == "0x00000000: 0x00000037"
    assert app.mem.itemcget(0, "bg") == gui.RED
    monkeypatch.setattr(gui, "check", lambda g, dumps, ran: (set(), "v"))
    app.refresh()
    assert app.mem.itemcget(0, "bg") != gui.RED


def test_memoria_vacia_muestra_el_aviso(make_app):
    app, _ = make_app()
    app.load(str(PROGRAMS / "suma.s"))
    assert list(app.mem.get(0, "end")) == ["(sin palabras escritas)"]


def test_reset_y_cargar_reinician_el_diagrama(make_app):
    app, errors = make_app()
    app.load(str(PROGRAMS / "suma.s"))
    app.step(4)
    assert len(app.dumps) == 5
    app.buttons["Reset"].invoke()
    assert len(app.dumps) == 1 and app.status_var.get().startswith("ciclos=0 ")
    app.step(2)
    app.load(str(PROGRAMS / "suma.s"))
    assert len(app.dumps) == 1
    app.buttons["Ejecutar"].invoke()
    app.buttons["Reset"].invoke()
    assert len(app.dumps) == 1 and app.ran is False and "halted" not in app.status_var.get()
    assert errors == []


def test_el_diagrama_dibuja_una_celda_por_etapa(make_app):
    app, _ = make_app()
    app.load(str(PROGRAMS / "suma.s"))
    app.step(3)
    celdas = sum(len(r.cells) for r in app.rows)
    assert celdas > 0
    assert sum(1 for i in app.cells.find_all() if app.cells.type(i) == "rectangle") == celdas


def test_registro_alterado_en_rojo(make_app):
    app, errors = make_app(fault={"x5": 0xdead})
    app.load(str(PROGRAMS / "branches.s"))
    assert _red(app) == {5}
    assert app.bottom_var.get() == "golden: 1 divergencias: x5"
    app.step(1)
    assert _red(app) == {5}
    assert errors == []


def test_ejecutar_con_timeout_no_compara(make_app):
    app, _ = make_app(run_limit=5)
    app.load(str(PROGRAMS / "suma.s"))
    app.buttons["Ejecutar"].invoke()
    assert "timeout" in app.status_var.get()
    assert app.bottom_var.get() == "sin comparar (timeout)"


def test_paso_por_n(make_app):
    app, errors = make_app()
    app.load(str(PROGRAMS / "suma.s"))
    app.n_var.set("3")
    app.buttons["Paso ×N"].invoke()
    assert len(app.dumps) == 4 and errors == []
    for malo in ("0", "101", "abc", ""):
        app.n_var.set(malo)
        app.buttons["Paso ×N"].invoke()
    assert len(app.dumps) == 4 and len(errors) == 4


def test_sin_programa_cargado_avisa(make_app):
    app, errors = make_app()
    for nombre in ("Reset", "Paso", "Paso ×N", "Ejecutar", "Dump"):
        app.buttons[nombre].invoke()
    assert len(errors) == 5 and all("Primero cargá" in e for e in errors)
    assert app.dumps == []


def test_cargar_con_error_deja_la_ventana_viva(make_app, tmp_path):
    app, errors = make_app()
    app.load(str(tmp_path / "no_existe.s"))
    app.load(str(tmp_path / "programa.txt"))
    assert len(errors) == 2 and "extensión no soportada" in errors[1]
    assert app.dumps == []


def test_los_latches_muestran_solo_sus_campos(make_app):
    app, _ = make_app()
    app.load(str(PROGRAMS / "suma.s"))
    id_ex, ex_mem, mem_wb = (v.get() for v in app.latch_vars)
    assert id_ex.startswith("ID/EX") and "alu_op=" in id_ex and "imm=0x" in id_ex
    assert ex_mem.startswith("EX/MEM") and "funct3=" in ex_mem and "alu_op=" not in ex_mem
    assert mem_wb.startswith("MEM/WB") and "reg_write=" in mem_wb and "funct3=" not in mem_wb
    assert all("halt=" in t for t in (id_ex, ex_mem, mem_wb))


def test_formato():
    d = Dump(halted=False, timeout=False, aborted=False, version=1, cycles=7, pc=0x20,
             x=(0,) * 32, latches=(0,) * 16, mem=())
    assert gui.status_text(d) == "ciclos=7 pc=0x00000020"
    assert gui.status_text(dataclasses.replace(d, halted=True)) == "ciclos=7 pc=0x00000020 halted"
    assert gui.status_text(dataclasses.replace(d, timeout=True)) == "ciclos=7 pc=0x00000020 timeout"
    assert gui.status_text(dataclasses.replace(d, aborted=True)) == "ciclos=7 pc=0x00000020 abort"
    assert gui.reg_text(5, 0xabc) == "x5 =0x00000abc"
    assert gui.reg_text(31, 1) == "x31=0x00000001"
    assert gui.parse_fault("x5=0xdead") == ("x5", 0xdead)
    assert gui.parse_fault("x31=7") == ("x31", 7)
    for malo in ("x0=1", "x32=1", "5=1", "x5", "x5=zz"):
        with pytest.raises(Exception):
            gui.parse_fault(malo)


def _gui(*args):
    return subprocess.run([sys.executable, "-m", "host.gui", *args], cwd=SW,
                          capture_output=True, text=True, encoding="utf-8", timeout=60)


def test_argumentos_invalidos(iss_exe):
    assert _gui().returncode == 2
    r = _gui("--fake", "--iss", "no/existe/iss.exe")
    assert r.returncode == 2
    assert r.stderr.strip() == "error: falta no/existe/iss.exe (py TP3_FINAL/tools/run.py iss)"
    assert _gui("--fake", "--fake-fault", "x0=1").returncode == 2
    r = _gui("--port", "COM1", "--fake-fault", "x5=1")
    assert r.returncode == 2 and "--fake-fault requiere --fake" in r.stderr

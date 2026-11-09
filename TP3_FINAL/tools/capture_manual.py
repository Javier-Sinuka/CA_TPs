"""Regenera las capturas PNG de doc/documentation/manual_interfaz.md (solo Windows, sin Pillow).

Captura SOLO el rectángulo de la ventana, con la placa simulada (--fake). Necesita build/iss.exe
(py tools/run.py iss) y una pantalla activa; la ventana queda arriba de todo mientras corre.

Uso: py TP3_FINAL/tools/capture_manual.py [directorio de salida]
     (por defecto TP3_FINAL/doc/documentation/img)
"""
import ctypes
import struct
import sys
import zlib
from pathlib import Path

TP3 = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TP3 / "sw"))
ctypes.windll.user32.SetProcessDPIAware()

import tkinter as tk

from asm.rvasm import assemble
from host import gui
from host.cli import Session
from host.fakeboard import FakeBoard
from host.golden import Golden
from host.link import Link
from tests.test_spacetime import BRANCH, LOAD_USE

OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else TP3 / "doc" / "documentation" / "img"
OUT.mkdir(parents=True, exist_ok=True)
ISS = TP3 / "build" / "iss.exe"
PROGRAMS = TP3 / "programs"

user32, gdi32 = ctypes.windll.user32, ctypes.windll.gdi32


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", ctypes.c_uint32), ("biWidth", ctypes.c_int32),
                ("biHeight", ctypes.c_int32), ("biPlanes", ctypes.c_uint16),
                ("biBitCount", ctypes.c_uint16), ("biCompression", ctypes.c_uint32),
                ("biSizeImage", ctypes.c_uint32), ("biXPelsPerMeter", ctypes.c_int32),
                ("biYPelsPerMeter", ctypes.c_int32), ("biClrUsed", ctypes.c_uint32),
                ("biClrImportant", ctypes.c_uint32)]


def grab(x, y, w, h):
    """BGRA de la pantalla en el rectángulo (x, y, w, h)."""
    hdc = user32.GetDC(0)
    mem = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mem, bmp)
    gdi32.BitBlt(mem, 0, 0, w, h, hdc, x, y, 0x00CC0020 | 0x40000000)
    bi = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), w, -h, 1, 32, 0, 0, 0, 0, 0, 0)
    buf = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(mem, bmp, 0, h, buf, ctypes.byref(bi), 0)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mem)
    user32.ReleaseDC(0, hdc)
    return buf.raw


def write_png(path, bgra, w, h):
    raw = bytearray()
    for r in range(h):
        raw.append(0)
        row = bgra[r * w * 4:(r + 1) * w * 4]
        rgb = bytearray(w * 3)
        rgb[0::3], rgb[1::3], rgb[2::3] = row[2::4], row[1::4], row[0::4]
        raw += rgb

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    Path(path).write_bytes(png)


root = tk.Tk()
sw, sh = root.winfo_screenwidth(), root.winfo_screenheight()
W, H = min(1120, sw - 80), min(860, sh - 120)
root.geometry(f"{W}x{H}+30+30")
root.attributes("-topmost", True)
errors = []
gui.App._error = lambda self, m: errors.append(m)


def make(fault=None):
    for w in root.winfo_children():
        w.destroy()
    link = Link(FakeBoard(ISS, fault=fault))
    app = gui.App(root, Session(link), lambda words: Golden(ISS, words))
    return app, link


def settle():
    root.update_idletasks()
    root.update()
    root.lift()
    root.update()


def shot(name, widget=None):
    settle()
    w = widget or root
    x, y, ww, hh = w.winfo_rootx(), w.winfo_rooty(), w.winfo_width(), w.winfo_height()
    write_png(OUT / f"{name}.png", grab(x, y, ww, hh), ww, hh)
    print(name, ww, hh)


# 1. paso a paso con suma.s: 10 pasos (amarillo)
app, link = make()
app.load(str(PROGRAMS / "suma.s"))
app.step(10)
shot("ventana_paso_a_paso")
shot("zona_barra", root.winfo_children()[0])
shot("zona_registros", app.reg_labels[0].master)
shot("zona_pipeline", app.mem.master.master.winfo_children()[0])
shot("zona_memoria", app.mem.master)
shot("zona_latches", app.latch_vars and root.winfo_children()[2])
shot("zona_diagrama", root.winfo_children()[3])
link.close(); app.close()

# 2. Ejecutar hasta halted
app, link = make()
app.load(str(PROGRAMS / "suma.s"))
app.buttons["Ejecutar"].invoke()
shot("ventana_ejecutar")
link.close(); app.close()

# 3. falla inyectada: x5 en rojo
app, link = make(fault={"x5": 0xdead})
app.load(str(PROGRAMS / "branches.s"))
app.step(3)
shot("ventana_divergencia")
link.close(); app.close()

# 4. diagramas con dumps armados a mano (escenarios de B-26 §A), no de la placa
app, link = make()
app.session.words = assemble("lw x1, 0(x0)\nadd x2, x1, x1\naddi x3, x0, 1\n")
app.dumps = LOAD_USE
app._draw_diagram()
app.cells.xview_moveto(0.0)
shot("diagrama_load_use", root.winfo_children()[3])
app.session.words = assemble("addi x1, x0, 1\nbne x1, x0, 12\naddi x2, x0, 2\naddi x3, x0, 3\n")
app.dumps = BRANCH
app._draw_diagram()
app.cells.xview_moveto(0.0)
shot("diagrama_salto_tomado", root.winfo_children()[3])
link.close(); app.close()
print("errores:", errors)
root.destroy()

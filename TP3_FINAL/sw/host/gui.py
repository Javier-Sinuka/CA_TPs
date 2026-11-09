"""Interfaz gráfica (tkinter) sobre Session (B-26 §C).

    py -m host.gui (--port COMx | --fake) [--iss <ruta>] [--fake-fault xN=valor ...]

Un solo `tk.Tk`, sin hilos: las llamadas a `Link` bloquean (timeouts de B-23, <= 4 s).
La ventana envuelve a `Session` (la misma lógica que la CLI); el diagrama espacio-tiempo
sale de `spacetime.py` y las divergencias de `golden.py`: acá solo se dibuja.
"""
from __future__ import annotations

import argparse
import re
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox
from typing import Callable

from asm.rvasm import AsmError
from host.cli import DEFAULT_ISS, CliError, Session
from host.dump import Dump, LatchInfo
from host.golden import Golden, check
from host.link import Link, LinkError
from host.spacetime import build, row_label

MONO = ("Consolas", 10)
MONO_BOLD = ("Consolas", 10, "bold")
YELLOW = "#fff2a8"          # registro que cambió respecto del dump anterior
RED = "#ff9c9c"             # diverge del golden model
CELL_W, CELL_H, HEAD_H, LABEL_W = 56, 20, 22, 290

_ALL_FIELDS = ("rd", "rs1", "rs2", "funct3", "alu_op", "alu_src_b", "mem_read", "mem_write",
               "mem_to_reg", "reg_write", "branch", "jump", "jalr", "lui", "halt")
# Campos que cada latch lleva (dump.md §3.1).
_LATCHES = (
    ("ID/EX", 2, ("pc", "rs1_val", "rs2_val", "imm"), _ALL_FIELDS),
    ("EX/MEM", 7, ("pc", "result", "store_data"),
     ("rd", "funct3", "mem_read", "mem_write", "mem_to_reg", "reg_write", "halt")),
    ("MEM/WB", 11, ("pc", "result", "load_data"), ("rd", "mem_to_reg", "reg_write", "halt")),
)


# ---------------------------------------------------------------- formato (sin tkinter)

def status_text(d: Dump) -> str:
    flags = [name for name, on in (("halted", d.halted), ("timeout", d.timeout),
                                   ("abort", d.aborted)) if on]
    return " ".join([f"ciclos={d.cycles} pc=0x{d.pc:08x}", *flags])


def reg_text(i: int, value: int) -> str:
    return f"x{i:<2}=0x{value:08x}"


def latch_lines(d: Dump) -> list[tuple[str, str, str]]:
    """Por latch: (nombre, palabras crudas en hex, campos decodificados que ese latch lleva)."""
    out = []
    for name, base, names, fields in _LATCHES:
        words = " ".join(f"{n}=0x{d.latches[base + i]:08x}" for i, n in enumerate(names))
        raw = d.latches[base + len(names)]
        info = LatchInfo.unpack(raw)
        decoded = " ".join(f"{f}={int(getattr(info, f))}" for f in fields)
        out.append((name, f"{words} info=0x{raw:08x}", decoded))
    return out


def parse_fault(text: str) -> tuple[str, int]:
    m = re.fullmatch(r"(x(\d+))=(\S+)", text)
    if not m or not 1 <= int(m.group(2)) <= 31:
        raise argparse.ArgumentTypeError(f"'{text}': se espera xN=valor con N de 1 a 31")
    try:
        return m.group(1), int(m.group(3), 0)
    except ValueError:
        raise argparse.ArgumentTypeError(f"'{text}': valor inválido") from None


# ---------------------------------------------------------------- ventana

class App:
    def __init__(self, root: tk.Tk, session: Session,
                 golden_for: Callable[[list[int]], Golden | None], notice: str = "") -> None:
        self.root = root
        self.session = session
        self.golden_for = golden_for
        self.notice = notice
        self.golden: Golden | None = None
        self.dumps: list[Dump] = []     # columnas del diagrama
        self.ran = False                # hubo un Ejecutar desde el último Cargar/Reset
        self.keys: set[str] = set()
        self.verdict = ""
        self.rows: list = []
        self.buttons: dict[str, tk.Button] = {}
        self._build()
        self._cmd_ok(self.session.start())
        self._refresh_status()

    # ------------------------------------------------------------ construcción

    def _build(self) -> None:
        root = self.root
        root.title("Debug RISC-V")
        root.geometry("1120x860")
        root.columnconfigure(0, weight=1)
        root.rowconfigure(3, weight=1)

        bar = tk.Frame(root)
        bar.grid(row=0, column=0, sticky="ew", padx=6, pady=4)
        self.n_var = tk.StringVar(value="10")
        for text, command in (("Cargar .s…", self.load), ("Reset", self.reset),
                              ("Paso", lambda: self.step(1)), ("Paso ×N", self._step_n),
                              ("Ejecutar", self.run), ("Dump", self.dump)):
            b = tk.Button(bar, text=text, command=command)
            b.pack(side="left", padx=2)
            self.buttons[text] = b
            if text == "Paso ×N":
                self.spin = tk.Spinbox(bar, from_=1, to=100, width=4, textvariable=self.n_var)
                self.spin.pack(side="left", padx=(0, 8))
        self.status_var = tk.StringVar(value="sin programa cargado")
        tk.Label(bar, textvariable=self.status_var, font=MONO_BOLD).pack(side="left", padx=10)

        top = tk.Frame(root)
        top.grid(row=1, column=0, sticky="ew", padx=6)
        regs = tk.LabelFrame(top, text="Registros")
        regs.pack(side="left", anchor="n")
        self.reg_labels: list[tk.Label] = []
        for i in range(32):
            lab = tk.Label(regs, text=reg_text(i, 0), font=MONO, anchor="w")
            lab.grid(row=i // 4, column=i % 4, sticky="w", padx=2)
            self.reg_labels.append(lab)
        right = tk.Frame(top)
        right.pack(side="left", anchor="n", fill="both", expand=True, padx=(8, 0))
        pipe = tk.LabelFrame(right, text="Pipeline")
        pipe.pack(fill="x")
        self.pipe_var = tk.StringVar()
        tk.Label(pipe, textvariable=self.pipe_var, font=MONO, justify="left",
                 anchor="w").pack(fill="x")
        mem = tk.LabelFrame(right, text="Memoria")
        mem.pack(fill="both", expand=True)
        self.mem = tk.Listbox(mem, height=7, font=MONO)
        self.mem.pack(fill="both", expand=True)

        lat = tk.LabelFrame(root, text="Latches")
        lat.grid(row=2, column=0, sticky="ew", padx=6)
        self.latch_vars = [tk.StringVar() for _ in _LATCHES]
        for var in self.latch_vars:
            tk.Label(lat, textvariable=var, font=MONO, justify="left", anchor="w",
                     wraplength=1090).pack(fill="x")

        st = tk.LabelFrame(root, text="Espacio-tiempo")
        st.grid(row=3, column=0, sticky="nsew", padx=6)
        st.columnconfigure(1, weight=1)
        st.rowconfigure(0, weight=1)
        self.lab = tk.Canvas(st, width=LABEL_W, height=150, bg="white", highlightthickness=0)
        self.cells = tk.Canvas(st, height=150, bg="white", highlightthickness=0)
        self.lab.grid(row=0, column=0, sticky="ns")
        self.cells.grid(row=0, column=1, sticky="nsew")
        vbar = tk.Scrollbar(st, orient="vertical", command=self._yview)
        hbar = tk.Scrollbar(st, orient="horizontal", command=self.cells.xview)
        vbar.grid(row=0, column=2, sticky="ns")
        hbar.grid(row=1, column=1, sticky="ew")
        self.lab.configure(yscrollcommand=vbar.set)
        self.cells.configure(xscrollcommand=hbar.set)

        self.bottom_var = tk.StringVar(value=self.notice)
        tk.Label(root, textvariable=self.bottom_var, anchor="w").grid(
            row=4, column=0, sticky="ew", padx=6, pady=2)

    def _yview(self, *args) -> None:
        self.lab.yview(*args)
        self.cells.yview(*args)

    # ------------------------------------------------------------ errores

    def _error(self, message: str) -> None:
        messagebox.showerror("Error", message)

    def _cmd_ok(self, out: list[str]) -> bool:
        errors = [s for s in out if s.startswith("error:")]
        if errors:
            self._error("\n".join(errors))
        return not errors

    def _need_program(self) -> bool:
        if not self.dumps:
            self._error("Primero cargá un programa (Cargar .s…).")
        return bool(self.dumps)

    # ------------------------------------------------------------ acciones

    def load(self, path: str | None = None) -> None:
        if path is None:
            path = filedialog.askopenfilename(
                title="Cargar programa", filetypes=[("Programa", "*.s *.hex"), ("Todos", "*.*")])
            if not path:
                return
        try:
            words = self.session.load_path(Path(path))
        except (LinkError, AsmError, OSError, CliError) as e:
            self._error(str(e))
            return
        if self.golden is not None:
            self.golden.close()
        self.golden = self.golden_for(words)
        self.dumps = [self.session.cur]
        self.ran = False
        self.refresh()

    def reset(self) -> None:
        if not self._need_program() or not self._cmd_ok(self.session.execute("reset")):
            return
        self.dumps = [self.session.cur]
        self.ran = False
        self.refresh()

    def _step_n(self) -> None:
        try:
            n = int(self.n_var.get())
        except ValueError:
            n = 0
        if not 1 <= n <= 100:
            self._error("N debe ser un entero entre 1 y 100.")
            return
        self.step(n)

    def step(self, n: int = 1) -> None:
        if not self._need_program():
            return
        for _ in range(n):
            was_halted = self.dumps[-1].halted
            if not self._cmd_ok(self.session.execute("step")):
                break
            self._record(was_halted)
        self.refresh()

    def run(self) -> None:
        if not self._need_program():
            return
        was_halted = self.dumps[-1].halted
        if self._cmd_ok(self.session.execute("run")):
            self.ran = True
            self._record(was_halted)
        self.refresh()

    def dump(self) -> None:
        if not self._need_program():
            return
        if self._cmd_ok(self.session.execute("dump")):
            self._record(True)
        self.refresh()

    def _record(self, replace_last: bool) -> None:
        """Una columna nueva por paso/Ejecutar; Dump y Paso sobre un CPU detenido no agregan."""
        cur = self.session.cur
        if replace_last:
            self.dumps[-1] = cur
        else:
            self.dumps.append(cur)

    def close(self) -> None:
        if self.golden is not None:
            self.golden.close()
            self.golden = None

    # ------------------------------------------------------------ dibujo

    def _compare(self) -> tuple[set[str], str]:
        try:
            return check(self.golden, self.dumps, self.ran)
        except (RuntimeError, OSError) as e:
            return set(), f"golden: error ({e})"

    def _refresh_status(self) -> None:
        text = self.verdict
        if self.keys:
            text += ": " + ", ".join(sorted(self.keys)[:8])
        self.bottom_var.set("   ".join(s for s in (text, self.notice) if s))

    def refresh(self) -> None:
        d = self.session.cur
        if d is None:
            return
        self.keys, self.verdict = self._compare()
        self.status_var.set(status_text(d))
        prev = self.session.prev
        for i, lab in enumerate(self.reg_labels):
            changed = prev is not None and prev.x[i] != d.x[i]
            bg = RED if f"x{i}" in self.keys else YELLOW if changed else self.root.cget("bg")
            lab.configure(text=reg_text(i, d.x[i]), bg=bg)
        self.pipe_var.set("\n".join(self.session.execute("pipe")))
        for var, (name, words, decoded) in zip(self.latch_vars, latch_lines(d)):
            var.set(f"{name:<7}{words}\n{'':<7}{decoded}")
        self.mem.delete(0, "end")
        for i, (addr, val) in enumerate(d.mem):
            self.mem.insert("end", f"0x{addr:08x}: 0x{val:08x}")
            if f"mem[0x{addr:08x}]" in self.keys:
                self.mem.itemconfig(i, bg=RED)
        if not d.mem:
            self.mem.insert("end", "(sin palabras escritas)")
        self._draw_diagram()
        self._refresh_status()

    def _draw_diagram(self) -> None:
        self.rows = build(self.dumps)
        ncols, words = len(self.dumps), self.session.words
        self.lab.delete("all")
        self.cells.delete("all")
        height = HEAD_H + CELL_H * len(self.rows)
        self.lab.create_text(4, HEAD_H // 2, anchor="w", text="instrucción", font=MONO_BOLD)
        for c in range(ncols):
            self.cells.create_text(c * CELL_W + CELL_W // 2, HEAD_H // 2, text=f"D{c}",
                                   font=MONO_BOLD)
        for r, row in enumerate(self.rows):
            y = HEAD_H + r * CELL_H
            self.lab.create_text(4, y + CELL_H // 2, anchor="w", text=row_label(row, words),
                                 font=MONO)
            for c, text in row.cells.items():
                x = c * CELL_W
                color = "#cc0000" if "×" in text else "#888888" if "*" in text else "black"
                self.cells.create_rectangle(x + 1, y + 1, x + CELL_W - 1, y + CELL_H - 1,
                                            fill="#eef3ff", outline="#9aa5c0")
                self.cells.create_text(x + CELL_W // 2, y + CELL_H // 2, text=text, fill=color,
                                       font=MONO)
        self.lab.configure(scrollregion=(0, 0, LABEL_W, height))
        self.cells.configure(scrollregion=(0, 0, ncols * CELL_W, height))
        self.cells.xview_moveto(1.0)


# ---------------------------------------------------------------- entrada

def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(prog="py -m host.gui")
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--port", help="puerto serie, p. ej. COM5")
    group.add_argument("--fake", action="store_true", help="placa simulada sobre el ISS")
    ap.add_argument("--iss", default=DEFAULT_ISS, help=f"ruta de iss.exe (default {DEFAULT_ISS})")
    ap.add_argument("--fake-fault", action="append", type=parse_fault, default=[],
                    metavar="xN=valor",
                    help="solo con --fake: fuerza el registro xN en la placa simulada "
                         "(para probar la marca de divergencia)")
    args = ap.parse_args(argv)
    if args.fake_fault and not args.fake:
        ap.error("--fake-fault requiere --fake")

    iss_ok = Path(args.iss).exists()
    notice = ""
    try:
        if args.fake:
            if not iss_ok:
                print(f"error: falta {args.iss} (py TP3_FINAL/tools/run.py iss)", file=sys.stderr)
                return 2
            from host.fakeboard import FakeBoard
            link = Link(FakeBoard(args.iss, fault=dict(args.fake_fault) or None))
        else:
            link = Link.open(args.port)
            if not iss_ok:
                notice = f"sin golden: falta {args.iss} (py TP3_FINAL/tools/run.py iss)"
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    def golden_for(words: list[int]) -> Golden | None:
        return Golden(args.iss, words) if iss_ok else None

    try:
        root = tk.Tk()
    except tk.TclError as e:
        link.close()
        print(f"error: no se pudo abrir la ventana: {e}", file=sys.stderr)
        return 2
    app = App(root, Session(link), golden_for, notice)
    try:
        root.mainloop()
    finally:
        app.close()
        link.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""CLI de texto sobre el protocolo UART v1: `py -m host.cli (--port COMx | --fake)`.

La lógica está en `Session` (devuelve líneas de salida, sin E/S) para poder
compararla en tests; `main()` solo lee e imprime. Sin colores ni curses.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterator

from asm.disasm import disasm, disasm_at
from asm.rvasm import AsmError, assemble
from host.dump import Dump
from host.link import Link, LinkError

DEFAULT_ISS = "../build/iss.exe"
_HEX_WORD = re.compile(r"[0-9a-fA-F]{1,8}")


class CliError(Exception):
    """Error de uso o de archivo de entrada de la CLI."""


def _read_hex(path: Path) -> list[int]:
    words = []
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        text = raw.strip()
        if not text:
            continue
        if not _HEX_WORD.fullmatch(text):
            raise CliError(f"{path}:{n}: palabra inválida '{text}'")
        words.append(int(text, 16))
    return words


class Session:
    def __init__(self, link: Link) -> None:
        self.link = link
        self.cur: Dump | None = None
        self.prev: Dump | None = None
        self.words: list[int] = []
        self.errors = 0
        self.done = False

    def start(self) -> list[str]:
        """Conexión inicial: lo que se imprime al arrancar."""
        return self.execute("version")

    def execute(self, line: str) -> list[str]:
        parts = line.split()
        if not parts:
            return []
        out: list[str] = []
        handler = getattr(self, "_cmd_" + parts[0], None) if parts[0].isalpha() else None
        try:
            if handler is None:
                raise CliError(f"comando desconocido '{parts[0]}'")
            handler(parts[1:], out)
        except (LinkError, AsmError, OSError, CliError) as e:
            out.append(f"error: {e}")
        self.errors += sum(1 for s in out if s.startswith("error:"))
        return out

    def _new(self, d: Dump) -> None:
        self.prev, self.cur = self.cur, d

    def _state(self) -> Dump:
        if self.cur is None:
            raise CliError("no hay estado (usar dump)")
        return self.cur

    # ------------------------------------------------------------------ comandos

    def _cmd_version(self, args: list[str], out: list[str]) -> None:
        v = self.link.connect()
        out.append(f"conectado: protocolo {v.proto}, imem {v.imem_words}, "
                   f"dmem {v.dmem_words} palabras")

    def load_path(self, path: Path) -> list[int]:
        """Ensambla (.s) o lee (.hex), carga en la placa y deja el dump inicial como estado."""
        if path.suffix == ".s":
            words = assemble(path.read_text(encoding="utf-8"))
        elif path.suffix == ".hex":
            words = _read_hex(path)
        else:
            raise CliError(f"extensión no soportada '{path.suffix}' (usar .s o .hex)")
        self.link.load(words)
        self.words = words
        d = self.link.dump()
        self.prev, self.cur = None, d
        return words

    def _cmd_load(self, args: list[str], out: list[str]) -> None:
        if len(args) != 1:
            raise CliError("uso: load <ruta>")
        words = self.load_path(Path(args[0]))
        out.append(f"cargado: {len(words)} palabras ({args[0]})")

    def _cmd_reset(self, args: list[str], out: list[str]) -> None:
        self.link.reset()
        self._new(self.link.dump())
        out.append("reset: ok")

    def _cmd_step(self, args: list[str], out: list[str]) -> None:
        if len(args) > 1 or (args and not args[0].isdigit()) or (args and int(args[0]) < 1):
            raise CliError("uso: step [n]")
        for _ in range(int(args[0]) if args else 1):
            d = self.link.step()
            self._new(d)
            out.append(f"paso: ciclos={d.cycles} pc=0x{d.pc:08x}" + (" halted" if d.halted else ""))

    def _cmd_run(self, args: list[str], out: list[str]) -> None:
        d = self.link.run()
        self._new(d)
        reason = ("halt" if d.halted else "timeout" if d.timeout
                  else "abort" if d.aborted else "desconocido")
        pc = d.latches[11] if d.halted else d.pc
        out.append(f"run: {reason} ciclos={d.cycles} pc=0x{pc:08x}")

    def _cmd_dump(self, args: list[str], out: list[str]) -> None:
        d = self.link.dump()
        self._new(d)
        out.append(f"dump: ciclos={d.cycles} pc=0x{d.pc:08x} halted={int(d.halted)}")

    def _cmd_regs(self, args: list[str], out: list[str]) -> None:
        d = self._state()
        for j in range(8):
            cells = []
            for i in range(4 * j, 4 * j + 4):
                changed = self.prev is not None and self.prev.x[i] != d.x[i]
                cells.append(f"x{i:<2}=0x{d.x[i]:08x}{'*' if changed else ' '}")
            out.append(" ".join(cells).rstrip())

    def _cmd_mem(self, args: list[str], out: list[str]) -> None:
        d = self._state()
        out += [f"0x{a:08x}: 0x{v:08x}" for a, v in d.mem] or ["(sin palabras escritas)"]

    def _cmd_pipe(self, args: list[str], out: list[str]) -> None:
        d = self._state()
        stages = [
            ("IF", not d.stop_fetch and not d.halted, d.pc, lambda pc: disasm_at(self.words, pc)),
            ("ID", d.valid_id, d.latches[0], lambda pc: disasm(d.latches[1])),
            ("EX", d.valid_ex, d.latches[2], lambda pc: disasm_at(self.words, pc)),
            ("MEM", d.valid_mem, d.latches[7], lambda pc: disasm_at(self.words, pc)),
            ("WB", d.valid_wb, d.latches[11], lambda pc: disasm_at(self.words, pc)),
        ]
        for name, valid, pc, text in stages:
            out.append(f"{name:<4}" + (f"0x{pc:08x}  {text(pc)}" if valid else "--"))

    def _cmd_raw(self, args: list[str], out: list[str]) -> None:
        if len(args) != 1 or not re.fullmatch(r"[0-9a-fA-F]{1,2}", args[0]):
            raise CliError("uso: raw <hh>")
        out.append(f"raw: E {self.link.raw_error(int(args[0], 16)):02x}")

    def _cmd_quit(self, args: list[str], out: list[str]) -> None:
        self.done = True


def run_script(session: Session, lines: list[str]) -> Iterator[str]:
    """Ejecuta un guion: ignora vacías y `#`, y antes de cada comando emite `> <comando>`."""
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        yield f"> {line}"
        yield from session.execute(line)
        if session.done:
            return


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(prog="py -m host.cli")
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--port", help="puerto serie, p. ej. COM5")
    group.add_argument("--fake", action="store_true", help="placa simulada sobre el ISS")
    ap.add_argument("--script", help="archivo de comandos")
    ap.add_argument("--iss", default=DEFAULT_ISS, help=f"ruta de iss.exe (default {DEFAULT_ISS})")
    args = ap.parse_args(argv)

    script: list[str] | None = None
    try:
        if args.script:
            script = Path(args.script).read_text(encoding="utf-8").splitlines()
        if args.fake:
            if not Path(args.iss).exists():
                print(f"error: falta {args.iss} (py TP3_FINAL/tools/run.py iss)", file=sys.stderr)
                return 2
            from host.fakeboard import FakeBoard
            link = Link(FakeBoard(args.iss))
        else:
            link = Link.open(args.port)
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    session = Session(link)
    try:
        start = session.start()
        print("\n".join(start))
        if session.errors:
            return 1
        if script is not None:
            for text in run_script(session, script):
                print(text)
        else:
            while not session.done:
                try:
                    line = input("rv> ")
                except EOFError:
                    break
                for text in session.execute(line):
                    print(text)
    finally:
        link.close()
    return 1 if session.errors else 0


if __name__ == "__main__":
    sys.exit(main())

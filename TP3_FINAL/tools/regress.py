"""Regresión de tres niveles (B-27): cada programa de TP3_FINAL/programs contra su .expected.json.

Se invoca con `py TP3_FINAL/tools/run.py regress [--levels iss,fake,rtl,board] [--board COMx]
[--program <nombre>] [--iss-mutant sra]`. Niveles:
  iss    build/iss.exe (o build/iss_mut.exe con --iss-mutant)
  fake   Link sobre FakeBoard (placa simulada sobre el ISS)
  rtl    tb_system_prog_stub una vez mientras CPU_FILES (tools/tbs.py) esté vacío; con CPU real,
         tb_system_prog por programa
  board  placa real en --board
Salidas en TP3_FINAL/build/regress/<programa>.<nivel>.json.
"""
from __future__ import annotations

import contextlib
import io
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

TOOLS = Path(__file__).resolve().parent
TP3 = TOOLS.parent
REPO = TP3.parent
SW = TP3 / "sw"
PROGRAMS = TP3 / "programs"
BUILD = TP3 / "build"
OUT = BUILD / "regress"
ISS_EXE = BUILD / "iss.exe"
ISS_MUT = BUILD / "iss_mut.exe"

for _p in (TOOLS, SW):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

from host import canonical  # noqa: E402
from host.dump import decode  # noqa: E402
from host.fakeboard import FakeBoard  # noqa: E402
from host.link import Link  # noqa: E402
from tbs import CPU_FILES  # noqa: E402

LEVELS = ("iss", "fake", "rtl", "board")
FAKE_RUN_LIMIT = 10_000
MUT_MARKER = "// MUT:sra"
MUT_LINE = "static uint32_t op_sra(uint32_t a, uint32_t sh) { return a >> (sh & 31); } // MUT:sra"


def _words(name: str) -> list[int]:
    return [int(w, 16) for w in (PROGRAMS / f"{name}.hex").read_text().split()]


def _need_iss(exe: Path) -> None:
    if not exe.exists():
        raise FileNotFoundError(f"falta {exe.relative_to(REPO).as_posix()} "
                                "(py TP3_FINAL/tools/run.py iss)")


def _level_iss(name: str, exe: Path) -> dict[str, Any]:
    _need_iss(exe)
    out = OUT / f"{name}.iss.json"
    r = subprocess.run([str(exe), str(PROGRAMS / f"{name}.hex"), "-o", str(out)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"iss devolvió {r.returncode}: {r.stderr.strip()}")
    return canonical.load(out)


def _level_fake(name: str) -> dict[str, Any]:
    _need_iss(ISS_EXE)
    link = Link(FakeBoard(ISS_EXE, run_limit=FAKE_RUN_LIMIT))
    try:
        link.load(_words(name))
        result = canonical.from_dump(link.run())
    finally:
        link.close()
    canonical.save(result, OUT / f"{name}.fake.json")
    return result


def _level_rtl(name: str) -> dict[str, Any]:
    import run

    dump_file = OUT / f"{name}.rtl.dump.hex"
    plusargs = [f"+prog={(PROGRAMS / f'{name}.hex').as_posix()}",
                f"+out={dump_file.relative_to(REPO).as_posix()}"]
    with contextlib.redirect_stdout(io.StringIO()):
        ok = run.run_tb("tb_system_prog", plusargs)
    if not ok:
        raise RuntimeError("tb_system_prog falló (ver TP3_FINAL/build/tb_system_prog.log)")
    dump = decode(bytes(int(b, 16) for b in dump_file.read_text().split()))
    result = canonical.from_dump(dump)
    canonical.save(result, OUT / f"{name}.rtl.json")
    return result


class _Board:
    """Abre el puerto la primera vez que se usa y lo reutiliza para todos los programas."""

    def __init__(self, port: str) -> None:
        self.port = port
        self.link: Link | None = None

    def run(self, name: str) -> dict[str, Any]:
        if self.link is None:
            link = Link.open(self.port)
            try:
                link.connect()
            except Exception:
                link.close()
                raise
            self.link = link
        self.link.load(_words(name))
        result = canonical.from_dump(self.link.run())
        canonical.save(result, OUT / f"{name}.board.json")
        return result

    def close(self) -> None:
        if self.link is not None:
            self.link.close()


def _stub_rtl() -> bool:
    import run

    with contextlib.redirect_stdout(io.StringIO()):
        return run.run_tb("tb_system_prog_stub")


def _build_mutant() -> Path:
    """build/iss_mut.exe: el ISS con el SRA lógico en lugar del aritmético."""
    import run

    src = SW / "iss" / "iss.cpp"
    lines = src.read_text(encoding="utf-8").splitlines(keepends=True)
    hits = [i for i, line in enumerate(lines) if MUT_MARKER in line]
    if len(hits) != 1:
        raise RuntimeError("falta // MUT:sra en iss.cpp (B-21)")
    eol = "\r\n" if lines[hits[0]].endswith("\r\n") else "\n"
    lines[hits[0]] = MUT_LINE + eol
    mut = BUILD / "mut" / "iss.cpp"
    mut.parent.mkdir(parents=True, exist_ok=True)
    mut.write_text("".join(lines), encoding="utf-8")
    cmd = run.GPP + ["-I", (SW / "iss").as_posix(), "-o", ISS_MUT.as_posix(),
                     mut.as_posix(), (SW / "iss" / "iss_main.cpp").as_posix()]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"no compila el mutante:\n{r.stderr.strip()}")
    return ISS_MUT


def _table(names: list[str], cells: dict[str, dict[str, str]]) -> list[str]:
    width = max([len("programa")] + [len(n) for n in names]) + 2
    rows = [("programa".ljust(width) + "".join(f"{lv:<6}" for lv in LEVELS)).rstrip()]
    for n in names:
        rows.append((n.ljust(width) + "".join(f"{cells[n].get(lv, '-'):<6}" for lv in LEVELS)).rstrip())
    return rows


def main(args) -> int:
    levels = [lv for lv in args.levels.split(",") if lv]
    unknown = [lv for lv in levels if lv not in LEVELS]
    if unknown or not levels:
        print(f"error: niveles inválidos {unknown or args.levels!r} (válidos: {','.join(LEVELS)})")
        return 2
    if args.board and "board" not in levels:
        levels.append("board")
    if "board" in levels and not args.board:
        print("error: el nivel board necesita --board COMx")
        return 2
    if args.iss_mutant and "iss" not in levels:
        print("error: --iss-mutant necesita el nivel iss")
        return 2
    names = sorted(p.stem for p in PROGRAMS.glob("*.s"))
    if args.program:
        if args.program not in names:
            print(f"error: no existe programs/{args.program}.s")
            return 2
        names = [args.program]

    OUT.mkdir(parents=True, exist_ok=True)
    iss_exe = ISS_EXE
    if args.iss_mutant:
        try:
            iss_exe = _build_mutant()
        except Exception as e:
            print(f"ERR: {e}")
            return 1

    runners: dict[str, Callable[[str], dict[str, Any]]] = {}
    if "iss" in levels:
        runners["iss"] = lambda n: _level_iss(n, iss_exe)
    if "fake" in levels:
        runners["fake"] = _level_fake
    if "rtl" in levels and CPU_FILES:
        runners["rtl"] = _level_rtl
    board = _Board(args.board) if "board" in levels else None
    if board:
        runners["board"] = board.run

    cells: dict[str, dict[str, str]] = {n: {} for n in names}
    failures: list[str] = []
    try:
        for n in names:
            expected = canonical.load(PROGRAMS / f"{n}.expected.json")
            for lv in LEVELS:
                if lv not in runners:
                    continue
                try:
                    got = runners[lv](n)
                except Exception as e:
                    cells[n][lv] = "ERR"
                    failures.append(f"{n} [{lv}] ERR: {e}")
                    continue
                diffs = canonical.diff(expected, got, "esperado", lv)
                cells[n][lv] = "FAIL" if diffs else "OK"
                failures += [f"{n} [{lv}] {d}" for d in diffs]
    finally:
        if board:
            board.close()

    print("\n".join(_table(names, cells)))
    if "rtl" in levels and not CPU_FILES:
        stub_ok = _stub_rtl()
        print(f"rtl: stub (sin CPU real) {'OK' if stub_ok else 'FAIL'}")
        if not stub_ok:
            failures.append("rtl [stub] tb_system_prog_stub falló "
                            "(ver TP3_FINAL/build/tb_system_prog_stub.log)")
    if failures:
        print("\nFALLAS:")
        print("\n".join(failures))
    return 1 if failures else 0

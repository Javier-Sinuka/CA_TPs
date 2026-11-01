"""Runner único de TP3 (convenciones.md §3).

Uso, desde la raíz del repo:
    py TP3_FINAL/tools/run.py tb <nombre> [+plusarg ...]
    py TP3_FINAL/tools/run.py tbs
    py TP3_FINAL/tools/run.py synth_ooc <top>
iverilog y vvp corren con cwd = raíz del repo: los TB abren archivos con rutas relativas a esa raíz.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parents[1]
BUILD = REPO / "TP3_FINAL" / "build"
sys.path.insert(0, str(TOOLS))
from tbs import SYNTH, TBS  # noqa: E402

VIVADO = os.environ.get("VIVADO", "C:/Xilinx/Vivado/2024.1/bin/vivado.bat")
BAD_SYNTH = re.compile(r"inferring latch|multi-driven|implicit", re.IGNORECASE)


def run_tb(name: str, plusargs: list[str] | None = None) -> bool:
    spec = TBS[name]
    top = spec["top"]
    files = [REPO / f for f in spec["files"]]
    incdirs = sorted({f.parent.as_posix() for f in files}
                     | {(REPO / d).as_posix() for d in spec.get("incdirs", [])})
    BUILD.mkdir(parents=True, exist_ok=True)
    vvp = BUILD / f"{name}.vvp"
    log = BUILD / f"{name}.log"
    cmd = ["iverilog", "-g2012", "-Wall", "-Wno-timescale"]
    cmd += [f"-I{d}" for d in incdirs]
    cmd += [f"-D{k}={v}" for k, v in spec.get("defines", {}).items()]
    cmd += [f"-P{top}.{k}={v}" for k, v in spec.get("params", {}).items()]
    cmd += ["-s", top, "-o", vvp.as_posix()] + [f.as_posix() for f in files]
    comp = subprocess.run(cmd, capture_output=True, text=True, cwd=REPO)
    if comp.returncode != 0:
        log.write_text(comp.stdout + comp.stderr)
        print(f"FAIL {name}: no compila (ver {log.relative_to(REPO).as_posix()})")
        return False
    sim = subprocess.run(["vvp", "-n", vvp.as_posix(), *(plusargs or [])],
                         capture_output=True, text=True, cwd=REPO)
    out = comp.stdout + comp.stderr + sim.stdout + sim.stderr
    log.write_text(out)
    lines = out.splitlines()
    has_fail = any(l.startswith("FAIL") for l in lines)
    if spec.get("legacy"):
        ok = sim.returncode == 0 and not has_fail and not any("TIMEOUT" in l for l in lines)
    else:
        ok = (sim.returncode == 0 and not has_fail
              and any(l.startswith(f"PASS {top}:") for l in lines))
    print(f"{'PASS' if ok else 'FAIL'} {name} (log: {log.relative_to(REPO).as_posix()})")
    return ok


def run_tbs() -> bool:
    results = [run_tb(n) for n in TBS]
    print(f"tbs: {sum(results)}/{len(results)} PASS")
    return all(results)


def run_vivado(tcl: str, log: Path, args: list[str]) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    cmd = [VIVADO, "-mode", "batch", "-nojournal", "-log", log.as_posix(),
           "-source", (TOOLS / tcl).as_posix(), "-tclargs", *args]
    return subprocess.run(cmd).returncode


def bad_synth_lines(log: Path) -> list[str]:
    text = log.read_text(errors="replace") if log.exists() else ""
    return [l for l in text.splitlines() if BAD_SYNTH.search(l)]


def run_synth(top: str) -> bool:
    out = BUILD / "synth_ooc" / top
    log = out / "vivado.log"
    files = [(REPO / f).as_posix() for f in SYNTH[top]]
    rc = run_vivado("synth_ooc.tcl", log, [top, out.as_posix(), *files])
    bad = bad_synth_lines(log)
    for l in bad:
        print(f"  {l}")
    ok = rc == 0 and not bad
    print(f"{'PASS' if ok else 'FAIL'} synth_ooc {top} (log: {log.relative_to(REPO).as_posix()})")
    return ok


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="run.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    ptb = sub.add_parser("tb")
    ptb.add_argument("name", choices=sorted(TBS))
    ptb.add_argument("plusargs", nargs="*", help="se pasan a vvp, por ejemplo +SEED=3")
    sub.add_parser("tbs")
    sub.add_parser("synth_ooc").add_argument("top", choices=sorted(SYNTH))
    a = p.parse_args(argv)
    if a.cmd == "tb":
        ok = run_tb(a.name, a.plusargs)
    elif a.cmd == "tbs":
        ok = run_tbs()
    else:
        ok = run_synth(a.top)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

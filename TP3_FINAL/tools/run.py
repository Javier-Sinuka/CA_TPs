"""Runner único de TP3 (convenciones.md §3).

Uso, desde la raíz del repo:
    py TP3_FINAL/tools/run.py tb <nombre> [+plusarg ...]
    py TP3_FINAL/tools/run.py tbs
    py TP3_FINAL/tools/run.py mutate
    py TP3_FINAL/tools/run.py synth_ooc <top>
    py TP3_FINAL/tools/run.py vectors
    py TP3_FINAL/tools/run.py pytest
    py TP3_FINAL/tools/run.py iss
    py TP3_FINAL/tools/run.py test
    py TP3_FINAL/tools/run.py bit <top> [--mhz 50|100] [--clk wiz|mmcm] [--define NAME]
    py TP3_FINAL/tools/run.py program <archivo.bit>
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
from tbs import BITS, CLK_GEN, MUTATIONS, SYNTH, TBS  # noqa: E402

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


def run_mutate() -> bool:
    ok_all = True
    for m in MUTATIONS:
        src = REPO / m["file"]
        text = src.read_text(encoding="utf-8")
        n = text.count(m["old"])
        if n != 1:
            print(f"FAIL mutate {m['name']}: el texto original aparece {n} veces")
            ok_all = False
            continue
        mfile = BUILD / "mut" / m["name"] / src.name
        mfile.parent.mkdir(parents=True, exist_ok=True)
        mfile.write_text(text.replace(m["old"], m["new"]), encoding="utf-8")
        spec = dict(TBS[m["tb"]])
        spec["files"] = [mfile.relative_to(REPO).as_posix() if f == m["file"] else f
                         for f in spec["files"]]
        name = f"mut_{m['name']}"
        TBS[name] = spec
        detected = not run_tb(name)
        print(f"{'PASS' if detected else 'FAIL'} mutate {m['name']}: "
              f"{'detectada' if detected else 'NO detectada'}")
        ok_all = ok_all and detected
    return ok_all


def run_vectors() -> bool:
    rc = subprocess.run([sys.executable, (TOOLS / "gen_vectors.py").as_posix(), "--check"],
                        cwd=REPO).returncode
    return rc == 0


def run_pytest() -> bool:
    rc = subprocess.run([sys.executable, "-m", "pytest", "-q"], cwd=REPO / "TP3_FINAL" / "sw").returncode
    return rc == 0


GPP = ["g++", "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror"]


def run_iss() -> str:
    """Devuelve "OK", "FAIL" o "SKIP" (todavía no hay test_iss.cpp: B-21)."""
    iss = REPO / "TP3_FINAL" / "sw" / "iss"
    if not (iss / "test_iss.cpp").exists():
        print("SKIP iss: sw/iss/test_iss.cpp no existe (B-21)")
        return "SKIP"
    BUILD.mkdir(parents=True, exist_ok=True)
    for exe, sources in (("iss.exe", ["iss.cpp", "iss_main.cpp"]),
                         ("test_iss.exe", ["iss.cpp", "test_iss.cpp"])):
        cmd = GPP + ["-o", (BUILD / exe).as_posix()] + [(iss / s).as_posix() for s in sources]
        if subprocess.run(cmd, cwd=REPO).returncode != 0:
            print(f"FAIL iss: no compila {exe}")
            return "FAIL"
    ok = subprocess.run([(BUILD / "test_iss.exe").as_posix()], cwd=REPO).returncode == 0
    print(f"{'PASS' if ok else 'FAIL'} iss")
    return "OK" if ok else "FAIL"


def run_test() -> bool:
    """Orden de convenciones.md §3: iss, vectors --check, tbs, pytest, mutate; sin cortar en la primera falla."""
    steps = [
        ("iss", run_iss),
        ("vectors", run_vectors),
        ("tbs", run_tbs),
        ("pytest", run_pytest),
        ("mutate", run_mutate),
    ]
    results = []
    for name, fn in steps:
        r = fn()
        results.append((name, r if isinstance(r, str) else ("OK" if r else "FAIL")))
    print("resumen:")
    for name, r in results:
        print(f"  {name:<9}{r}")
    return all(r != "FAIL" for _, r in results)


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


def run_bit(top: str, mhz: int, clk: str, defines: list[str] | None = None) -> bool:
    spec = BITS[top]
    out = BUILD / "bit" / f"{top}_{mhz}mhz_{clk}"
    log = out / "vivado.log"
    files = [(REPO / f).as_posix() for f in spec["files"]]
    if clk == "mmcm":
        files.append((REPO / CLK_GEN).as_posix())
    defs = ",".join(defines) if defines else "-"
    rc = run_vivado("build_bit.tcl", log,
                    [top, str(mhz), out.as_posix(), clk, (REPO / spec["xdc"]).as_posix(), defs, *files])
    bad = bad_synth_lines(log)
    for l in bad:
        print(f"  {l}")
    summary = out / "summary.txt"
    wns_ok = False
    if summary.exists():
        text = summary.read_text().strip()
        print(text)
        m = re.search(r"WNS=(-?[0-9.]+)", text)
        wns_ok = m is not None and float(m.group(1)) >= 0.0
    ok = rc == 0 and not bad and wns_ok
    bit = (out / f"{top}.bit").relative_to(REPO).as_posix()
    print(f"{'PASS' if ok else 'FAIL'} bit {top} {mhz} MHz ({clk}) -> {bit}")
    return ok


def run_program(bit: str) -> bool:
    log = BUILD / "program" / "vivado.log"
    rc = run_vivado("program.tcl", log, [Path(bit).resolve().as_posix()])
    print(f"{'PASS' if rc == 0 else 'FAIL'} program {bit}")
    return rc == 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="run.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    ptb = sub.add_parser("tb")
    ptb.add_argument("name", choices=sorted(TBS))
    ptb.add_argument("plusargs", nargs="*", help="se pasan a vvp, por ejemplo +SEED=3")
    sub.add_parser("tbs")
    sub.add_parser("mutate")
    sub.add_parser("vectors")
    sub.add_parser("pytest")
    sub.add_parser("iss")
    sub.add_parser("test")
    sub.add_parser("synth_ooc").add_argument("top", choices=sorted(SYNTH))
    pb = sub.add_parser("bit")
    pb.add_argument("top", choices=sorted(BITS))
    pb.add_argument("--mhz", type=int, default=50)
    pb.add_argument("--clk", choices=["wiz", "mmcm"], default="wiz")
    pb.add_argument("--define", action="append", default=[], metavar="NAME",
                    help="repetible; va a synth_design -verilog_define (B-17 usa --define CPU_STUB)")
    sub.add_parser("program").add_argument("bitfile")
    a = p.parse_args(argv)
    if a.cmd == "tb":
        ok = run_tb(a.name, a.plusargs)
    elif a.cmd == "tbs":
        ok = run_tbs()
    elif a.cmd == "mutate":
        ok = run_mutate()
    elif a.cmd == "vectors":
        ok = run_vectors()
    elif a.cmd == "pytest":
        ok = run_pytest()
    elif a.cmd == "iss":
        ok = run_iss() != "FAIL"
    elif a.cmd == "test":
        ok = run_test()
    elif a.cmd == "bit":
        ok = run_bit(a.top, a.mhz, a.clk, a.define)
    elif a.cmd == "program":
        ok = run_program(a.bitfile)
    else:
        ok = run_synth(a.top)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

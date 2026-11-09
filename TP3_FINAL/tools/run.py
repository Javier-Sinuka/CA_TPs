"""Phase 1 elaboration and registered testbenches."""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

sys.dont_write_bytecode = True
from tbs import EXTERNAL_SYNTH, EXTERNAL_TBS, PHASE1_TOPS, RTL, SYNTH, SYNTH_COMPANION_HEADERS, TBS


TP3_FINAL = Path(__file__).resolve().parents[1]
REPO = TP3_FINAL.parent


def elaborate_phase1() -> int:
    include_dir = TP3_FINAL / RTL
    with tempfile.TemporaryDirectory(prefix="a01-elaborate-") as build_dir:
        for top, sources in PHASE1_TOPS.items():
            command = [
                "iverilog", "-g2012", "-Wall", "-Wno-timescale", "-I", str(include_dir),
                "-s", top, "-o", str(Path(build_dir) / f"{top}.vvp"),
                *(str(TP3_FINAL / source) for source in sources),
            ]
            print(f"[{top}] {' '.join(command)}", flush=True)
            try:
                result = subprocess.run(command, check=False)
            except FileNotFoundError:
                print("iverilog is not installed or is not on PATH", file=sys.stderr)
                return 127
            if result.returncode:
                return result.returncode
    print("Elaboration passed for: " + ", ".join(PHASE1_TOPS))
    return 0


def run_tb(name: str, companion: Path | None = None) -> int:
    spec = TBS[name] if name in TBS else EXTERNAL_TBS[name]
    top = spec["top"]
    build = TP3_FINAL / "build"
    build.mkdir(exist_ok=True)
    output = build / f"{name}.vvp"
    log = build / f"{name}.log"
    if (spec.get("companion_files") or spec.get("companion_headers")) and companion is None:
        print(f"{name} requires --companion PATH", file=sys.stderr)
        return 1
    sources = [REPO / source for source in spec["files"]]
    headers = []
    if companion is not None:
        sources.extend(companion / source for source in spec.get("companion_files", ()))
        headers.extend(companion / source for source in spec.get("companion_headers", ()))
    missing = [source for source in (*sources, *headers) if not source.is_file()]
    if missing:
        print("Missing sources: " + ", ".join(str(source) for source in missing), file=sys.stderr)
        return 1
    incdirs = {str(source.parent) for source in (*sources, *headers)}
    command = ["iverilog", "-g2012", "-Wall", "-Wno-timescale"]
    for incdir in sorted(incdirs):
        command.extend(("-I", incdir))
    for key, value in sorted(spec.get("defines", {}).items()):
        command.append(f"-D{key}={value}")
    command.extend(("-s", top, "-o", str(output)))
    command.extend(str(source) for source in sources)
    print(' '.join(command), flush=True)
    try:
        result = subprocess.run(command, cwd=REPO, check=False)
        if result.returncode:
            return 1
        command = ["vvp", "-n", str(output)]
        print(' '.join(command), flush=True)
        result = subprocess.run(command, cwd=REPO, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                check=False)
    except FileNotFoundError as error:
        print(f"Tool unavailable: {error.filename}", file=sys.stderr)
        return 1
    log.write_text(result.stdout)
    print(result.stdout, end="")
    lines = result.stdout.splitlines()
    passed = result.returncode == 0 and any(
        line.startswith(f"PASS {top}:") for line in lines
    ) and not any(line.startswith("FAIL") for line in lines)
    if not passed:
        print(f"{name}: failed runner contract (see {log})", file=sys.stderr)
        return 1
    return 0


def synth_ooc(top: str, companion: Path | None = None) -> int:
    if (top in EXTERNAL_SYNTH or top in SYNTH_COMPANION_HEADERS) and companion is None:
        print(f"{top} requires --companion PATH", file=sys.stderr)
        return 1
    root = companion.resolve() if top in EXTERNAL_SYNTH else REPO
    sources = [root / source for source in SYNTH[top]]
    sources.extend(companion.resolve() / source for source in SYNTH_COMPANION_HEADERS.get(top, ()))
    missing = [source for source in sources if not source.is_file()]
    if missing:
        print("Missing sources: " + ", ".join(str(source) for source in missing), file=sys.stderr)
        return 1
    output = TP3_FINAL / "build" / "synth_ooc" / top
    output.mkdir(parents=True, exist_ok=True)
    log = output / "vivado.log"
    vivado = os.environ.get("VIVADO", "vivado")
    command = [vivado, "-mode", "batch", "-nojournal", "-log", str(log),
               "-source", str(TP3_FINAL / "tools" / "synth_ooc.tcl"),
               "-tclargs", top, str(output), *(str(source) for source in sources)]
    print(" ".join(command), flush=True)
    try:
        result = subprocess.run(command, cwd=output, check=False)
    except FileNotFoundError:
        print(f"Vivado unavailable: {vivado}", file=sys.stderr)
        return 127
    content = log.read_text(errors="replace") if log.exists() else ""
    errors = [line for line in content.splitlines() if re.search(
        r"inferring latch|multiple drivers|multi[- ]driven|implicit net",
        line, re.IGNORECASE)]
    util = output / "util.rpt"
    if util.is_file():
        match = re.search(r"^\|\s*Register as Latch\s*\|\s*(\d+)",
                          util.read_text(errors="replace"), re.MULTILINE)
        if match is None or int(match.group(1)) != 0:
            errors.append("Unexpected or missing latch count in utilization report")
    for line in errors:
        print(line)
    passed = result.returncode == 0 and not errors and util.is_file()
    print(f"{'PASS' if passed else 'FAIL'} synth_ooc {top}: {log}")
    return 0 if passed else 1


def regress(companion: Path) -> int:
    companion = companion.resolve()
    build = TP3_FINAL / "build"
    build.mkdir(exist_ok=True)
    python = sys.executable
    common = ["--companion", str(companion)]
    commands = (
        ("ports", [python, str(TP3_FINAL / "tools/check_cpu_contract.py"), *common], ()),
        ("programs", [python, str(TP3_FINAL / "tools/check_halt_programs.py"), *common], ()),
        ("control", [python, str(TP3_FINAL / "tools/check_control_programs.py"), *common], ()),
        ("vectors", [python, str(companion / "TP3_FINAL/tools/gen_vectors.py"), "--check"], ()),
        ("rtl", [python, str(Path(__file__).resolve()), "test", *common], ()),
        ("uart", [python, str(TP3_FINAL / "tools/check_system_dumps.py"), *common], ("rtl",)),
        ("coverage", [python, str(TP3_FINAL / "tools/check_final_coverage.py"), *common,
                      "--regression-log", str(build / "a33_rtl.log")],
         ("ports", "programs", "control", "vectors", "rtl", "uart")),
    )
    results = {}
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    for name, command, dependencies in commands:
        log = build / f"a33_{name}.log"
        if any(results[dependency]["status"] != "passed" for dependency in dependencies):
            results[name] = {"status": "skipped", "command": command,
                             "reason": "required stage failed", "log": str(log)}
            log.write_text("SKIP: required stage failed\n")
            print(f"SKIP regress {name}: required stage failed", flush=True)
            continue
        print(f"RUN regress {name}: {log}", flush=True)
        try:
            with log.open("w") as output:
                result = subprocess.run(command, cwd=REPO, env=environment, stdout=output,
                                        stderr=subprocess.STDOUT, check=False)
            code = result.returncode
        except OSError as error:
            log.write_text(str(error) + "\n")
            code = 127
        results[name] = {"status": "passed" if code == 0 else "failed", "returncode": code,
                         "command": command, "log": str(log)}
        print(f"{'PASS' if code == 0 else 'FAIL'} regress {name}: exit={code}", flush=True)
        if code:
            print("\n".join(log.read_text(errors="replace").splitlines()[-12:]), flush=True)
    passed = all(result["status"] == "passed" for result in results.values())
    summary = {"timestamp_utc": datetime.now(timezone.utc).isoformat(), "cwd": str(REPO),
               "companion": str(companion), "status": "passed" if passed else "failed",
               "stages": results}
    (build / "a33_regress.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"{'PASS' if passed else 'FAIL'} regress: {len(results)} stages; synthesis is a separate synth_ooc target")
    return 0 if passed else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("elaborate_phase1", "tb", "tbs", "test", "regress", "synth_ooc"))
    parser.add_argument("name", nargs="?", choices=sorted(TBS.keys() | EXTERNAL_TBS.keys() | SYNTH.keys()))
    parser.add_argument("--companion", type=Path)
    args = parser.parse_args()
    if args.target == "regress":
        if args.name is not None or args.companion is None:
            parser.error("regress requires --companion PATH and no testbench name")
        return regress(args.companion)
    if args.target == "elaborate_phase1":
        if args.name is not None or args.companion is not None:
            parser.error("elaborate_phase1 does not accept a testbench name")
        return elaborate_phase1()
    if args.target == "tb":
        if args.name is None:
            parser.error("tb requires a testbench name")
        if args.name not in TBS and args.name not in EXTERNAL_TBS:
            parser.error(f"unknown testbench: {args.name}")
        return run_tb(args.name, args.companion)
    if args.target == "synth_ooc":
        if args.name not in SYNTH:
            parser.error("synth_ooc requires a registered top")
        return synth_ooc(args.name, args.companion)
    if args.target == "test":
        if args.name is not None or args.companion is None:
            parser.error("test requires --companion PATH and no testbench name")
        names = (*TBS, *EXTERNAL_TBS)
    else:
        if args.name is not None or args.companion is not None:
            parser.error("tbs does not accept a testbench name")
        names = TBS
    failed = []
    for top in names:
        if run_tb(top, args.companion):
            failed.append(top)
    if failed:
        print(f"FAIL {args.target}: " + ", ".join(failed), file=sys.stderr)
        return 1
    print(f"PASS {args.target}: {len(names)} testbenches")
    return 0


if __name__ == "__main__":
    sys.exit(main())

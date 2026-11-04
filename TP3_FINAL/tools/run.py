"""Phase 1 elaboration and registered testbenches."""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
from tbs import PHASE1_TOPS, RTL, TBS


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


def run_tb(name: str) -> int:
    spec = TBS[name]
    top = spec["top"]
    build = TP3_FINAL / "build"
    build.mkdir(exist_ok=True)
    output = build / f"{name}.vvp"
    log = build / f"{name}.log"
    incdirs = {str((REPO / source).parent) for source in spec["files"]}
    command = ["iverilog", "-g2012", "-Wall", "-Wno-timescale"]
    for incdir in sorted(incdirs):
        command.extend(("-I", incdir))
    command.extend(("-s", top, "-o", str(output)))
    command.extend(str(REPO / source) for source in spec["files"])
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("elaborate_phase1", "tb", "tbs"))
    parser.add_argument("name", nargs="?", choices=TBS)
    args = parser.parse_args()
    if args.target == "elaborate_phase1":
        if args.name is not None:
            parser.error("elaborate_phase1 does not accept a testbench name")
        return elaborate_phase1()
    if args.target == "tb":
        if args.name is None:
            parser.error("tb requires a testbench name")
        return run_tb(args.name)
    if args.name is not None:
        parser.error("tbs does not accept a testbench name")
    failed = []
    for top in TBS:
        if run_tb(top):
            failed.append(top)
    if failed:
        print("FAIL tbs: " + ", ".join(failed), file=sys.stderr)
        return 1
    print(f"PASS tbs: {len(TBS)} testbenches")
    return 0


if __name__ == "__main__":
    sys.exit(main())

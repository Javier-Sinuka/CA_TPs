import argparse
from pathlib import Path
import shlex
import subprocess
import sys


sys.dont_write_bytecode = True
TP3 = Path(__file__).resolve().parents[1]
REPO = TP3.parent


def check(companion: Path, vivado_bin: Path) -> None:
    from tbs import EXTERNAL_TBS

    companion = companion.resolve()
    vivado_bin = vivado_bin.resolve()
    build = TP3 / "build"
    if not (build / "a29_step_trace.csv").is_file():
        raise ValueError("run the Icarus regression before the XSim comparison")
    for target in ("tb_cpu_step_halt", "tb_system_cpu_smoke"):
        spec = EXTERNAL_TBS[target]
        sources = [REPO / path for path in spec["files"]]
        sources.extend(companion / path for path in spec.get("companion_files", ()))
        incdirs = sorted({path.parent for path in sources}
                         | {(companion / path).parent for path in spec.get("companion_headers", ())})
        output = build / f"a33_xsim_{target}"
        output.mkdir(exist_ok=True)
        extra = []
        if target == "tb_cpu_step_halt":
            local_root = output / "TP3_FINAL"
            local_root.mkdir(exist_ok=True)
            for name, destination in (("programs", TP3 / "programs"), ("build", output)):
                link = local_root / name
                if not link.exists():
                    link.symlink_to(destination, target_is_directory=True)
        else:
            frames = build / "a33_xsim_frames"
            frames.mkdir(exist_ok=True)
            link = output / "TP3_FINAL"
            if not link.exists():
                link.symlink_to(TP3, target_is_directory=True)
            extra = ["-testplusarg", f"OUT={frames}/"]
        commands = (
            [vivado_bin / "xvlog", "--sv", *[arg for path in incdirs for arg in ("-i", path)], *sources],
            [vivado_bin / "xelab", spec["top"], "-s", "a33_snapshot", "-debug", "typical"],
            [vivado_bin / "xsim", "a33_snapshot", "-runall", *extra],
        )
        logfile = build / f"a33_xsim_{target}.log"
        with logfile.open("w") as log:
            for command in commands:
                log.write(shlex.join(map(str, command)) + "\n")
                log.flush()
                subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT, check=True)
        content = logfile.read_text()
        passed = next((line for line in content.splitlines() if line.startswith(f"PASS {target}:")), None)
        if passed is None or "FAIL " in content:
            raise ValueError(f"{target}: failed XSim contract; see {logfile}")
        print(passed, flush=True)
        if target == "tb_cpu_step_halt":
            if (output / "a29_step_trace.csv").read_bytes() != (build / "a29_step_trace.csv").read_bytes():
                raise ValueError("RUN/STEP trace differs between Icarus and XSim")
            print("PASS byte-identical RUN/STEP trace: Icarus and XSim", flush=True)
        else:
            frame_files = sorted(frames.glob("a32_*.dump.hex"))
            if len(frame_files) != 34:
                raise ValueError(f"expected 34 XSim UART frames, got {len(frame_files)}")
            for frame in frame_files:
                if frame.read_bytes() != (build / frame.name).read_bytes():
                    raise ValueError(f"UART frame differs between Icarus and XSim: {frame.name}")
            print("PASS 34 byte-identical UART frames: Icarus and XSim", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--companion", type=Path, required=True)
    parser.add_argument("--vivado-bin", type=Path, required=True)
    args = parser.parse_args()
    try:
        check(args.companion, args.vivado_bin)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"FAIL final XSim: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

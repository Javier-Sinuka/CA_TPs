import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


sys.dont_write_bytecode = True
TP3 = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def check(companion: Path, frames: Path) -> None:
    sw = companion.resolve() / "TP3_FINAL/sw"
    sys.path.insert(0, str(sw))
    from asm.rvasm import assemble
    from host.dump import decode, encode, expected_length, DumpError
    from host import canonical

    labels = ["branch_reset"]
    labels += [label for step in range(1, 11) for label in (f"step_{step}", f"paused_{step}")]
    labels += [
        "branch_run", "branch_halted_dump", "branch_halted_step", "branch_halted_run",
        "after_x", "branch_rerun", "suma_run", "abort_run", "abort_dump", "timeout_run",
        "timeout_again", "step_after_timeout", "recovery_run",
    ]
    dumps = {}
    raw = {}
    for label in labels:
        data = bytes.fromhex((frames / f"a32_{label}.dump.hex").read_text())
        dump = decode(data)
        require(len(data) == expected_length(len(dump.mem)), f"{label}: wrong frame length")
        require(encode(dump) == data, f"{label}: codec round trip differs")
        require(dump.version == 1 and dump.x[0] == 0, f"{label}: version or x0 differs")
        require(dump.latches[10] & ~0x8783801F == 0, f"{label}: MEM absent fields")
        require(dump.latches[14] & ~0x8600001F == 0, f"{label}: WB absent fields")
        require(dump.latches[15] & ~255 == 0, f"{label}: reserved flags")
        require(bool(dump.latches[15] & 16) == dump.halted, f"{label}: inconsistent halted")
        bad = bytearray(data)
        bad[-1] ^= 1
        try:
            decode(bad)
        except DumpError:
            pass
        else:
            raise ValueError(f"{label}: corrupted checksum accepted")
        dumps[label] = dump
        raw[label] = data
    for label in ("branch_reset", "after_x"):
        d = dumps[label]
        require(not (d.halted or d.timeout or d.aborted) and d.cycles == d.pc == 0,
                f"{label}: incorrect reset status")
        require(d.x == (0,) * 32 and d.latches == (0,) * 16 and d.mem == (),
                f"{label}: reset did not clear logical CPU state")
    for step in range(1, 11):
        name = f"step_{step}"
        require(dumps[name].cycles == step, f"{name}: STEP is not one enabled cycle")
        require(raw[name] == raw[f"paused_{step}"], f"{name}: D changed the paused state")
    require(dumps["step_7"].load_use_stall, "missing paused load-use condition")
    require(dumps["step_9"].take_ex, "missing paused taken branch")
    require(dumps["step_10"].x[1] == 73 and dumps["step_10"].x[8:10] == (73, 21),
            "STEP partial architectural state differs")
    for label in ("branch_halted_dump", "branch_halted_step", "branch_halted_run", "branch_rerun"):
        require(raw[label] == raw["branch_run"], f"{label}: halted/restarted response differs")
    require(raw["abort_run"] == raw["abort_dump"], "D changed aborted state")
    for label in ("abort_run", "abort_dump", "timeout_run", "timeout_again", "step_after_timeout"):
        d = dumps[label]
        require(not d.halted and d.x == (0,) * 32 and not d.mem, f"{label}: infinite loop state differs")
    require(dumps["abort_run"].aborted and not dumps["abort_run"].timeout, "abort cause differs")
    require(0 < dumps["abort_run"].cycles < 1000, "abort did not precede timeout")
    for label, cycles in (("timeout_run", 1000), ("timeout_again", 2000)):
        d = dumps[label]
        require(d.timeout and not d.aborted and d.cycles == cycles, f"{label}: RUN budget or cumulative count differs")
    d = dumps["step_after_timeout"]
    require(not (d.timeout or d.aborted) and d.cycles == 2001, "STEP did not resume after timeout")

    build = TP3 / "build"
    iss = build / "a32_iss"
    command = [os.environ.get("CXX", "g++"), "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
               str(sw / "iss/iss.cpp"), str(sw / "iss/iss_main.cpp"), "-o", str(iss)]
    print(" ".join(command), flush=True)
    subprocess.run(command, check=True)
    golden = {entry["name"]: entry for entry in json.loads((TP3 / "programs/halt_suite.expected.json").read_text())}
    for name, label, words in (("branch_load_use", "branch_run", 35), ("suma", "suma_run", 9),
                               ("flush_halt", "recovery_run", 7)):
        base = TP3 / "programs" / name
        image = [int(line, 16) for line in base.with_suffix(".hex").read_text().splitlines()]
        require(assemble(base.with_suffix(".s").read_text())[:words] == image[:words], f"{name}: source/hex mismatch")
        output = frames / f"a32_iss_{name}.json"
        command = [str(iss), str(base.with_suffix(".hex")), "-o", str(output), "--full", "--max-instr", "1000"]
        print(" ".join(command), flush=True)
        subprocess.run(command, check=True)
        expected = json.loads(output.read_text())
        actual = canonical.from_dump(dumps[label])
        differences = canonical.diff(expected, actual, "iss", "uart")
        require(not differences, f"{name}: {'; '.join(differences)}")
        entry = golden[name]
        require(actual["x"] == [f"0x{int(value, 16):08x}" for value in entry["x"]], f"{name}: independent registers differ")
        require(actual["pc"] == f"0x{entry['halt_pc']:08x}", f"{name}: independent HALT PC differs")
        require(actual["mem"] == [[f"0x{int(address, 16):08x}", f"0x{int(value, 16):08x}"]
                                  for address, value in sorted(entry["mem"].items())], f"{name}: independent memory differs")
        require(dumps[label].cycles == entry["advances"], f"{name}: independent pipeline cycle count differs")
        require(dumps[label].latches[15] == 0x98, f"{name}: pipeline did not drain")
        canonical.save(actual, frames / f"a32_uart_{name}.json")
        print(f"PASS UART/ISS {name}: PC, 32 registers, memory/dirty and {dumps[label].cycles} cycles", flush=True)
    command = [str(iss), str(TP3 / "programs/no_halt.hex"), "-o", str(frames / "a32_iss_no_halt.json"),
               "--max-instr", "1000"]
    print(" ".join(command), flush=True)
    subprocess.run(command, check=True)
    require(json.loads((frames / "a32_iss_no_halt.json").read_text())["stop"] == "limit", "ISS infinite loop did not reach limit")
    print(f"PASS system dumps: {len(labels)} real UART frames, codec/checksum, STEP/D, reset, three ISS results and abort/timeout recovery")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--companion", type=Path, required=True)
    parser.add_argument("--frames", type=Path, default=TP3 / "build")
    args = parser.parse_args()
    try:
        check(args.companion, args.frames.resolve())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"FAIL system dumps: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

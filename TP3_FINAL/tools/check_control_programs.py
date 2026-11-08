import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
TP3 = Path(__file__).resolve().parents[1]
PROGRAMS = ("suma", "jump_link", "branch_load_use")
CONTROL_WORDS = {
    "suma": {20: 0xFE311CE3},
    "jump_link": {4: 0x04C000EF, 16: 0x00051663, 28: 0x00C002EF,
                  44: 0x000303E7, 72: 0x0180006F, 84: 0x00008067},
    "branch_load_use": {24: 0x00808663, 44: 0x00241663, 64: 0x02818E63,
                        80: 0x02441663, 100: 0x008303E7, 116: 0x0100006F},
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(command):
    subprocess.run([str(value) for value in command], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--companion", type=Path, required=True)
    args = parser.parse_args()
    companion = args.companion.resolve()
    sw = companion / "TP3_FINAL/sw"
    sys.path.insert(0, str(sw))
    from asm.rvasm import assemble, to_hex

    build = TP3 / "build"
    build.mkdir(exist_ok=True)
    compiler = os.environ.get("CXX", "g++")
    flags = ["-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror"]
    iss = build / "a26_iss"
    iss_test = build / "a26_test_iss"
    run([compiler, *flags, sw / "iss/iss.cpp", sw / "iss/test_iss.cpp", "-o", iss_test])
    run([iss_test])
    run([compiler, *flags, sw / "iss/iss.cpp", sw / "iss/iss_main.cpp", "-o", iss])
    for name in PROGRAMS:
        base = TP3 / "programs" / name
        words = assemble(base.with_suffix(".s").read_text())
        require(words[-1] == 0x73, f"{name}: missing assembler HALT terminator")
        code = words[:-1]
        require(to_hex(code + [0x13] * (256 - len(code))) == base.with_suffix(".hex").read_text(),
                f"{name}: assembly/hex mismatch")
        for pc, word in CONTROL_WORDS[name].items():
            require(code[pc // 4] == word, f"{name}: independent encoding mismatch at PC {pc}")
        golden = json.loads(base.with_suffix(".expected.json").read_text())
        header = [golden[field] for field in ("advances", "retired", "register_writes", "stores",
                                             "load_use_stalls", "taken", "marker_pc")]
        registers = [int(value, 16) for value in golden["x"]]
        memory = [0] * 256
        dirty = [0] * 256
        for address, value in golden["mem"].items():
            index = int(address, 16) // 4
            memory[index] = int(value, 16)
            dirty[index] = 1
        events = golden["events"]
        require(len(events) == golden["retired"], f"{name}: event count mismatch")
        require(all(len(event) == 14 for event in events), f"{name}: malformed event")
        require(events[-1][:4] == [golden["marker_pc"], 1, 31, 0x5A5], f"{name}: missing marker")
        require(sum(bool(event[1] & 1) for event in events) == golden["register_writes"],
                f"{name}: write count mismatch")
        require(sum(bool(event[1] & 2) for event in events) == golden["stores"],
                f"{name}: store count mismatch")
        require(sum(event[8] for event in events) == golden["taken"], f"{name}: redirect count mismatch")
        require(sum(event[9] for event in events) == golden["load_use_stalls"], f"{name}: stall count mismatch")
        data = header + registers + memory + dirty + [value for event in events for value in event]
        expected_hex = "".join(f"{value:08x}\n" for value in data + [0] * (1152 - len(data)))
        require(expected_hex == base.with_suffix(".expected.hex").read_text(), f"{name}: JSON/hex mismatch")
        iss_input = build / f"a26_iss_{name}.hex"
        iss_output = build / f"a26_iss_{name}.json"
        iss_input.write_text(to_hex(words))
        run([iss, iss_input, "-o", iss_output, "--full", "--max-instr", "1000"])
        result = json.loads(iss_output.read_text())
        require(result["stop"] == "halt", f"{name}: ISS did not halt")
        require(int(result["pc"], 16) == golden["marker_pc"] + 4, f"{name}: ISS final PC mismatch")
        require(result["instret"] == golden["retired"], f"{name}: ISS retired count mismatch")
        require([int(value, 16) for value in result["x"]] == registers, f"{name}: ISS register mismatch")
        require({int(address, 16): int(value, 16) for address, value in result["mem"]} ==
                {int(address, 16): int(value, 16) for address, value in golden["mem"].items()},
                f"{name}: ISS memory/dirty mismatch")
        print(f"PASS {name}: encoding, golden files and ISS state ({golden['retired']} instructions)", flush=True)
    print("PASS control programs: three independent golden states and 13 fixed control encodings")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"FAIL control programs: {error}", file=sys.stderr)
        sys.exit(1)

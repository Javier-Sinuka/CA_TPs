import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
TP3 = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(command):
    subprocess.run([str(value) for value in command], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--companion", type=Path, required=True)
    args = parser.parse_args()
    sw = args.companion.resolve() / "TP3_FINAL/sw"
    sys.path.insert(0, str(sw))
    from asm.rvasm import assemble, to_hex

    programs = TP3 / "programs"
    suite = json.loads((programs / "halt_suite.expected.json").read_text())
    build = TP3 / "build"
    build.mkdir(exist_ok=True)
    compiler = os.environ.get("CXX", "g++")
    flags = ["-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror"]
    iss = build / "a29_iss"
    test = build / "a29_test_iss"
    run([compiler, *flags, sw / "iss/iss.cpp", sw / "iss/test_iss.cpp", "-o", test])
    run([test])
    run([compiler, *flags, sw / "iss/iss.cpp", sw / "iss/iss_main.cpp", "-o", iss])
    data = []
    for golden in suite:
        name = golden["name"]
        base = programs / name
        text = base.with_suffix(".s").read_text()
        words = assemble(text)
        if name == "no_halt":
            require(words == [0x0000006F, 0x73], "no_halt: unexpected source")
            words = words[:-1]
            padding = 0x0000006F
        else:
            require(text.splitlines()[-1] == "halt", f"{name}: HALT must be explicit")
            require(words[golden["halt_pc"] // 4] == 0x73, f"{name}: HALT PC mismatch")
            padding = 0x73
            require(golden["advances"] == golden["instret"] + 4 + golden["stalls"] + 2*golden["takes"],
                    f"{name}: independent pipeline cycle count inconsistent")
        require(to_hex(words + [padding] * (256 - len(words))) == base.with_suffix(".hex").read_text(),
                f"{name}: assembly/hex mismatch")
        registers = [int(value, 16) for value in golden["x"]]
        memory = [0] * 256
        dirty = [0] * 256
        for address, value in golden["mem"].items():
            index = int(address, 16) // 4
            memory[index] = int(value, 16)
            dirty[index] = 1
        data.extend([golden[key] if golden[key] is not None else 0xFFFFFFFF for key in
                     ("halt_pc", "advances", "writes", "stores", "stalls", "takes", "instret")])
        data.extend(registers + memory + dirty + [0]*9)
        output = build / f"a29_iss_{name}.json"
        run([iss, base.with_suffix(".hex"), "-o", output, "--full", "--max-instr", "1000"])
        result = json.loads(output.read_text())
        if name == "no_halt":
            require(result["stop"] == "limit", "no_halt: ISS must reach its instruction limit")
            require(result["instret"] == 1000, "no_halt: unexpected ISS instruction limit")
        else:
            require(result["stop"] == "halt", f"{name}: ISS did not halt")
            require(int(result["pc"], 16) == golden["halt_pc"], f"{name}: ISS HALT PC mismatch")
            require(result["instret"] == golden["instret"], f"{name}: ISS instruction count mismatch")
            require([int(value, 16) for value in result["x"]] == registers, f"{name}: ISS register mismatch")
            require({int(address, 16): int(value, 16) for address, value in result["mem"]} ==
                    {int(address, 16): int(value, 16) for address, value in golden["mem"].items()},
                    f"{name}: ISS memory/dirty mismatch")
        print(f"PASS {name}: encoding, independent expectations, ISS stop={result['stop']}", flush=True)
    require("".join(f"{value:08x}\n" for value in data) == (programs / "halt_suite.expected.hex").read_text(),
            "halt suite: JSON/hex mismatch")
    print("PASS HALT programs: seven architectural states and explicit no-HALT limit")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"FAIL HALT programs: {error}", file=sys.stderr)
        sys.exit(1)

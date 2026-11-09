import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


sys.dont_write_bytecode = True
TP3 = Path(__file__).resolve().parents[1]
REPO = TP3.parent
ISA = set("add sub sll slt sltu xor srl sra or and addi slti sltiu xori ori andi slli srli srai lb lh lw lbu lhu sb sh sw beq bne jal jalr lui".split())
REQUIRED_TARGETS = set("""
tb_hazard_unit tb_forwarding_unit tb_mem_wb tb_execute_stage tb_decode_stage
tb_alu tb_alu_control tb_imm_gen tb_control tb_regfile tb_dmem tb_dmem_dirty tb_pipeline_regs
tb_system_cpu_smoke tb_cpu_contract tb_cpu_contract_stub tb_cpu_debug tb_cpu_step_halt
tb_cpu_freeze tb_halt_drain tb_control_flow tb_flush tb_branch_execute tb_load_use_consumers
tb_load_use tb_raw tb_forwarding_paths tb_cpu_no_hazard tb_fetch tb_imem tb_imem_bridge
""".split())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def check(companion: Path, regression_log: Path) -> None:
    from tbs import TBS, EXTERNAL_TBS

    companion = companion.resolve()
    sys.path.insert(0, str(companion / "TP3_FINAL/sw"))
    from asm.disasm import disasm

    registry = TBS | EXTERNAL_TBS
    require(REQUIRED_TARGETS <= registry.keys(), "required testbench removed from the registry")
    log = regression_log.read_text()
    require(not re.search(r"^FAIL|warning:|sorry:", log, re.MULTILINE | re.IGNORECASE),
            "RTL regression contains a failure or an unclassified warning")
    results = {}
    for match in re.finditer(r"^vvp -n [^\n]*/([^/\s]+)\.vvp\n(.*?)(?=^iverilog |\Z)", log,
                             re.MULTILINE | re.DOTALL):
        name, output = match.groups()
        require(name in registry and name not in results, f"unexpected or repeated target: {name}")
        top = registry[name]["top"]
        passed = re.search(rf"^PASS {re.escape(top)}: (\d+)", output, re.MULTILINE)
        require(passed is not None, f"missing PASS/count: {name}")
        seed = re.search(r"seed=([0-9a-fA-F]+)", output)
        results[name] = {"top": top, "checks": int(passed[1]), "seed": seed[1] if seed else None}
    require(set(results) == set(registry), f"target mismatch: missing={set(registry)-set(results)}")
    require(f"PASS test: {len(registry)} testbenches" in log, "missing final RTL regression PASS")

    suite = json.loads((TP3 / "programs/halt_suite.expected.json").read_text())
    golden = {entry["name"]: entry for entry in suite}
    images = {name: [int(word, 16) for word in (TP3 / f"programs/{name}.hex").read_text().splitlines()]
              for name in golden}
    counts = Counter()
    instructions = defaultdict(lambda: defaultdict(set))
    mode_instructions = defaultdict(set)
    halts = defaultdict(set)
    final = {}
    retirement = []
    previous = None
    with (TP3 / "build/a29_step_trace.csv").open() as trace:
        for row in csv.DictReader(trace):
            key = row["program"], int(row["mode"])
            require(row["program"] in golden, "unexpected traced program")
            final[key] = row
            if (previous is not None and key == (previous["program"], int(previous["mode"]))
                    and row["reset"] == "0" and row["enable"] == "1"
                    and previous["halted"] == "0" and previous["valid"][0] == "1"):
                pc = int(previous["pc_wb"], 16)
                word = images[key[0]][(pc >> 2) & 255]
                mnemonic = disasm(word).split()[0]
                if mnemonic == "nop":
                    mnemonic = "addi"
                require(mnemonic in ISA, f"unexpected retired instruction {word:08x}: {mnemonic}")
                counts[key] += 1
                instructions[mnemonic][key[0]].add(pc)
                mode_instructions[key[1]].add(mnemonic)
                retirement.append({"program": key[0], "mode": key[1], "pc": pc,
                                   "word": f"{word:08x}", "mnemonic": mnemonic})
            if row["halted"] == "1":
                require(row["valid"] == "1000", f"{key}: younger stages not drained")
                halts[key].add(int(row["pc_wb"], 16))
            previous = row
    require(set(instructions) == ISA, f"ISA coverage missing: {ISA-set(instructions)}")
    for mode in (0, 1):
        require(mode_instructions[mode] == ISA, f"mode {mode}: ISA coverage missing: {ISA-mode_instructions[mode]}")
    for name, entry in golden.items():
        for mode in (0, 1):
            key = name, mode
            require(key in final, f"missing program/mode: {key}")
            require(counts[key] == entry["instret"], f"{key}: retired count differs from independent golden")
            for column, expected in (("advance", "advances"), ("writes", "writes"), ("stores", "stores"),
                                     ("stalls", "stalls"), ("takes", "takes")):
                require(int(final[key][column]) == entry[expected], f"{key}: {column} differs")
            expected_halts = set() if entry["halt_pc"] is None else {entry["halt_pc"]}
            require(halts[key] == expected_halts, f"{key}: actual HALT PC differs")

    project = TP3 / "VIVADO/TP_FINAL/TP_FINAL.xpr"
    tree = ET.parse(project)
    for source in tree.findall(".//File"):
        path = Path(source.attrib["Path"].replace("$PPRDIR", str(project.parent)))
        require(path.is_file(), f"Vivado source missing: {path}")
    local_tb = set((TP3 / "VIVADO/TP_FINAL/tb").glob("*.sv"))
    declared_tb = {REPO / source for spec in registry.values() for source in spec["files"] if source.endswith(".sv")}
    require(local_tb <= declared_tb, f"unregistered local testbench: {local_tb-declared_tb}")

    source_paths = set()
    for spec in registry.values():
        source_paths.update(REPO / value for value in spec["files"])
        source_paths.update(companion / value for key in ("companion_files", "companion_headers")
                            for value in spec.get(key, ()))
    source_paths.update((TP3 / "programs").glob("*"))
    source_paths.update((TP3 / "tools").glob("*.py"))
    source_paths.add(TP3 / "tools/synth_ooc.tcl")
    source_paths.update((TP3 / "VIVADO/TP_FINAL/rtl").glob("*.vh"))
    source_paths.add(project)
    hashes = {str(path.resolve()): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sorted(source_paths) if path.is_file()}
    git = lambda root, *args: subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()
    report = {
        "status": "passed", "isa_covered": len(ISA), "halt_programs": len(suite)-1,
        "targets": results, "checks": sum(result["checks"] for result in results.values()),
        "program_modes": {f"{name}/{'RUN' if mode == 0 else 'STEP'}": count
                          for (name, mode), count in sorted(counts.items())},
        "instructions": {name: {program: sorted(pcs) for program, pcs in sorted(programs.items())}
                         for name, programs in sorted(instructions.items())},
        "source_sha256": hashes,
        "repository": {"commit": git(REPO, "rev-parse", "HEAD"), "branch": git(REPO, "branch", "--show-current"),
                       "status": git(REPO, "status", "--short")},
        "companion": {"commit": git(companion, "rev-parse", "HEAD"),
                      "branch": git(companion, "branch", "--show-current"),
                      "status": git(companion, "status", "--short")},
    }
    build = TP3 / "build"
    (build / "a33_coverage.json").write_text(json.dumps(report, indent=2) + "\n")
    with (build / "a33_retirement.csv").open("w") as output:
        writer = csv.DictWriter(output, fieldnames=("program", "mode", "pc", "word", "mnemonic"))
        writer.writeheader()
        writer.writerows(retirement)
    rows = ["# Cobertura dinámica final", "", "| Instrucción | Programa y PC byte observado en WB |",
            "|---|---|"]
    for name, programs in sorted(instructions.items()):
        rows.append(f"| {name} | " + "; ".join(f"{program}: {', '.join(map(str, sorted(pcs)))}"
                                               for program, pcs in sorted(programs.items())) + " |")
    (build / "a33_coverage.md").write_text("\n".join(rows) + "\n")
    print(f"PASS final coverage: {len(ISA)}/32 retired mnemonics, seven HALTs, eight programs in RUN/STEP")
    print(f"PASS manifest: {len(results)} targets, {report['checks']} checks, {len(hashes)} source hashes, fixed seeds")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--companion", type=Path, required=True)
    parser.add_argument("--regression-log", type=Path, required=True)
    args = parser.parse_args()
    try:
        check(args.companion, args.regression_log)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, ET.ParseError) as error:
        print(f"FAIL final coverage: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

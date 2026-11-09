import argparse
import re
from pathlib import Path


PORTS = (
    ("input", 1, "i_clock"),
    ("input", 1, "i_reset"),
    ("input", 1, "i_en"),
    ("output", 1, "o_halted"),
    ("output", 32, "o_imem_addr"),
    ("input", 32, "i_imem_data"),
    ("input", 5, "i_dbg_reg_addr"),
    ("output", 32, "o_dbg_reg_data"),
    ("input", 4, "i_dbg_latch_sel"),
    ("output", 32, "o_dbg_latch_word"),
    ("input", 8, "i_dbg_mem_addr"),
    ("output", 32, "o_dbg_mem_data"),
    ("output", 1, "o_dbg_mem_dirty"),
    ("output", 32, "o_dbg_pc"),
)


def normalized(text: str) -> str:
    text = re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"\s+", "", text)


def check(companion: Path) -> None:
    project = Path(__file__).resolve().parents[1]
    external = companion.resolve() / "TP3_FINAL"
    rtl = "VIVADO/TP_FINAL/rtl"
    header = (external / rtl / "debug/cpu_ports.vh").read_text()
    declarations = []
    for direction, high, low, name in re.findall(
        r"\b(input|output)\s+wire\s*(?:\[(\d+):(\d+)\]\s*)?(\w+)", header
    ):
        width = int(high) - int(low) + 1 if high else 1
        declarations.append((direction, width, name))
    if tuple(declarations) != PORTS:
        raise ValueError(f"public port declarations differ: {declarations}")
    expected = ",".join(
        f"{direction}wire{f'[{width-1}:0]' if width != 1 else ''}{name}"
        for direction, width, name in PORTS
    )
    if normalized(header) != expected:
        raise ValueError("unexpected header content, guards or trailing comma")
    document = (external / "doc/documentation/interfaz_cpu.md").read_text()
    section = document.split("Contenido exacto de `cpu_ports.vh`", 1)[1]
    documented = section.split("```verilog", 1)[1].split("```", 1)[0]
    if normalized(header) != normalized(documented):
        raise ValueError("cpu_ports.vh differs from the documented declaration")
    for module, path in (
        ("cpu", project / rtl / "cpu.v"),
        ("cpu_stub", external / rtl / "debug/cpu_stub.v"),
    ):
        source = path.read_text()
        match = re.search(
            rf"\bmodule\s+{module}\s*(?:#\(.*?\)\s*)?\((.*?)\);",
            source, re.DOTALL,
        )
        if match is None or normalized(match[1]) != '`include"cpu_ports.vh"':
            raise ValueError(f"{module} does not use the shared header exclusively")
    system = (external / rtl / "debug/system.v").read_text()
    connections = re.findall(r"\bu_cpu\s*\((.*?)\);", system, re.DOTALL)
    if len(connections) != 2:
        raise ValueError("system must have two CPU selections named u_cpu")
    mappings = [dict(re.findall(r"\.(\w+)\s*\((\w+)\)", text)) for text in connections]
    if mappings[0] != mappings[1] or set(mappings[0]) != {p[2] for p in PORTS}:
        raise ValueError("CPU/stub wiring differs in the companion system")
    for direction, width, name in PORTS:
        print(f"{name}: {direction}, {width} bit(s)")
    print("PASS cpu_contract: 14 ports, document, shared includes and identical system wiring")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--companion", type=Path, required=True)
    args = parser.parse_args()
    try:
        check(args.companion)
    except (OSError, ValueError, IndexError) as error:
        print(f"FAIL cpu_contract: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

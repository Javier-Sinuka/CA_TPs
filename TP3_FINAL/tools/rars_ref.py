"""Referencia RARS 1.6 (B-19 §F y B-21 §6).

Uso:
    py TP3_FINAL/tools/rars_ref.py encode <prog.s> -o <out.hex>   # .text en hex
    py TP3_FINAL/tools/rars_ref.py regs   <prog.s> -o <out.json>  # registros finales
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parents[1]
BUILD = REPO / "TP3_FINAL" / "build"
JAR = TOOLS / "rars1_6.jar"

_LABELS = re.compile(r"^\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)*")
_HALT = re.compile(r"\bhalt\b", re.IGNORECASE)
_IGNORE = re.compile(r"^\s*#\s*rars-ignore:\s*(.*)$", re.MULTILINE)
_REG_LINE = re.compile(r"^(x\d+)\s+(0x[0-9a-fA-F]{8})", re.MULTILINE)


def prepare(src: str) -> str:
    """halt -> ecall; agrega ecall al final si la última instrucción no es halt/ecall."""
    out: list[str] = []
    last = ""
    for line in src.splitlines():
        code, sep, comment = line.partition("#")
        code = _HALT.sub("ecall", code)
        out.append(code + sep + comment)
        body = code[_LABELS.match(code).end():].strip()
        if body:
            last = body.split()[0].lower()
    if last != "ecall":
        out.append("ecall")
    return "\n".join(out) + "\n"


def encode(src: Path, out: Path) -> int:
    if not JAR.exists():
        print("falta TP3_FINAL/tools/rars1_6.jar (ver B-19)")
        return 2
    work = BUILD / "rars"
    work.mkdir(parents=True, exist_ok=True)
    prepared = work / f"{src.stem}.s"
    prepared.write_text(prepare(src.read_text(encoding="utf-8-sig")), encoding="utf-8")
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = ["java", "-jar", str(JAR), "a", "mc", "CompactTextAtZero",
           "dump", ".text", "HexText", str(out.resolve()), str(prepared)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.stdout.write(res.stdout)
        sys.stderr.write(res.stderr)
    return res.returncode


def prepare_regs(src: str) -> str:
    """halt -> j __rars_end; agrega la etiqueta __rars_end: al final (RARS termina al caer del final)."""
    out: list[str] = []
    for line in src.splitlines():
        code, sep, comment = line.partition("#")
        code = _HALT.sub("j __rars_end", code)
        out.append(code + sep + comment)
    out.append("__rars_end:")
    return "\n".join(out) + "\n"


def regs(src: Path, out: Path) -> int:
    if not JAR.exists():
        print("falta TP3_FINAL/tools/rars1_6.jar (ver B-19)")
        return 2
    text = src.read_text(encoding="utf-8-sig")
    ignore: list[str] = []
    for m in _IGNORE.finditer(text):
        ignore += [r.strip() for r in m.group(1).split(",") if r.strip()]
    work = BUILD / "rars"
    work.mkdir(parents=True, exist_ok=True)
    prepared = work / f"{src.stem}_regs.s"
    prepared.write_text(prepare_regs(text), encoding="utf-8")
    cmd = ["java", "-jar", str(JAR), "nc", "mc", "CompactDataAtZero",
           *[f"x{i}" for i in range(1, 32)], str(prepared)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    found = {m.group(1): m.group(2).lower() for m in _REG_LINE.finditer(res.stdout)}
    if res.returncode != 0 or len(found) != 31:
        sys.stdout.write(res.stdout)
        sys.stderr.write(res.stderr)
        print(f"rars_ref regs: RARS no terminó limpio ({len(found)} registros leídos)")
        return 2
    if "terminated due to errors" in res.stdout + res.stderr:
        # p. ej. lw desalineado: RARS lo trata como excepción (el ISS, D-18, no); el programa debe
        # listar en `# rars-ignore:` los registros afectados.
        extra = [l for l in (res.stdout + res.stderr).splitlines() if not _REG_LINE.match(l)]
        sys.stderr.write("\n".join(extra) + "\n")
        sys.stderr.write("rars_ref regs: aviso: RARS terminó con errores de ejecución\n")
    data: dict[str, list[str]] = {"x": ["0x00000000"] + [found[f"x{i}"] for i in range(1, 32)]}
    if ignore:
        data["ignore"] = ignore
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="rars_ref.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("encode", "regs"):
        p = sub.add_parser(name)
        p.add_argument("source", type=Path)
        p.add_argument("-o", dest="out", type=Path, required=True)
    a = ap.parse_args(argv)
    if a.cmd == "regs":
        return regs(a.source, a.out)
    return encode(a.source, a.out)


if __name__ == "__main__":
    sys.exit(main())

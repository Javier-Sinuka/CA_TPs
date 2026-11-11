import json
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

from host import canonical
from host.dump import DumpError, decode, encode


TP3 = Path(__file__).resolve().parents[2]
REPO = TP3.parent
BUILD = TP3 / "build"
LABELS = ["branch_reset", "branch_run", "branch_halted_dump", "branch_halted_step",
          "branch_halted_run", "after_x", "branch_rerun", "suma_run", "abort_run",
          "abort_dump", "timeout_run", "timeout_again", "step_after_timeout", "recovery_run"]
LABELS += [f"{prefix}_{index}" for prefix in ("step", "paused") for index in range(1, 11)]


@pytest.fixture(scope="module")
def recordings():
    if not shutil.which("iverilog") or not shutil.which("vvp"):
        pytest.skip("Icarus Verilog is required for real UART recordings")
    sys.path.insert(0, str(TP3 / "tools"))
    from tbs import TBS

    spec = TBS["tb_system_cpu_smoke"]
    dependencies = [REPO / path for path in spec["files"]]
    dependencies += list((TP3 / "programs/cpu").glob("*.hex"))
    dependencies += list((TP3 / "VIVADO/TP_FINAL/rtl").rglob("*.vh"))
    dependencies.append(TP3 / "VIVADO/TP_FINAL/tb/common/uart_bfm.svh")
    dependencies.append(TP3 / "tools/tbs.py")
    newest = max(path.stat().st_mtime for path in dependencies)
    frames = {label: BUILD / f"a32_{label}.dump.hex" for label in LABELS}
    log = BUILD / "tb_system_cpu_smoke.log"
    ready = (log.is_file() and log.stat().st_mtime >= newest
             and "PASS tb_system_cpu_smoke:" in log.read_text()
             and not any(line.startswith("FAIL") for line in log.read_text().splitlines())
             and all(path.is_file() and path.stat().st_mtime >= newest for path in frames.values()))
    if not ready:
        subprocess.run([sys.executable, str(TP3 / "tools/run.py"), "tb", "tb_system_cpu_smoke"],
                       cwd=REPO, check=True, capture_output=True, text=True)
    return {label: bytes(int(word, 16) for word in path.read_text().split())
            for label, path in frames.items()}


@pytest.mark.parametrize("label", LABELS)
def test_real_uart_codec_and_corrupted_checksum(recordings, label):
    raw = recordings[label]
    dump = decode(raw)
    assert len(dump.x) == 32 and len(dump.latches) == 16
    assert len(raw) == 210 + 8 * len(dump.mem)
    assert encode(dump) == raw
    corrupted = raw[:-1] + bytes([raw[-1] ^ 1])
    with pytest.raises(DumpError):
        decode(corrupted)


@pytest.mark.parametrize("label,program", [("branch_run", "branch_load_use"),
                                          ("suma_run", "suma"),
                                          ("recovery_run", "flush_halt")])
def test_final_uart_state_matches_independent_golden_and_iss(recordings, iss_exe, tmp_path, label, program):
    dump = decode(recordings[label])
    suite = json.loads((TP3 / "programs/cpu/halt_suite.expected.json").read_text())
    golden = next(entry for entry in suite if entry["name"] == program)
    expected = {
        "stop": "halt", "pc": canonical.hex32(golden["halt_pc"]),
        "x": [canonical.hex32(int(word, 16)) for word in golden["x"]],
        "mem": [[canonical.hex32(int(address, 16)), canonical.hex32(int(word, 16))]
                for address, word in sorted(golden["mem"].items())],
    }
    assert dump.halted and not dump.timeout and not dump.aborted
    assert dump.cycles == golden["advances"]
    assert dump.latches[15] == 0x98
    assert canonical.from_dump(dump) == expected
    output = tmp_path / "iss.json"
    subprocess.run([str(iss_exe), str(TP3 / f"programs/cpu/{program}.hex"), "-o", str(output)],
                   check=True, capture_output=True, text=True)
    assert canonical.load(output) == expected


@pytest.mark.parametrize("index", range(1, 11))
def test_step_and_paused_dump_match_exactly(recordings, index):
    assert recordings[f"step_{index}"] == recordings[f"paused_{index}"]
    dump = decode(recordings[f"step_{index}"])
    assert dump.cycles == index
    assert not dump.halted and not dump.timeout and not dump.aborted
    if index == 7:
        assert dump.latches[15] & 0x20
    if index == 9:
        assert dump.latches[15] & 0x40


def test_reset_and_halted_commands_preserve_state(recordings):
    for label in ("branch_reset", "after_x"):
        dump = decode(recordings[label])
        assert dump.cycles == dump.pc == 0
        assert not any(dump.x) and not any(dump.latches) and not dump.mem
    for label in ("branch_halted_dump", "branch_halted_step", "branch_halted_run", "branch_rerun"):
        assert recordings[label] == recordings["branch_run"]


def test_abort_timeout_and_recovery_have_explicit_partial_state(recordings):
    for label in ("abort_run", "abort_dump", "timeout_run", "timeout_again", "step_after_timeout"):
        dump = decode(recordings[label])
        assert not dump.halted and not any(dump.x) and not dump.mem
    aborted = decode(recordings["abort_run"])
    assert aborted.aborted and not aborted.timeout and 0 < aborted.cycles < 1000
    assert recordings["abort_dump"] == recordings["abort_run"]
    for label, count in (("timeout_run", 1000), ("timeout_again", 2000)):
        dump = decode(recordings[label])
        assert dump.timeout and not dump.aborted and dump.cycles == count
    step = decode(recordings["step_after_timeout"])
    assert step.cycles == 2001 and not step.timeout and not step.aborted
    assert decode(recordings["recovery_run"]).halted


def test_five_steps_move_each_instruction_one_stage(recordings):
    # branch_load_use no tiene riesgos en sus primeras 6 instrucciones: cada S corre toda una etapa.
    words = [int(w, 16) for w in (TP3 / "programs/cpu/branch_load_use.hex").read_text().split()]
    stages = ((0, 0), (2, 1), (7, 2), (11, 3))   # (latch con el PC de la etapa, bit de validez en latch 15)
    for k in range(1, 6):
        dump = decode(recordings[f"step_{k}"])
        assert dump.pc == 4 * k, k # IF ya apunta a la siguiente
        assert dump.latches[1] == words[k - 1], k # instr_id = la que entró en este paso
        for depth, (sel, valid_bit) in enumerate(stages):
            pc = 4 * (k - 1 - depth)
            if pc >= 0:
                assert dump.latches[15] >> valid_bit & 1, (k, depth)
                assert dump.latches[sel] == pc, (k, depth)

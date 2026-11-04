"""Explicit Phase 1 source and testbench inventory (A-01).

TBS paths are relative to the repository root (Practico/TPs).
"""

RTL = "VIVADO/TP_FINAL/rtl"
TB = "VIVADO/TP_FINAL/tb"

PHASE1_TOPS = {
    "alu": (f"{RTL}/alu.v",),
    "alu_control": (f"{RTL}/alu_control.v",),
    "imm_gen": (f"{RTL}/imm_gen.v",),
    "control": (f"{RTL}/alu_control.v", f"{RTL}/control.v"),
}

TBS = {
    "tb_alu": {"top": "tb_alu", "files": (f"TP3_FINAL/{RTL}/alu.v", f"TP3_FINAL/{TB}/tb_alu.sv")},
    "tb_alu_control": {"top": "tb_alu_control", "files": (f"TP3_FINAL/{RTL}/alu.v", f"TP3_FINAL/{RTL}/alu_control.v", f"TP3_FINAL/{RTL}/control.v", f"TP3_FINAL/{TB}/tb_alu_control.sv")},
    "tb_imm_gen": {"top": "tb_imm_gen", "files": (f"TP3_FINAL/{RTL}/imm_gen.v", f"TP3_FINAL/{TB}/tb_imm_gen.sv")},
    "tb_control": {"top": "tb_control", "files": (f"TP3_FINAL/{RTL}/alu_control.v", f"TP3_FINAL/{RTL}/control.v", f"TP3_FINAL/{RTL}/imm_gen.v", f"TP3_FINAL/{TB}/tb_control.sv")},
    "tb_regfile": {"top": "tb_regfile", "files": (f"TP3_FINAL/{RTL}/regfile.v", f"TP3_FINAL/{TB}/tb_regfile.sv")},
    "tb_dmem": {"top": "tb_dmem", "files": (f"TP3_FINAL/{RTL}/dmem.v", f"TP3_FINAL/{TB}/tb_dmem.sv")},
    "tb_dmem_dirty": {"top": "tb_dmem_dirty", "files": (f"TP3_FINAL/{RTL}/dmem.v", f"TP3_FINAL/{TB}/tb_dmem_dirty.sv")},
}

EXTERNAL_TBS = {
    "tb_imem": {
        "top": "tb_imem",
        "files": (),
        "companion_files": (
            f"TP3_FINAL/{RTL}/debug/imem.v",
            f"TP3_FINAL/{TB}/debug/tb_imem.sv",
        ),
    },
    "tb_imem_bridge": {
        "top": "tb_imem_bridge",
        "files": (f"TP3_FINAL/{TB}/tb_imem_bridge.sv",),
        "companion_files": (
            f"TP3_FINAL/{RTL}/debug/imem.v",
            f"TP3_FINAL/{RTL}/debug/cpu_stub.v",
        ),
    },
}

SYNTH = {
    "regfile": (f"TP3_FINAL/{RTL}/regfile.v",),
    "dmem": (f"TP3_FINAL/{RTL}/dmem.v",),
    "imem": (f"TP3_FINAL/{RTL}/debug/imem.v",),
}

EXTERNAL_SYNTH = {"imem"}

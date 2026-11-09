"""Explicit Phase 1 source and testbench inventory (A-01).

TBS paths are relative to the repository root (Practico/TPs).
"""

RTL = "VIVADO/TP_FINAL/rtl"
TB = "VIVADO/TP_FINAL/tb"

DECODE_FILES = tuple(f"TP3_FINAL/{RTL}/{name}.v" for name in (
    "alu_control", "control", "imm_gen", "regfile", "id_ex", "decode_stage",
))

EXECUTE_FILES = tuple(f"TP3_FINAL/{RTL}/{name}.v" for name in (
    "alu", "ex_mem", "execute_stage",
))

MEMORY_FILES = tuple(f"TP3_FINAL/{RTL}/{name}.v" for name in (
    "dmem", "mem_wb", "memory_stage",
))

PHASE1_TOPS = {
    "alu": (f"{RTL}/alu.v",),
    "alu_control": (f"{RTL}/alu_control.v",),
    "imm_gen": (f"{RTL}/imm_gen.v",),
    "control": (f"{RTL}/alu_control.v", f"{RTL}/control.v"),
}

TBS = {
    "tb_hazard_unit": {
        "top": "tb_hazard_unit",
        "files": (f"TP3_FINAL/{RTL}/hazard_unit.v", f"TP3_FINAL/{RTL}/alu_control.v",
                  f"TP3_FINAL/{RTL}/control.v", f"TP3_FINAL/{TB}/tb_hazard_unit.sv"),
    },
    "tb_forwarding_unit": {
        "top": "tb_forwarding_unit",
        "files": (f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{TB}/tb_forwarding_unit.sv"),
    },
    "tb_mem_wb": {
        "top": "tb_mem_wb",
        "files": (*MEMORY_FILES, f"TP3_FINAL/{RTL}/regfile.v", f"TP3_FINAL/{TB}/tb_mem_wb.sv"),
    },
    "tb_execute_stage": {
        "top": "tb_execute_stage",
        "files": (*EXECUTE_FILES, f"TP3_FINAL/{TB}/tb_execute_stage.sv"),
    },
    "tb_decode_stage": {
        "top": "tb_decode_stage",
        "files": (*DECODE_FILES, f"TP3_FINAL/{TB}/tb_decode_stage.sv"),
    },
    "tb_alu": {"top": "tb_alu", "files": (f"TP3_FINAL/{RTL}/alu.v", f"TP3_FINAL/{TB}/tb_alu.sv")},
    "tb_alu_control": {"top": "tb_alu_control", "files": (f"TP3_FINAL/{RTL}/alu.v", f"TP3_FINAL/{RTL}/alu_control.v", f"TP3_FINAL/{RTL}/control.v", f"TP3_FINAL/{TB}/tb_alu_control.sv")},
    "tb_imm_gen": {"top": "tb_imm_gen", "files": (f"TP3_FINAL/{RTL}/imm_gen.v", f"TP3_FINAL/{TB}/tb_imm_gen.sv")},
    "tb_control": {"top": "tb_control", "files": (f"TP3_FINAL/{RTL}/alu_control.v", f"TP3_FINAL/{RTL}/control.v", f"TP3_FINAL/{RTL}/imm_gen.v", f"TP3_FINAL/{TB}/tb_control.sv")},
    "tb_regfile": {"top": "tb_regfile", "files": (f"TP3_FINAL/{RTL}/regfile.v", f"TP3_FINAL/{TB}/tb_regfile.sv")},
    "tb_dmem": {"top": "tb_dmem", "files": (f"TP3_FINAL/{RTL}/dmem.v", f"TP3_FINAL/{TB}/tb_dmem.sv")},
    "tb_dmem_dirty": {"top": "tb_dmem_dirty", "files": (f"TP3_FINAL/{RTL}/dmem.v", f"TP3_FINAL/{TB}/tb_dmem_dirty.sv")},
    "tb_pipeline_regs": {
        "top": "tb_pipeline_regs",
        "files": (
            f"TP3_FINAL/{RTL}/if_id.v",
            f"TP3_FINAL/{RTL}/id_ex.v",
            f"TP3_FINAL/{RTL}/ex_mem.v",
            f"TP3_FINAL/{RTL}/mem_wb.v",
            f"TP3_FINAL/{TB}/tb_pipeline_regs.sv",
        ),
    },
}

EXTERNAL_TBS = {
    "tb_cpu_contract": {
        "top": "tb_cpu_contract",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_cpu_contract.sv",
        ),
        "companion_files": (f"TP3_FINAL/{RTL}/debug/imem.v",),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_cpu_contract_stub": {
        "top": "tb_cpu_contract",
        "files": (f"TP3_FINAL/{TB}/tb_cpu_contract.sv",),
        "companion_files": (
            f"TP3_FINAL/{RTL}/debug/cpu_stub.v",
            f"TP3_FINAL/{RTL}/debug/imem.v",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
        "defines": {"CPU_STUB": 1},
    },
    "tb_cpu_debug": {
        "top": "tb_cpu_debug",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_cpu_debug.sv",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_cpu_step_halt": {
        "top": "tb_cpu_step_halt",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_cpu_step_halt.sv",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_cpu_freeze": {
        "top": "tb_cpu_freeze",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_cpu_freeze.sv",
        ),
        "companion_files": (f"TP3_FINAL/{RTL}/debug/imem.v",),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_halt_drain": {
        "top": "tb_halt_drain",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_halt_drain.sv",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_control_flow": {
        "top": "tb_control_flow",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_control_flow.sv",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_flush": {
        "top": "tb_flush",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_flush.sv",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_branch_execute": {
        "top": "tb_branch_execute",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_branch_execute.sv",
        ),
        "companion_files": (f"TP3_FINAL/{RTL}/debug/imem.v",),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_load_use_consumers": {
        "top": "tb_load_use_consumers",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_load_use_consumers.sv",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_load_use": {
        "top": "tb_load_use",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v",
            f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_load_use.sv",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_raw": {
        "top": "tb_raw",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v", f"TP3_FINAL/{RTL}/forwarding_unit.v",
            f"TP3_FINAL/{RTL}/if_id.v", *DECODE_FILES, *EXECUTE_FILES,
            *MEMORY_FILES, f"TP3_FINAL/{TB}/tb_raw.sv",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_forwarding_paths": {
        "top": "tb_forwarding_paths",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v", f"TP3_FINAL/{RTL}/forwarding_unit.v",
            f"TP3_FINAL/{RTL}/if_id.v", *DECODE_FILES, *EXECUTE_FILES,
            *MEMORY_FILES, f"TP3_FINAL/{TB}/tb_forwarding_paths.sv",
        ),
        "companion_headers": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
    },
    "tb_cpu_no_hazard": {
        "top": "tb_cpu_no_hazard",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v", f"TP3_FINAL/{RTL}/forwarding_unit.v",
            f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_cpu_no_hazard.sv",
        ),
        "companion_files": (f"TP3_FINAL/{RTL}/debug/imem.v",),
    },
    "tb_fetch": {
        "top": "tb_fetch",
        "files": (
            f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v", f"TP3_FINAL/{RTL}/forwarding_unit.v",
            f"TP3_FINAL/{RTL}/if_id.v",
            *DECODE_FILES,
            *EXECUTE_FILES,
            *MEMORY_FILES,
            f"TP3_FINAL/{TB}/tb_fetch.sv",
        ),
        "companion_files": (f"TP3_FINAL/{RTL}/debug/imem.v",),
    },
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
    "hazard_unit": (f"TP3_FINAL/{RTL}/hazard_unit.v",),
    "forwarding_unit": (f"TP3_FINAL/{RTL}/forwarding_unit.v",),
    "cpu": (f"TP3_FINAL/{RTL}/cpu.v", f"TP3_FINAL/{RTL}/hazard_unit.v", f"TP3_FINAL/{RTL}/forwarding_unit.v", f"TP3_FINAL/{RTL}/if_id.v", *DECODE_FILES, *EXECUTE_FILES, *MEMORY_FILES),
    "memory_stage": MEMORY_FILES,
    "execute_stage": EXECUTE_FILES,
    "decode_stage": DECODE_FILES,
    "if_id": (f"TP3_FINAL/{RTL}/if_id.v",),
    "id_ex": (f"TP3_FINAL/{RTL}/id_ex.v",),
    "ex_mem": (f"TP3_FINAL/{RTL}/ex_mem.v",),
    "mem_wb": (f"TP3_FINAL/{RTL}/mem_wb.v",),
    "regfile": (f"TP3_FINAL/{RTL}/regfile.v",),
    "dmem": (f"TP3_FINAL/{RTL}/dmem.v",),
    "imem": (f"TP3_FINAL/{RTL}/debug/imem.v",),
}

EXTERNAL_SYNTH = {"imem"}

SYNTH_COMPANION_HEADERS = {
    "cpu": (f"TP3_FINAL/{RTL}/debug/cpu_ports.vh",),
}

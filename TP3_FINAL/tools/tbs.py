"""Tablas del runner (convenciones.md §3). Rutas relativas a la raíz del repo."""
RTL = "TP3_FINAL/VIVADO/TP_FINAL/rtl"
TB = "TP3_FINAL/VIVADO/TP_FINAL/tb"

UART_RTL = [f"{RTL}/uart/baud_gen.v", f"{RTL}/uart/uart_rx.v",
            f"{RTL}/uart/uart_tx.v", f"{RTL}/uart/uart_if.v"]

# Todo lo de `system` menos el CPU. Con CPU_STUB se le suma cpu_stub.v; con el CPU real, CPU_FILES.
SYSTEM_FILES = UART_RTL + [f"{RTL}/debug/debug_unit.v", f"{RTL}/debug/imem.v",
                           f"{RTL}/debug/system.v"]
DEBUG_FILES_BASE = SYSTEM_FILES + [f"{RTL}/debug/cpu_stub.v"]
DEBUG_FILES = DEBUG_FILES_BASE + [f"{TB}/debug/tb_debug_unit.sv"]

# Fase 10: A agrega acá los archivos del CPU (cpu.v y submódulos); con eso se habilita
# tb_system_prog (system con el CPU real, sin CPU_STUB) y se suman al bitstream de top_debug.
DATAPATH_FILES = [
    f"{RTL}/cpu/cpu.v",
    f"{RTL}/cpu/hazards/hazard_unit.v",
    f"{RTL}/cpu/hazards/forwarding_unit.v",
    f"{RTL}/cpu/registers/if_id.v",
    f"{RTL}/cpu/decode/alu_control.v",
    f"{RTL}/cpu/decode/control.v",
    f"{RTL}/cpu/decode/imm_gen.v",
    f"{RTL}/cpu/registers/regfile.v",
    f"{RTL}/cpu/registers/id_ex.v",
    f"{RTL}/cpu/decode/decode_stage.v",
    f"{RTL}/cpu/execute/alu.v",
    f"{RTL}/cpu/registers/ex_mem.v",
    f"{RTL}/cpu/execute/execute_stage.v",
    f"{RTL}/cpu/memory/dmem.v",
    f"{RTL}/cpu/registers/mem_wb.v",
    f"{RTL}/cpu/memory/memory_stage.v",
]

CPU_FILES = DATAPATH_FILES
CPU_INCDIRS = [f"{RTL}/common", f"{RTL}/debug"]

# Claves de cada entrada: "top", "files"; opcionales "incdirs" (lista de directorios para -I,
# por ejemplo f"{TB}/common" para `include "uart_bfm.svh"), "defines", "params", "legacy".
# "legacy": TB heredado de TP2 que termina con $finish aunque falle. Pasa si vvp
# devuelve 0 y no hay líneas que empiecen con FAIL ni contengan TIMEOUT.
# B-04 convierte esos TB y borra la marca.
TBS = {
    "tb_baud_gen": {"top": "tb_baud_gen",
                    "files": [f"{RTL}/uart/baud_gen.v", f"{TB}/uart/tb_baud_gen.sv"]},
    "tb_uart_rx": {"top": "tb_uart_rx",
                   "files": [f"{RTL}/uart/uart_rx.v", f"{TB}/uart/tb_uart_rx.sv"]},
    "tb_uart_tx": {"top": "tb_uart_tx",
                   "files": [f"{RTL}/uart/uart_tx.v", f"{TB}/uart/tb_uart_tx.sv"]},
    "tb_uart": {"top": "tb_uart", "files": UART_RTL + [f"{TB}/uart/tb_uart.sv"],
                "incdirs": [f"{TB}/common"]},
    "tb_uart_fast32": {"top": "tb_uart", "files": UART_RTL + [f"{TB}/uart/tb_uart.sv"],
                       "incdirs": [f"{TB}/common"], "params": {"BAUD_RATE": 1_562_500}},
    "tb_uart_fast128": {"top": "tb_uart", "files": UART_RTL + [f"{TB}/uart/tb_uart.sv"],
                        "incdirs": [f"{TB}/common"], "params": {"BAUD_RATE": 390_625}},
    "tb_uart_echo": {"top": "tb_uart_echo",
                     "files": UART_RTL + [f"{RTL}/top/top_uart_echo.v", f"{TB}/top/tb_uart_echo.sv"],
                     "incdirs": [f"{TB}/common"]},
    "tb_cpu_stub": {"top": "tb_cpu_stub",
                    "files": [f"{RTL}/debug/cpu_stub.v", f"{TB}/debug/tb_cpu_stub.sv"]},
    "tb_imem": {"top": "tb_imem",
                "files": [f"{RTL}/debug/imem.v", f"{TB}/debug/tb_imem.sv"]},
    "tb_debug_unit_h20": {"top": "tb_debug_unit", "files": DEBUG_FILES,
                          "incdirs": [f"{TB}/common"], "defines": {"CPU_STUB": "1"},
                          "params": {"HALT_AT": 20}},
    "tb_debug_unit_h0": {"top": "tb_debug_unit", "files": DEBUG_FILES,
                         "incdirs": [f"{TB}/common"], "defines": {"CPU_STUB": "1"},
                         "params": {"HALT_AT": 0}},
    "tb_system_debug": {"top": "tb_system_debug",
                        "files": DEBUG_FILES_BASE + [f"{TB}/debug/tb_system_debug.sv"],
                        "incdirs": [f"{TB}/common"], "defines": {"CPU_STUB": "1"}},
    "tb_system_prog_stub": {"top": "tb_system_prog",
                            "files": SYSTEM_FILES + [f"{RTL}/debug/cpu_stub.v",
                                                     f"{TB}/system/tb_system_prog.sv"],
                            "incdirs": [f"{TB}/common"], "defines": {"CPU_STUB": "1"}},
}

if CPU_FILES:
    TBS["tb_system_prog"] = {"top": "tb_system_prog",
                             "files": SYSTEM_FILES + CPU_FILES + [f"{TB}/system/tb_system_prog.sv"],
                             "incdirs": [*CPU_INCDIRS, f"{TB}/common"], "defines": {}}

# Síntesis out-of-context: top -> archivos.
SYNTH = {
    "baud_gen": [f"{RTL}/uart/baud_gen.v"],
    "uart_rx": [f"{RTL}/uart/uart_rx.v"],
    "uart_tx": [f"{RTL}/uart/uart_tx.v"],
    "uart_if": [f"{RTL}/uart/baud_gen.v", f"{RTL}/uart/uart_rx.v",
                f"{RTL}/uart/uart_tx.v", f"{RTL}/uart/uart_if.v"],
    "cpu_stub": [f"{RTL}/debug/cpu_stub.v"],
    "debug_unit": [f"{RTL}/debug/debug_unit.v"],
    "imem": [f"{RTL}/debug/imem.v"],
}

# Cada mutación copia el archivo a build/mut/<name>/, reemplaza "old" (que tiene que aparecer
# exactamente una vez) por "new", y corre el TB esperando que FALLE.
MUTATIONS = [
    {"name": "tx_orden_bits", "file": f"{RTL}/uart/uart_tx.v", "tb": "tb_uart",
     "old": "r_shift <= r_shift >> 1;", "new": "r_shift <= r_shift << 1;"},
    {"name": "rx_muestreo_tarde", "file": f"{RTL}/uart/uart_rx.v", "tb": "tb_uart",
     "old": "localparam SAMPLE    = 4'd7;", "new": "localparam SAMPLE    = 4'd14;"},
]

# Bitstreams: top -> archivos y XDC. --clk mmcm agrega CLK_GEN.
CLK_GEN = f"{RTL}/top/clk_gen.v"
BITS = {
    "top_uart_echo": {"files": UART_RTL + [f"{RTL}/top/top_uart_echo.v"],
                      "xdc": "TP3_FINAL/constraints/basys3_uart_echo.xdc"},
    # El define CPU_STUB se pasa siempre por --define: no va acá (el CPU real usa el mismo top).
    "top_debug": {"files": DEBUG_FILES_BASE + CPU_FILES + [f"{RTL}/top/top_debug.v"],
                  "xdc": "TP3_FINAL/constraints/basys3_debug.xdc"},
}




TBS.update({
    'tb_hazard_unit': {
        "top": 'tb_hazard_unit',
        "files": [f"{RTL}/cpu/hazards/hazard_unit.v", f"{RTL}/cpu/decode/alu_control.v", f"{RTL}/cpu/decode/control.v", f"{TB}/cpu/unit/tb_hazard_unit.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_forwarding_unit': {
        "top": 'tb_forwarding_unit',
        "files": [f"{RTL}/cpu/hazards/forwarding_unit.v", f"{TB}/cpu/unit/tb_forwarding_unit.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_mem_wb': {
        "top": 'tb_mem_wb',
        "files": [f"{RTL}/cpu/memory/dmem.v", f"{RTL}/cpu/registers/mem_wb.v", f"{RTL}/cpu/memory/memory_stage.v", f"{RTL}/cpu/registers/regfile.v", f"{TB}/cpu/unit/tb_mem_wb.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_execute_stage': {
        "top": 'tb_execute_stage',
        "files": [f"{RTL}/cpu/execute/alu.v", f"{RTL}/cpu/registers/ex_mem.v", f"{RTL}/cpu/execute/execute_stage.v", f"{TB}/cpu/unit/tb_execute_stage.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_decode_stage': {
        "top": 'tb_decode_stage',
        "files": [f"{RTL}/cpu/decode/alu_control.v", f"{RTL}/cpu/decode/control.v", f"{RTL}/cpu/decode/imm_gen.v", f"{RTL}/cpu/registers/regfile.v", f"{RTL}/cpu/registers/id_ex.v", f"{RTL}/cpu/decode/decode_stage.v", f"{TB}/cpu/unit/tb_decode_stage.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_alu': {
        "top": 'tb_alu',
        "files": [f"{RTL}/cpu/execute/alu.v", f"{TB}/cpu/unit/tb_alu.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_alu_control': {
        "top": 'tb_alu_control',
        "files": [f"{RTL}/cpu/execute/alu.v", f"{RTL}/cpu/decode/alu_control.v", f"{RTL}/cpu/decode/control.v", f"{TB}/cpu/unit/tb_alu_control.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_imm_gen': {
        "top": 'tb_imm_gen',
        "files": [f"{RTL}/cpu/decode/imm_gen.v", f"{TB}/cpu/unit/tb_imm_gen.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_control': {
        "top": 'tb_control',
        "files": [f"{RTL}/cpu/decode/alu_control.v", f"{RTL}/cpu/decode/control.v", f"{RTL}/cpu/decode/imm_gen.v", f"{TB}/cpu/unit/tb_control.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_regfile': {
        "top": 'tb_regfile',
        "files": [f"{RTL}/cpu/registers/regfile.v", f"{TB}/cpu/unit/tb_regfile.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_dmem': {
        "top": 'tb_dmem',
        "files": [f"{RTL}/cpu/memory/dmem.v", f"{TB}/cpu/unit/tb_dmem.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_dmem_dirty': {
        "top": 'tb_dmem_dirty',
        "files": [f"{RTL}/cpu/memory/dmem.v", f"{TB}/cpu/unit/tb_dmem_dirty.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_pipeline_regs': {
        "top": 'tb_pipeline_regs',
        "files": [f"{RTL}/cpu/registers/if_id.v", f"{RTL}/cpu/registers/id_ex.v", f"{RTL}/cpu/registers/ex_mem.v", f"{RTL}/cpu/registers/mem_wb.v", f"{TB}/cpu/unit/tb_pipeline_regs.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_system_cpu_smoke': {
        "top": 'tb_system_cpu_smoke',
        "files": [*DATAPATH_FILES, f"{TB}/system/tb_system_cpu_smoke.sv", f"{RTL}/uart/baud_gen.v", f"{RTL}/uart/uart_rx.v", f"{RTL}/uart/uart_tx.v", f"{RTL}/uart/uart_if.v", f"{RTL}/debug/debug_unit.v", f"{RTL}/debug/imem.v", f"{RTL}/debug/system.v"],
        "incdirs": [*CPU_INCDIRS, f"{TB}/common"],
    },
    'tb_cpu_contract': {
        "top": 'tb_cpu_contract',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/debug/tb_cpu_contract.sv", f"{RTL}/debug/imem.v"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_cpu_contract_stub': {
        "top": 'tb_cpu_contract',
        "files": [f"{TB}/cpu/debug/tb_cpu_contract.sv", f"{RTL}/debug/cpu_stub.v", f"{RTL}/debug/imem.v"],
        "incdirs": CPU_INCDIRS,
        "defines": {'CPU_STUB': 1},
    },
    'tb_cpu_debug': {
        "top": 'tb_cpu_debug',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/debug/tb_cpu_debug.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_cpu_step_halt': {
        "top": 'tb_cpu_step_halt',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_cpu_step_halt.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_cpu_freeze': {
        "top": 'tb_cpu_freeze',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_cpu_freeze.sv", f"{RTL}/debug/imem.v"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_halt_drain': {
        "top": 'tb_halt_drain',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_halt_drain.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_control_flow': {
        "top": 'tb_control_flow',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_control_flow.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_flush': {
        "top": 'tb_flush',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_flush.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_branch_execute': {
        "top": 'tb_branch_execute',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_branch_execute.sv", f"{RTL}/debug/imem.v"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_load_use_consumers': {
        "top": 'tb_load_use_consumers',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_load_use_consumers.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_load_use': {
        "top": 'tb_load_use',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_load_use.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_raw': {
        "top": 'tb_raw',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_raw.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_forwarding_paths': {
        "top": 'tb_forwarding_paths',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_forwarding_paths.sv"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_cpu_no_hazard': {
        "top": 'tb_cpu_no_hazard',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_cpu_no_hazard.sv", f"{RTL}/debug/imem.v"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_fetch': {
        "top": 'tb_fetch',
        "files": [*DATAPATH_FILES, f"{TB}/cpu/pipeline/tb_fetch.sv", f"{RTL}/debug/imem.v"],
        "incdirs": CPU_INCDIRS,
    },
    'tb_imem_bridge': {
        "top": 'tb_imem_bridge',
        "files": [f"{TB}/system/tb_imem_bridge.sv", f"{RTL}/debug/imem.v", f"{RTL}/debug/cpu_stub.v"],
        "incdirs": CPU_INCDIRS,
    },
})

SYNTH.update({
    'hazard_unit': [f"{RTL}/cpu/hazards/hazard_unit.v"],
    'forwarding_unit': [f"{RTL}/cpu/hazards/forwarding_unit.v"],
    'cpu': DATAPATH_FILES,
    'memory_stage': [f"{RTL}/cpu/memory/dmem.v", f"{RTL}/cpu/registers/mem_wb.v", f"{RTL}/cpu/memory/memory_stage.v"],
    'execute_stage': [f"{RTL}/cpu/execute/alu.v", f"{RTL}/cpu/registers/ex_mem.v", f"{RTL}/cpu/execute/execute_stage.v"],
    'decode_stage': [f"{RTL}/cpu/decode/alu_control.v", f"{RTL}/cpu/decode/control.v", f"{RTL}/cpu/decode/imm_gen.v", f"{RTL}/cpu/registers/regfile.v", f"{RTL}/cpu/registers/id_ex.v", f"{RTL}/cpu/decode/decode_stage.v"],
    'if_id': [f"{RTL}/cpu/registers/if_id.v"],
    'id_ex': [f"{RTL}/cpu/registers/id_ex.v"],
    'ex_mem': [f"{RTL}/cpu/registers/ex_mem.v"],
    'mem_wb': [f"{RTL}/cpu/registers/mem_wb.v"],
    'regfile': [f"{RTL}/cpu/registers/regfile.v"],
    'dmem': [f"{RTL}/cpu/memory/dmem.v"],
})

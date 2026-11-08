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
# tb_system_prog (system con el CPU real, sin CPU_STUB).
CPU_FILES: list[str] = []

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
                             "incdirs": [f"{TB}/common"], "defines": {}}

# Síntesis out-of-context: top -> archivos.
SYNTH = {
    "baud_gen": [f"{RTL}/uart/baud_gen.v"],
    "uart_rx": [f"{RTL}/uart/uart_rx.v"],
    "uart_tx": [f"{RTL}/uart/uart_tx.v"],
    "uart_if": [f"{RTL}/uart/baud_gen.v", f"{RTL}/uart/uart_rx.v",
                f"{RTL}/uart/uart_tx.v", f"{RTL}/uart/uart_if.v"],
    "cpu_stub": [f"{RTL}/debug/cpu_stub.v"],
    "debug_unit": [f"{RTL}/debug/debug_unit.v"],
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
    "top_debug": {"files": DEBUG_FILES_BASE + [f"{RTL}/top/top_debug.v"],
                  "xdc": "TP3_FINAL/constraints/basys3_debug.xdc"},
}

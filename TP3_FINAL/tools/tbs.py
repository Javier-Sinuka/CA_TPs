"""Tablas del runner (convenciones.md §3). Rutas relativas a la raíz del repo."""
RTL = "TP3_FINAL/VIVADO/TP_FINAL/rtl"
TB = "TP3_FINAL/VIVADO/TP_FINAL/tb"

UART_RTL = [f"{RTL}/uart/baud_gen.v", f"{RTL}/uart/uart_rx.v",
            f"{RTL}/uart/uart_tx.v", f"{RTL}/uart/uart_if.v"]

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
}

# Síntesis out-of-context: top -> archivos.
SYNTH = {
    "baud_gen": [f"{RTL}/uart/baud_gen.v"],
    "uart_rx": [f"{RTL}/uart/uart_rx.v"],
    "uart_tx": [f"{RTL}/uart/uart_tx.v"],
    "uart_if": [f"{RTL}/uart/baud_gen.v", f"{RTL}/uart/uart_rx.v",
                f"{RTL}/uart/uart_tx.v", f"{RTL}/uart/uart_if.v"],
}

# Cada mutación copia el archivo a build/mut/<name>/, reemplaza "old" (que tiene que aparecer
# exactamente una vez) por "new", y corre el TB esperando que FALLE.
MUTATIONS = [
    {"name": "tx_orden_bits", "file": f"{RTL}/uart/uart_tx.v", "tb": "tb_uart",
     "old": "r_shift <= r_shift >> 1;", "new": "r_shift <= r_shift << 1;"},
    {"name": "rx_muestreo_tarde", "file": f"{RTL}/uart/uart_rx.v", "tb": "tb_uart",
     "old": "localparam SAMPLE    = 4'd7;", "new": "localparam SAMPLE    = 4'd14;"},
]

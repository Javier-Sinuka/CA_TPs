"""Tablas del runner (convenciones.md §3). Rutas relativas a la raíz del repo."""
RTL = "TP3_FINAL/VIVADO/TP_FINAL/rtl"
TB = "TP3_FINAL/VIVADO/TP_FINAL/tb"

# Claves de cada entrada: "top", "files"; opcionales "incdirs" (lista de directorios para -I,
# por ejemplo f"{TB}/common" para `include "uart_bfm.svh"), "defines", "params", "legacy".
# "legacy": TB heredado de TP2 que termina con $finish aunque falle. Pasa si vvp
# devuelve 0 y no hay líneas que empiecen con FAIL ni contengan TIMEOUT.
# B-04 convierte esos TB y borra la marca.
TBS = {
    "tb_baud_gen": {"top": "tb_baud_gen",
                    "files": [f"{RTL}/uart/baud_gen.v", f"{TB}/uart/tb_baud_gen.sv"]},
    "tb_uart_rx": {"top": "tb_uart_rx", "legacy": True,
                   "files": [f"{RTL}/uart/uart_rx.v", f"{TB}/uart/tb_uart_rx.sv"]},
    "tb_uart_tx": {"top": "tb_uart_tx", "legacy": True,
                   "files": [f"{RTL}/uart/uart_tx.v", f"{TB}/uart/tb_uart_tx.sv"]},
}

# Síntesis out-of-context: top -> archivos.
SYNTH = {
    "baud_gen": [f"{RTL}/uart/baud_gen.v"],
    "uart_rx": [f"{RTL}/uart/uart_rx.v"],
    "uart_tx": [f"{RTL}/uart/uart_tx.v"],
    "uart_if": [f"{RTL}/uart/baud_gen.v", f"{RTL}/uart/uart_rx.v",
                f"{RTL}/uart/uart_tx.v", f"{RTL}/uart/uart_if.v"],
}

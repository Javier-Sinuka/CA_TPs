# TP2 - UART

Implementación de un sistema UART para FPGA.

## Estructura

```text
src/          Fuentes sintetizables: UART, interfaz RX/TX y ALU.
sim/          Testbench y otros archivos exclusivos de simulación.
constraints/  Restricciones de pines de la placa FPGA (.xdc).
doc/          Documentación para el informe.
```

Los directorios y productos generados por Vivado no se versionan. Las fuentes de
`src/` y `sim/` deben agregarse o actualizarse desde Vivado al crear el proyecto
local.

## Interfaz con la ALU

`interface_circuit.v` conecta los bytes recibidos por `uart_rx` con la ALU de
TP1 y entrega el resultado a `uart_tx`. La recepción y la transmisión están
separadas en `interface_rx.v` e `interface_tx.v`.

Cada operación se envía como tres bytes binarios: **A, B, operación**. La
respuesta es un byte con el resultado. Por ejemplo, `12 34 20` (hexadecimal)
devuelve `46`. Desde la PC, enviar un comando y esperar su respuesta.

La [guía de la interfaz](doc/interface_circuit.md) describe las señales, las
máquinas de estados, el manejo de errores y los comandos de simulación.
`sim/tb_uart_interface.sv` incluye un ejemplo completo de conexión entre el
generador de baudios, RX, la interfaz con ALU y TX.

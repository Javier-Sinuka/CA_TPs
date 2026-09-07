# TP2 - UART

Implementación de un sistema UART para FPGA.

## Estructura

```text
src/          Fuentes sintetizables: generador de baudios, transmisor y receptor.
sim/          Testbench y otros archivos exclusivos de simulación.
constraints/  Restricciones de pines de la placa FPGA (.xdc).
doc/          Documentación para el informe.
```

Los directorios y productos generados por Vivado no se versionan. Las fuentes de
`src/` y `sim/` deben agregarse o actualizarse desde Vivado al crear el proyecto
local.

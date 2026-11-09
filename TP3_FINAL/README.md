# TP3_FINAL

## Instalación y tests

- Python 3 instalado con el administrador de Python de Windows; se invoca con `py`. Dependencias: `py -m pip install -r TP3_FINAL/sw/requirements.txt` (`pyserial`, `pytest`).
- Icarus Verilog 12 en `C:\iverilog\bin`, en el `PATH`.
- g++ (MinGW, por ejemplo `winget install BrechtSanders.WinLibs.POSIX.UCRT`) en el `PATH`.
- Java 21 (Temurin) en el `PATH`. RARS 1.6: descargar `rars1_6.jar` de las releases de `TheThirdOne/rars` en GitHub y guardarlo como `TP3_FINAL/tools/rars1_6.jar` (no se versiona).
- Vivado 2024.1 en `C:\Xilinx\Vivado\2024.1`, o la variable de entorno `VIVADO` con la ruta a `vivado.bat`.
- Comando único, desde la raíz del repo: `py TP3_FINAL/tools/run.py test`.
- Python se corre con `cwd = TP3_FINAL/sw`: `py -m asm.rvasm`, `py -m host.cli`.
- Guía de la Debug Unit, la regresión y la integración del CPU: [`doc/documentation/debug.md`](doc/documentation/debug.md).

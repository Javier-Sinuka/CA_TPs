# TP3_FINAL

## Instalación y tests

- Python 3 instalado con el administrador de Python de Windows; se invoca con `py`. Dependencias: `py -m pip install -r TP3_FINAL/sw/requirements.txt` (`pyserial`, `pytest`).
- Icarus Verilog 12 en `C:\iverilog\bin`, en el `PATH`.
- g++ (MinGW, por ejemplo `winget install BrechtSanders.WinLibs.POSIX.UCRT`) en el `PATH`.
- Java 21 en el `PATH` (Temurin u OpenJDK). RARS 1.6: descargar `rars1_6.jar` de la [release oficial](https://github.com/TheThirdOne/rars/releases/tag/v1.6) y guardarlo como `TP3_FINAL/tools/rars1_6.jar` (no se versiona).
- Vivado 2024.1 en `C:\Xilinx\Vivado\2024.1`, o la variable de entorno `VIVADO` con la ruta a `vivado.bat`.
- Comando único, desde la raíz del repo: `py TP3_FINAL/tools/run.py test`.
- Python se corre con `cwd = TP3_FINAL/sw`: `py -m asm.rvasm`, `py -m host.cli`.
- Guía de la Debug Unit, la regresión y la integración del CPU: [`doc/documentation/debug.md`](doc/documentation/debug.md).

En Linux, desde la raíz del repositorio y con Java 21 disponible (`java -version`), descargar RARS y ejecutar la suite con el entorno Python del proyecto:

```bash
curl --fail --location --retry 2 https://github.com/TheThirdOne/rars/releases/download/v1.6/rars1_6.jar --output TP3_FINAL/tools/rars1_6.jar
TP3_FINAL/build/venv/bin/python TP3_FINAL/tools/run.py test
```

La creación del entorno Python está detallada en la [guía de integración](doc/documentation/09_integracion_cpu_debug_basys3.md). RARS se ejecuta por consola y no necesita una pantalla. En esta máquina se verificó con OpenJDK 21.0.12.1; el JAR descargado tiene SHA-256 `780f730eb457b1ba609e968accc2c8b77d8f92c3d9dbf30cc7fdb3cfb14e8c24`.

## Organización del código

El datapath vive en `rtl/cpu/`, las definiciones compartidas en `rtl/common/` y sus bancos en `tb/cpu/`. UART, debug y tops conservan sus carpetas. Los programas dirigidos del CPU están en `programs/cpu/`; los programas del host permanecen en `programs/`. Véase la [guía de organización](doc/documentation/organizacion.md) para el árbol, comandos vigentes y alcance de la limpieza.

## Sistema integrado listo para Basys3

CPU real + Debug Unit + UART, `top_debug`, parte **xc7a35tcpg236-1**, clock interno de 50 MHz y UART 115200 8N1. Proyecto generado con Vivado 2025.1. [Guía de integración, bitstream y programación](doc/documentation/09_integracion_cpu_debug_basys3.md).

Desde la raíz del repositorio, con `VIVADO` apuntando al ejecutable instalado:

```bash
python3 TP3_FINAL/tools/run.py project
python3 TP3_FINAL/tools/run.py bit top_debug --mhz 50 --clk mmcm
```

El bitstream preparado está en `TP3_FINAL/build/bit/top_debug_50mhz_mmcm/top_debug.bit`. Las dependencias Python se instalan desde `sw/requirements.txt`; en esta máquina se utilizó el venv de build. El proyecto nativo usa `tb_system_cpu_smoke` como simulación por defecto. La programación física queda pendiente de que el usuario conecte la placa.

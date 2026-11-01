# Convenciones de la pista B (Fases 8 y 9)

Fuente única de rutas, herramientas, estilo y reglas de testbench. Los issues de [planning/issues](../../../planning/issues/README.md) la citan en vez de repetirla. Si un issue contradice este archivo, gana este archivo; si un issue necesita algo que no está acá, el ejecutor **se detiene y pregunta**, no improvisa.

Documentos hermanos (contratos, mismo directorio): [`protocolo.md`](protocolo.md), [`dump.md`](dump.md), [`interfaz_cpu.md`](interfaz_cpu.md), [`decisiones.md`](decisiones.md).

## 1. Rutas

Todas relativas a la raíz del repo (`CA_TPs/`).

| Alias | Ruta | Contenido |
| --- | --- | --- |
| `$TP3` | `TP3_FINAL/` | |
| `$RTL` | `TP3_FINAL/VIVADO/TP_FINAL/rtl/` | RTL sintetizable. Ya contiene lo de A (`alu.v`, `control.v`, `imm_gen.v`, `riscv_defs.vh`) |
| `$RTL/uart/` | | `baud_gen.v`, `uart_rx.v`, `uart_tx.v`, `uart_if.v` |
| `$RTL/debug/` | | `debug_unit.v`, `cpu_stub.v`, `imem.v`, `system.v`, `cpu_ports.vh` |
| `$RTL/top/` | | `top_uart_echo.v`, `top_debug.v` (únicos que tocan pines y Clock Wizard) |
| `$TB` | `TP3_FINAL/VIVADO/TP_FINAL/tb/` | TB de A en la raíz; los de B en `tb/uart/`, `tb/debug/`, `tb/system/` |
| `$XDC` | `TP3_FINAL/constraints/` | `basys3_uart_echo.xdc`, `basys3_debug.xdc` |
| `$DOCS` | `TP3_FINAL/doc/documentation/` | Este archivo y los contratos; `uart.md`, `debug.md` |
| `$SW` | `TP3_FINAL/sw/` | Raíz de Python (`asm/`, `host/`, `tests/`) y C++ (`iss/`) |
| `$PROG` | `TP3_FINAL/programs/` | `*.s`, y generados `*.hex`, `*.bin`, `*.expected.json` |
| `$TOOLS` | `TP3_FINAL/tools/` | `run.py`, `tbs.py`, `*.tcl`, `rars_ref.py` |
| `$BUILD` | `TP3_FINAL/build/` | Salidas. **No se versiona** (agregar `build/` al `.gitignore` de `TP3_FINAL`) |

`TP3_FINAL/src/` y `TP3_FINAL/sim/` no se usan.

## 2. Herramientas (verificadas en esta máquina el 2026-10-31)

| Herramienta | Cómo se invoca | Nota |
| --- | --- | --- |
| Python 3.14 | **`py`** (nunca `python`: en esta máquina es el alias de la Store) | `pyserial` ya instalado |
| pytest | `py -m pytest` | Instalar una vez: `py -m pip install -r TP3_FINAL/sw/requirements.txt` |
| Icarus 12 | `iverilog`, `vvp` (en `PATH`, `C:\iverilog\bin`) | Siempre `-g2012` |
| g++ 16 (MinGW) | `g++` (en `PATH`) | `-std=c++17 -O2 -Wall -Wextra -Werror` |
| Java 21 | `java` (en `PATH`) | Solo para RARS |
| RARS 1.6 | `java -jar TP3_FINAL/tools/rars1_6.jar` | Lo descarga el usuario (B-19); `*.jar` no se versiona |
| Vivado 2024.1 | `C:/Xilinx/Vivado/2024.1/bin/vivado.bat -mode batch -source <tcl>` | No está en `PATH`. Los scripts usan la variable de entorno `VIVADO` si existe, si no esa ruta |

`TP3_FINAL/sw/requirements.txt` contiene exactamente:

```
pyserial>=3.5
pytest>=8
```

**Parte FPGA: `xc7a35tcpg236-1` (Basys3).** El `.xpr` actual dice `xc7a35ticpg236-1L`, que es otra parte; los scripts Tcl usan la correcta y el `.xpr` se corrige en B-01.

## 3. Runner: `py TP3_FINAL/tools/run.py <objetivo>`

Un solo punto de entrada; devuelve 0 si todo pasó y 1 si algo falló. Se ejecuta desde la raíz del repo.

| Objetivo | Qué hace |
| --- | --- |
| `tb <nombre>` | Compila y corre un TB de la tabla `TBS` de `tools/tbs.py` |
| `tbs` | Todos los TB de `TBS` |
| `pytest` | `py -m pytest` con `cwd = TP3_FINAL/sw` |
| `iss` | Compila `build/iss.exe` y `build/test_iss.exe`, corre `test_iss.exe` |
| `mutate` | Mutaciones de B-04 (y las que se agreguen) |
| `vectors [--check]` | Regenera los vectores de `$TB/debug/vectors/` con `tools/gen_vectors.py`; con `--check` falla si cambian (B-09) |
| `test` | `iss` + `vectors --check` + `tbs` + `pytest` + `mutate`, en ese orden (los tests de Python usan `build/iss.exe`), sin cortar en la primera falla; imprime un resumen |
| `regress [--board COMx]` | B-27 |
| `synth_ooc <top>` | Síntesis out-of-context con `tools/synth_ooc.tcl` |
| `bit <top> [--mhz N] [--define NAME ...]` | Bitstream con `tools/build_bit.tcl`; cada `--define` va a `synth_design -verilog_define` (ej. `CPU_STUB`) |

`tools/tbs.py` define `TBS = {nombre: {"top": módulo, "files": [...], "incdirs": [...], "defines": {...}, "params": {...}, "legacy": bool}}` (todo menos `top` y `files` es opcional; `legacy` solo para los TB de TP2 hasta B-04), más `MUTATIONS` (B-04), `BITS = {top: {"files", "xdc", "defines"}}` (B-05) y `CPU_FILES` (B-28). Rutas relativas a la raíz del repo. `run.py tb <nombre> [+plusarg ...]` pasa los plusargs a `vvp`. **`vvp` corre con `cwd` = raíz del repo**: los TB abren vectores y escriben logs con rutas relativas a ella. La BFM vive en `$TB/common/uart_bfm.svh` y se incluye con `` `include "uart_bfm.svh" `` (su directorio va en `incdirs`).

Compilación de un TB (exactamente esto, armado por `run.py`):

```
iverilog -g2012 -Wall -Wno-timescale -I <dir de cada archivo .v> [-D<k>=<v> ...] [-P<top>.<k>=<v> ...] -s <top> -o TP3_FINAL/build/<nombre>.vvp <files...>
vvp -n TP3_FINAL/build/<nombre>.vvp
```

Salida en `TP3_FINAL/build/<nombre>.log`. El TB **pasa** si y solo si: `vvp` devuelve 0, **y** el log contiene una línea que empieza con `PASS <top>:` (`<top>` = nombre del **módulo**: dos entradas de `TBS` pueden correr el mismo módulo con otros parámetros), **y** el log no contiene ninguna línea que empiece con `FAIL`. Cualquier otra cosa es falla.

## 4. Estilo RTL (todo archivo `.v` nuevo o importado)

```verilog
`timescale 1ns/1ps
`default_nettype none

module nombre #(
    parameter P = 1
)(
    input  wire       i_clock,
    input  wire       i_reset,     // síncrono, activo en alto
    ...
);
    ...
endmodule

`default_nettype wire
```

- Puertos `i_`/`o_`; registros internos `r_`; cables internos `w_`; parámetros en MAYÚSCULAS; `localparam` para estados (`S_IDLE`, ...).
- Un `always @(posedge i_clock)` por registro o grupo coherente; lógica combinacional en `always @(*)` con **valor por defecto al principio** de cada bloque.
- Prohibido en RTL: `initial` (excepción única: inicialización de memorias y el registro sincronizador de reset del top, ver `interfaz_cpu.md`), `negedge`, `#retardos`, reset asíncrono, `$display`, latches.
- Atributo `(* ASYNC_REG = "TRUE" *)` en todo flip-flop de un sincronizador.
- Ningún módulo sincroniza el reset salvo el top (D-10).
- Comentarios: en castellano, cortos, solo donde el porqué no es obvio.

## 5. Reglas de testbench

- Archivo `.sv`, `` `timescale 1ns/1ps ``, módulo con el mismo nombre que el archivo.
- **Leer salidas del DUT lejos del flanco activo**: en `@(negedge clk)` o con `#1` después del `@(posedge clk)`. Nunca leerlas dentro de un `always @(posedge clk)` del TB (es la carrera que causó H-2).
- Manejar entradas del DUT en `@(negedge clk)` o con `<=`.
- Contador `errors`; cada chequeo fallido imprime una línea que empieza con `FAIL <caso>: ` con esperado y obtenido.
- Final del TB: `if (errors != 0) $fatal(1, "FAIL <módulo>: %0d errores", errors); else begin $display("PASS <módulo>: %0d chequeos", checks); $finish; end`.
- Watchdog obligatorio: un `initial begin #(LIMITE); $fatal(1, "FAIL <nombre>: watchdog"); end` con un límite holgado (el doble del tiempo esperado).
- Línea serie: con las tareas de `tb/common/uart_bfm.svh` (B-04), nunca reimplementarlas.

## 6. Python y C++

- Python 3.14, solo biblioteca estándar más `pyserial`; sin dependencias extra salvo que el issue lo diga.
- Todo comando Python corre con `cwd = TP3_FINAL/sw`: módulos como `py -m asm.rvasm`, `py -m host.cli`. `asm/` y `host/` tienen `__init__.py` vacío. Tests en `sw/tests/test_*.py`.
- Funciones con anotaciones de tipo; errores de usuario como excepciones propias (`AsmError`, `LinkError`, `DumpError`), nunca `sys.exit` dentro de una biblioteca.
- C++17, un solo `iss.cpp` con la lógica y `iss_main.cpp` / `test_iss.cpp` como `main`s. Sin bibliotecas externas.

## 7. Git

- Ramas `b/<issue>-<slug>` (por ejemplo `b/B-04-tb-uart`); un PR por issue.
- Commits en castellano, imperativo, prefijo del área: `uart: ...`, `debug: ...`, `sw-asm: ...`, `tools: ...`, `docs: ...`.
- Un commit que cambia comportamiento no mezcla cambios de estilo. Cuando un issue pide "commit propio", es literal.

## 8. Definición de terminado (vale para todo issue)

1. Todas las casillas de "Listo cuando" tildadas, con la salida del comando que lo prueba pegada en el PR.
2. `py TP3_FINAL/tools/run.py test` devuelve 0.
3. RTL nuevo: `py TP3_FINAL/tools/run.py synth_ooc <top>` sin `inferring latch`, sin `multi-driven`, sin `implicit net` (el script falla si los encuentra).
4. Si el issue tocó un contrato (`protocolo.md`, `dump.md`, `interfaz_cpu.md`), el cambio está en el mismo PR y lo aprobó A.
5. Cualquier decisión nueva va a `decisiones.md` con su porqué. Un ejecutor **no** toma decisiones de diseño: si falta algo, se detiene y lo pregunta.

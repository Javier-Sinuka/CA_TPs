# Debug Unit, software de la pista B y entrega a la integración

Guía para que A corra la regresión, lea un diff y conecte su CPU en la Fase 10 sin preguntar. No repite los contratos: los enlaza ([`protocolo.md`](protocolo.md), [`dump.md`](dump.md), [`interfaz_cpu.md`](interfaz_cpu.md), [`convenciones.md`](convenciones.md), [`decisiones.md`](decisiones.md)). Rutas relativas a la raíz del repo; `$RTL` = `TP3_FINAL/VIVADO/TP_FINAL/rtl/`, `$TB` = `TP3_FINAL/VIVADO/TP_FINAL/tb/`.

## 1. Qué hay

| Módulo / herramienta | Archivo | Issue |
| --- | --- | --- |
| UART: `baud_gen`, `uart_rx`, `uart_tx` | `$RTL/uart/` | B-01, B-02, B-03 |
| UART: `uart_if` (valid/ready) | `$RTL/uart/uart_if.v` | B-03 |
| TB de la UART y mutaciones | `$TB/uart/`, `$TB/common/uart_bfm.svh`, `MUTATIONS` en `tools/tbs.py` | B-04 |
| Eco en placa | `$RTL/top/top_uart_echo.v`, `constraints/basys3_uart_echo.xdc`, `$TB/top/tb_uart_echo.sv` | B-05 |
| Protocolo (Python) | `sw/host/proto.py`, [`protocolo.md`](protocolo.md) | B-06 |
| Dump y formato canónico | `sw/host/dump.py`, `sw/host/canonical.py`, [`dump.md`](dump.md) | B-07 |
| Puertos del CPU | `$RTL/debug/cpu_ports.vh`, [`interfaz_cpu.md`](interfaz_cpu.md) | B-08 |
| Stub, imem y su modelo | `$RTL/debug/cpu_stub.v`, `$RTL/debug/imem.v`, `sw/host/stub_model.py`, `$TB/debug/vectors/` | B-09 |
| Debug Unit (`V`, `X`, errores) y `system.v` | `$RTL/debug/debug_unit.v`, `$RTL/debug/system.v` | B-10 |
| Debug Unit: `S`, `R`/`A`, `L`, `D`, memoria usada | `$RTL/debug/debug_unit.v`, `$TB/debug/tb_debug_unit.sv` | B-11, B-12, B-13, B-14, B-15 |
| TB del sistema (guion de la Fase 10) | `$TB/debug/tb_system_debug.sv` | B-16 |
| Tops de placa y XDC | `$RTL/top/top_debug.v`, `constraints/basys3_debug.xdc`, `sw/host/guion_debug.py` | B-17 |
| Runner y tablas | `tools/run.py`, `tools/tbs.py`, `tools/*.tcl` | B-18 |
| Ensamblador | `sw/asm/rvasm.py`, `sw/asm/isa.py` | B-19 |
| Desensamblador | `sw/asm/disasm.py` | B-20 |
| ISS (golden model) | `sw/iss/` (`build/iss.exe`) | B-21 |
| Programas de prueba | `programs/*.s`, `.hex`, `.bin`, `.expected.json` | B-22 |
| Enlace serie | `sw/host/link.py`, `sw/host/replay.py` | B-23 |
| Placa simulada | `sw/host/fakeboard.py` | B-24 |
| CLI | `sw/host/cli.py` | B-25 |
| GUI, golden y diagrama espacio-tiempo | `sw/host/gui.py`, `sw/host/golden.py`, `sw/host/spacetime.py`, [`manual_interfaz.md`](manual_interfaz.md) | B-26 |
| Regresión de tres niveles | `tools/regress.py` | B-27 |
| TB de sistema para el CPU real | `$TB/system/tb_system_prog.sv` | B-28 |

(`sw/`, `programs/` y `tools/` están bajo `TP3_FINAL/`.)

## 2. Instalar y verificar

Una vez:

- Python 3 con el administrador de Python de Windows; se invoca con `py` (no `python`, que en Windows puede abrir la Microsoft Store). Dependencias: `py -m pip install -r TP3_FINAL/sw/requirements.txt` (`pyserial`, `pytest`).
- Icarus Verilog 12 en `C:\iverilog\bin`, en el `PATH`.
- g++ (MinGW, por ejemplo `winget install BrechtSanders.WinLibs.POSIX.UCRT`) en el `PATH`.
- Java 21 (Temurin) en el `PATH`. RARS 1.6: descargar `rars1_6.jar` de las releases de `TheThirdOne/rars` en GitHub y guardarlo como `TP3_FINAL/tools/rars1_6.jar` (no se versiona).
- Vivado 2024.1 en `C:\Xilinx\Vivado\2024.1`, o la variable de entorno `VIVADO` con la ruta a `vivado.bat`.
- Python se corre con `cwd = TP3_FINAL/sw`: `py -m asm.rvasm`, `py -m host.cli`.

Verificar, desde la raíz del repo (los dos tienen que terminar con código 0):

```
py TP3_FINAL/tools/run.py test
py TP3_FINAL/tools/run.py regress
```

`test` corre `iss`, `vectors --check`, `tbs`, `pytest` y `mutate` (tarda unos 2-3 minutos) y termina con:

```
resumen:
  iss      OK
  vectors  OK
  tbs      OK
  pytest   OK
  mutate   OK
```

`regress` compara cada programa de `programs/` con su `.expected.json` en tres niveles. Salida esperada:

```
programa     iss   fake  rtl   board
alu_nodep    OK    OK    -     -
branches     OK    OK    -     -
call_ret     OK    OK    -     -
const32      OK    OK    -     -
load_use     OK    OK    -     -
mem_bytes    OK    OK    -     -
no_halt      OK    OK    -     -
raw_hazards  OK    OK    -     -
suma         OK    OK    -     -
rtl: stub (sin CPU real) OK
```

`-` = nivel no corrido. Mientras `CPU_FILES` esté vacío, la columna `rtl` no compara programas: se corre una vez `tb_system_prog_stub` y se informa en la línea `rtl: stub`. Opciones: `--levels iss,fake,rtl,board`, `--program <nombre>`, `--board COMx` (agrega el nivel `board`), `--iss-mutant sra` (ver §4). Las salidas por programa quedan en `TP3_FINAL/build/regress/<programa>.<nivel>.json`.

Si falta `build/iss.exe`, `regress` avisa `ERR: falta build/iss.exe (py TP3_FINAL/tools/run.py iss)`: se compila con ese comando (o con `run.py test`).

## 3. Conectar el CPU real (Fase 10)

1. `cpu.v` declara sus puertos con `` `include "cpu_ports.vh" `` ([`interfaz_cpu.md`](interfaz_cpu.md) §1):

   ```verilog
   module cpu (
   `include "cpu_ports.vh"
   );
   ```

2. Cumplir las obligaciones **[A]**: §2 (`adv = i_en && !o_halted`: todo flip-flop con efecto cambia solo con `adv = 1`), §3 (qué hace el reset) y §4 (dmem de 256 palabras, un bit dirty por palabra, una palabra limpia se lee 0, accesos desalineados ignoran los bits bajos). El formato de las 16 palabras de latch es el de [`dump.md`](dump.md) §3.
3. Agregar los archivos del CPU (`cpu.v` y submódulos) a `CPU_FILES` en `TP3_FINAL/tools/tbs.py`. Esa lista habilita `tb_system_prog` y también entra en el bitstream de `top_debug`. Nada más cambia: `system.v` instancia `cpu` cuando `CPU_STUB` no está definido.
4. `py TP3_FINAL/tools/run.py tb tb_system_prog` → `PASS tb_system_prog`. Con `+prog=<.hex>` y `+out=<archivo>` corre otro programa y deja el dump (un byte hexadecimal por línea).
5. `py TP3_FINAL/tools/run.py regress` → la columna `rtl` ahora compara los 9 programas (la línea `rtl: stub` desaparece).

Si `rtl` da `FAIL` para un programa, el diff dice qué estado difiere (§4). Si da `ERR`, el mensaje de `FALLAS` indica que `tb_system_prog` falló o no dejó el dump: mirar `TP3_FINAL/build/tb_system_prog.log`.

## 4. Leer un diff

El mutante `sra` inyecta un bug en el ISS (el `sra` pasa a ser lógico). Es el ejemplo de una falla real:

```
py TP3_FINAL/tools/run.py regress --levels iss --iss-mutant sra
```

```
programa     iss   fake  rtl   board
alu_nodep    FAIL  -     -     -
branches     OK    -     -     -
...
suma         OK    -     -     -

FALLAS:
alu_nodep [iss] x10: esperado=0xffffffff iss=0x01ffffff
alu_nodep [iss] x21: esperado=0xfffffffe iss=0x7ffffffe
```

Cada línea de `FALLAS` es `programa [nivel] clave: esperado=… <nivel>=…`:

| Parte | Significado |
| --- | --- |
| `alu_nodep` | Programa de `programs/` (ver `alu_nodep.s`) |
| `[iss]` | Nivel que falló: `iss`, `fake`, `rtl` o `board`. El valor obtenido lleva ese nombre (`iss=…`, `rtl=…`) |
| `x10` | Clave que difiere: `stop`, `pc`, `xN` o `mem[0x…]` |
| `esperado=0xffffffff` | Valor de `programs/alu_nodep.expected.json` (lo generó el ISS, validado contra RARS en B-22) |
| `iss=0x01ffffff` | Valor que dio ese nivel |

Qué mirar primero según la clave:

| Clave | Qué revisar |
| --- | --- |
| `stop` distinto | El programa no llegó al HALT (timeout o `limit`) o paró donde no debía: HALT, timeout de `R`, `HALT_AT`, bucle |
| `pc` | Saltos y branches (destino, condición), o el HALT: `pc` es la dirección del HALT ([`decisiones.md`](decisiones.md) D-26) |
| `xN` | La última instrucción que escribe `xN` en el `.s`: operación, inmediato, forwarding o riesgo de load-use. Un valor que casi coincide (como arriba: los bits altos cambiaron) apunta a la operación, no al dato |
| `mem[0x…]` | Stores (`sb`/`sh`/`sw`, byte enables), el bit dirty y la regla "palabra limpia se lee 0" ([`interfaz_cpu.md`](interfaz_cpu.md) §4). `esperado=-` o `rtl=-` significa que esa dirección aparece de un solo lado |

Si fallan los tres niveles a la vez, el `.expected.json` o el ISS son sospechosos; si falla solo `rtl` o `board`, es el CPU o la placa. Los `.expected.json` no se regeneran para que `regress` pase.

## 5. Placa

Con el CPU real (sin `--define CPU_STUB`), desde la raíz del repo:

```
py TP3_FINAL/tools/run.py bit top_debug --mhz 50
py TP3_FINAL/tools/run.py program TP3_FINAL/build/bit/top_debug_50mhz_wiz/top_debug.bit
```

Después, desde `TP3_FINAL/sw` (`COMx` es el "USB Serial Port" de la Basys3; en la PC de B es COM7 y COM3 es otra cosa):

```
py -m host.cli --port COMx
```

Y desde la raíz, la regresión con el nivel de placa:

```
py TP3_FINAL/tools/run.py regress --board COMx
```

LEDs: [`interfaz_cpu.md`](interfaz_cpu.md) §7. `LD0` conmuta por byte recibido, `LD1` framing (pegajoso), `LD2` overrun (pegajoso), `LD3` `halted`, `LD4..LD7` estado de la FSM de la Debug Unit, `LD15` `locked` del Wizard. La GUI y su manual: [`manual_interfaz.md`](manual_interfaz.md).

### Placa con stub (B-17)

Resultados de B-17: `top_debug` con `cpu_stub` (`HALT_AT = 20`), `system.v` sin cambios, a 50 MHz y 115200 baud.

#### Síntesis e implementación (hechas en la PC de desarrollo)

Comando: `py TP3_FINAL/tools/run.py bit top_debug --mhz 50 --define CPU_STUB` (el define va siempre por la línea de comando; `BITS["top_debug"]` no lo fija, para que el CPU real use el mismo top sin él). Fecha: 2026-11-07. RTL: commit `c9cada2` (B-17; no hubo cambios de RTL hasta `c6c5659`).

| Reloj | WNS (ns) | WHS (ns) | LUT | FF | Latches | Multi-driven |
| --- | --- | --- | --- | --- | --- | --- |
| Wizard (`--clk wiz`) | 12,589 | 0,160 | 351 | 320 | 0 | 0 |
| MMCM (`--clk mmcm`) | 12,413 | 0,143 | — | — | 0 | 0 |

Utilización jerárquica (`util_hier.rpt`, modo `wiz`):

| Bloque | LUT | FF |
| --- | --- | --- |
| `top_debug` (total) | 351 | 320 |
| `u_system` | 350 | 318 |
| `u_system/u_debug` (Debug Unit) | 289 | 228 |
| `u_system/u_uart` | 50 | 55 |
| `u_system/u_cpu` (stub) | 12 | 32 |
| `u_clk` | 0 | 0 |

Observaciones:

- Sin críticos ni errores. Las 80 advertencias de síntesis son `Synth 8-7129` (64: bits de `i_imem_data` del stub sin carga), `Synth 8-3917` (14: `o_led[14:8]` constantes en 0, dos veces porque la síntesis las informa dos veces), `Synth 8-7080` (síntesis paralela no aplicable) y `Synth 8-6014` (`u_system/u_imem/r_mem_reg` eliminado por sin uso).
- Con el stub, la `imem` no aparece en la jerarquía ni usa BRAM ni LUTRAM: el stub ignora `i_imem_data`, así que Vivado la elimina (`Synth 8-6014`). La placa con el stub no prueba el almacenamiento de `L`, solo el protocolo; el contenido de la `imem` en placa se prueba en la Fase 10 con el CPU real (§7). Sus recursos están en §6.
- LEDs: `LD0` conmuta por byte recibido, `LD1` framing (pegajoso), `LD2` overrun (pegajoso), `LD3` `halted`, `LD4..LD7` estado de la FSM de la Debug Unit (`o_state`), `LD15` `locked` del Wizard. `LD8..LD14` fijos en 0.
- El `.bit` de `--mhz 50 --define CPU_STUB` queda en `TP3_FINAL/build/bit/top_debug_50mhz_wiz/top_debug.bit` (no se versiona). Programación: `py TP3_FINAL/tools/run.py program <bit>`.

#### Prueba en placa (la hace una persona)

Desde `TP3_FINAL/sw`:

```
py -m host.guion_debug --port COMx --repeat 20
py -m host.cli --port COMx --script tests/data/b16_script.txt
```

La primera cierra B-17 y el último criterio de B-23; la segunda, el criterio de B-25 contra la placa. Prueba negativa: con `btnC` apretado, `guion_debug` tiene que terminar en `FAIL guion_debug: 0/N` y código 1 (timeout de `V`).

| Dato | Valor |
| --- | --- |
| Fecha | 2026-11-07 |
| Puerto COM | COM7 ("USB Serial Port"; COM3 es Intel AMT SOL, no la placa) |
| `LD15` encendido tras programar | No informado; implícito: el guion pasó, así que el Wizard enganchó |
| `guion_debug --repeat 20` | `PASS guion_debug: 20/20`, código 0 |
| `guion_debug` con `btnC` apretado | `rep 1: FAIL V: timeout esperando versión (0 de 6 bytes)` y `FAIL guion_debug: 0/1`, código 1 |
| `cli --script tests/data/b16_script.txt` | Código 0, sin líneas `error:`; `step 5` da ciclos 1..5, `run` da `halt ciclos=20`, `raw 7a` da `E 01` |
| RTL probado | commit `c9cada2` |

Programación: `py TP3_FINAL/tools/run.py program TP3_FINAL/build/bit/top_debug_50mhz_wiz/top_debug.bit` dio `PASS program` (Digilent `210183A8A4C3A`, `End of startup status: HIGH`).

Nota sobre la salida de `run`: con el stub, `run: halt ciclos=20 pc=0x1a0b0014` muestra el valor de la latch 11 (el stub llena las latches con `0x1A00_0000 | (k << 16) | ciclos`), mientras que `dump` muestra `pc=0x00000050` (el PC del stub). Es un artefacto del stub: con el CPU real la latch 11 es el PC de la instrucción en WB (el HALT, D-26), así que `run` mostrará un PC de programa.

## 6. Recursos de la Debug Unit

Part `xc7a35tcpg236-1`, 50 MHz. RTL del commit `c9cada2` (sin cambios de RTL hasta `c6c5659`).

| Bloque | LUT | de ellas LUTRAM | FF | RAMB36 / RAMB18 | Fuente |
| --- | --- | --- | --- | --- | --- |
| `debug_unit` | 289 | 0 | 228 | 0 / 0 | `build/bit/top_debug_50mhz_wiz/util_hier.rpt` |
| `uart_if` (`u_uart`: `baud_gen` 5 / 6, `uart_rx` 25 / 30, `uart_tx` 20 / 19 LUT / FF) | 50 | 0 | 55 | 0 / 0 | `build/bit/top_debug_50mhz_wiz/util_hier.rpt` |
| `imem` (256 × 32) | 212 (36 de lógica + 176 LUTRAM) | 176 | 0 | 0 / 0 | `build/synth_ooc/imem/util.rpt` |

- `debug_unit` y `uart_if`: `report_utilization -hierarchical` que genera `tools/build_bit.tcl` sobre `top_debug` con el stub, 2026-11-07, estado `Routed`.
- `imem`: no figura en ese reporte porque con el stub Vivado la elimina (§5). Sus números salen de `py TP3_FINAL/tools/run.py synth_ooc imem`, 2026-11-08, estado `Synthesized` (sin implementar, el conteo final puede ser algo menor). Es lectura asíncrona, por eso va en RAM distribuida y no en BRAM. El `TIMING-17` de su `methodology.rpt` aparece porque el análisis es out-of-context, sin reloj.
- Los reportes están en `TP3_FINAL/build/` (no se versiona); se regeneran con los comandos de arriba (`run.py bit top_debug --mhz 50 --define CPU_STUB` y `run.py synth_ooc imem`).
- Con el CPU real, la `imem` aparece en la jerarquía de `top_debug` y suma sus 212 LUT.

## 7. Pendiente

Casillas abiertas de B-01 a B-28 y decisiones **[A]** sin aprobar (cada una con su issue):

| Qué | Issue | Estado |
| --- | --- | --- |
| Aprobación de A de [`protocolo.md`](protocolo.md) | B-06 | "v1 propuesta, pendiente de aprobación de A" |
| Aprobación de A de [`dump.md`](dump.md) (layout de latches, §3) | B-07 | idem |
| Aprobación de A de [`interfaz_cpu.md`](interfaz_cpu.md) y sus obligaciones **[A]** (§2 `adv`, §3 reset, §4 dmem) | B-08 | idem |
| D-17: imem y dmem de 256 palabras, la dirección da la vuelta **[A]** | B-08, B-09 | Sin aprobar |
| D-18: accesos desalineados ignoran los bits bajos **[A]** | B-08, B-21 | Sin aprobar |
| D-19: el reset pone x1-x31 y dirty en 0; palabra limpia se lee 0 **[A]** | B-08 | Sin aprobar |
| D-24: 16 palabras de latch, un único layout **[A]** | B-07 | Sin aprobar |
| Diagrama espacio-tiempo con el CPU real (último criterio de B-26) | B-26 | Abierto hasta las Fases 10/11; con `--fake` el diagrama es una demo |
| Contenido de la `imem` (`L`) y programas reales en la placa | B-17, B-28 | Con el stub solo se probó el protocolo; falta la placa con el CPU real |
| Columna `rtl` de `regress` comparando los 9 programas | B-27, B-28 | Hoy solo corre el stub; se activa al llenar `CPU_FILES` (§3) |
| A corrió `run.py regress` siguiendo solo este documento (comentario en el PR con la tabla) | B-29 | Abierto |

Cuando A apruebe B-06/B-07/B-08, la primera línea de cada contrato pasa a `**Estado: v1 congelada (aprobada por A el AAAA-MM-DD).**`.

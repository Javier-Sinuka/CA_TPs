# Registro de decisiones · pista B (M0)

Resuelve los `[DECISION]` D-01 a D-13 abiertos en [planning/issues](../../../planning/issues/README.md). Fecha: 2026-10-31.

Criterio general: tocar lo mínimo del núcleo que escribimos en TP2 (`baud_gen`, `uart_rx`, `uart_tx`), pero sí tocarlo cuando hay un defecto real; no agregar capas que el núcleo ya resuelve.

## Resumen

| ID | Tema | Resolución | ¿Igual a la inclinación del plan? |
| --- | --- | --- | --- |
| D-01 | Layout | (a) `VIVADO/TP_FINAL/{rtl,tb}` + **copia** de la UART | Sí |
| D-02 | Entorno | (a) Python 3 real + `tools/run.py`; Tcl de síntesis versionado | Sí |
| D-03 | Simulador | (a) Icarus diario, xsim al cerrar milestone | Sí |
| D-04 | Estilo | (a) `i_`/`o_`/`r_`/`w_`, `default_nettype none`, `ASYNC_REG` en RTL | Sí |
| D-05 | Parámetros baud | (a) `CLOCK_FREQ`, `BAUD_RATE`; `OVERSAMPLE` = `localparam 16` | Sí |
| D-06 | Divisor | (c) Redondear, con D-07 aplicado | Sí |
| D-07 | Stop bit | (a) Evaluar a mitad de bit, test-first | Sí, con un agregado |
| D-08 | Framing error | (a) Descartar + pulso de error, **resuelto en el núcleo** | Cambia el dónde |
| D-09 | `interface_rx/tx` | (a) No reutilizar | Sí |
| D-10 | Reset | Activo en alto, síncrono, generado una vez en el top | Sí |
| D-11 | Baud alto / desvío | (c) `CLK/32` y `CLK/128`; barrido ±0,5/±1/±2 % | Sí |
| D-12 | Eco | (b) Retención de 1 byte, ráfaga parametrizable (256) | Sí |
| D-13 | Reloj | Clock Wizard creado por Tcl desde un argumento `MHZ`; sin `.xci` versionado | **No** |
| D-14 | Contrato TX (nueva) | Handshake valid/ready, **sin** detector de flanco | **No** (reemplaza B-03 tarea 2) |
| D-15 … D-27 | Contratos de M1 a M4 | Ver la sección "Decisiones de los contratos" | — |

## Decisiones

### D-01 · Layout: (a) + copia

Fuentes en `TP3_FINAL/VIVADO/TP_FINAL/rtl/` (UART en `rtl/uart/`), TB en `tb/` (`tb/uart/`), docs en `TP3_FINAL/doc/documentation/`, y `sw/`, `programs/`, `tools/` nuevos en `TP3_FINAL/`. La UART se **copia**: TP2 es una entrega cerrada y no debe cambiar cuando arreglemos el RX de TP3. `TP3_FINAL/src` y `TP3_FINAL/sim` quedan sin uso (se pueden borrar para no confundir).

### D-02 · Entorno: Python + script

Instalar Python 3 real (python.org o `winget install Python.Python.3.12`) y `pyserial`. Runner: `python tools/run.py <objetivo>` con los objetivos `tb_uart`, `test`, `regress`. Sin `make`. Vivado batch: versionar `tools/synth_ooc.tcl` desde B-01 (es un script de 10 líneas y evita que la síntesis aislada dependa de clicks); la implementación de B-05 puede quedar en el GUI para M0.

### D-03 · Simulador: Icarus diario, xsim en el cierre

Icarus 12 (`-g2012`) en el runner; xsim obligatorio antes de cerrar M0 y M2. Los TB evitan lo que Icarus no soporta (clases, `assert property`). Regla de los TB: **leer las salidas del DUT en `negedge`** o con `#1` después del `posedge`, nunca en el mismo `always @(posedge)` que las produce (ver H-2 abajo: es exactamente esa carrera).

### D-04 · Estilo: (a), y sí se edita el núcleo

Prefijos `i_`/`o_`/`r_`/`w_`, `` `timescale 1ns/1ps ``, `` `default_nettype none `` … `` `default_nettype wire ``, `(* ASYNC_REG = "TRUE" *)` en el RTL. Se permiten cambios sin efecto funcional en el núcleo, en commits propios, con los TB de módulo dando lo mismo antes y después.

### D-05 · Parámetros: (a)

`baud_gen #(CLOCK_FREQ, BAUD_RATE)`. `OVERSAMPLE` pasa a `localparam OVERSAMPLE = 16` con el comentario "uart_rx/uart_tx cuentan 16 ticks por bit". Hacerlo configurable en RX/TX no lo pide nadie.

### D-06 · Divisor: redondear

`DIV = (CLOCK_FREQ + BAUD_RATE*8) / (BAUD_RATE*16)`. Minimiza el error absoluto, que es lo que ve el receptor de la PC cuando la FPGA transmite. A 50 y 100 MHz (las frecuencias que vamos a usar en M0) da el mismo `DIV` que truncar (27 y 54, +0,47 %), así que el signo negativo solo aparece si la Fase 12 elige 75 o 125 MHz, y para entonces D-07 ya está aplicado. Rango: `$error` en elaboración si `DIV < 2`.

### D-07 · Stop bit a mitad de bit: aplicar

Confirmado leyendo `uart_rx.v`: el conteo de ticks arranca en el flanco de start (no en su centro), así que `STOP → IDLE` con `r_tick_counter == 15` cae a **10,0 bits** del flanco, en el borde con el start siguiente. Con el bit de la FPGA 0,47 % más corto, el margen hacia "emisor rápido" es ≈ 0,4 %, coherente con lo medido (−0,5 % ya falla). Muestrear a mitad de stop (≈ 9,5 bits) lleva la tolerancia a ≈ ±4–5 % por cálculo.

Implementación (un commit, con el caso rojo de B-04 en el mensaje):

- En `STOP`, con `i_baud_tick && r_tick_counter == SAMPLE`: se genera `o_data` y el pulso (`o_valid` u `o_error`, ver D-08).
- Si `w_rx == 1` ahí, `STOP → IDLE`.
- Si `w_rx == 0` (framing error o *break*), se queda esperando `w_rx == 1` antes de volver a `IDLE`. Hace falta un quinto estado (`WAIT_IDLE`), así que `r_state` pasa a 3 bits. Sin esto, un *break* largo se lee como una cadena de bytes `0x00` con error.

`tb_uart_rx.sv` se ajusta solo en el instante esperado del pulso.

### D-08 · Framing error: descartar, en el núcleo

Resolución (a): byte con stop en 0 → pulso `o_error`, **sin** `o_valid`. Cambia el dónde respecto del plan: como D-07 ya reescribe justo las líneas que generan `o_valid`/`o_error`, se resuelve ahí y no con un enmascarado en el wrapper. El wrapper solo renombra (`o_rx_frame_err`). El código `E 04` hacia el host se decide en B-06; v1 lo muestra en un LED.

### D-09 · `interface_rx/tx`: no reutilizar

La máquina de 4 estados de `interface_tx` existe para evitar un doble `start` que el núcleo no produce (ver D-14), e `interface_rx` agrega un ciclo y un buffer de 1 byte que la Debug Unit no necesita. Quedan solo en TP2.

### D-10 · Reset

Activo en alto, síncrono. Se genera una sola vez en el top: `rst_req = btnC | ~locked`, 2 FF con `ASYNC_REG` e `INIT = 1` (el `reg … = 2'b11` de `uart_top.v` de TP2, que es el único valor inicial aceptado). Ningún otro módulo sincroniza reset. El CPU de la pista A usa el mismo puerto `i_reset`.

### D-11 · Baud alto y desvío

Baud alto: correr `CLK/32` (`DIV = 2`, el que usa la Fase 10 para acelerar la simulación) y `CLK/128` (control, el de TP2). Desvío: barrido −2, −1, −0,5, 0, +0,5, +1, +2 %, que deja la regresión de H-1 permanente. El rojo previo a D-07 debe verse en −0,5 % y peor.

### D-12 · Eco: retención de 1 byte

(b) con `--burst` parametrizable y 256 por defecto. A 50 y 100 MHz la FPGA transmite 0,47 % más rápido que el bridge, así que con una retención de 1 byte no debería acumularse atraso; si aparece overrun es un hallazgo sobre el eco, no sobre la UART. FIFO (d) descartada.

### D-13 · Reloj: Clock Wizard generado por script desde una sola variable

**Distinto de la inclinación** (revisada el mismo día). Re-customizar a mano un `.xci` deja cada corrida irreproducible desde un commit, y un `.xci` hecho en Vivado 2025.2 (el del `.xpr`) no abre en 2024.1 (el instalado acá). En su lugar:

- `tools/build_bit.tcl` (flujo **non-project**) recibe `MHZ` y hace todo: `create_ip clk_wiz` en memoria con salida `MHZ` y `locked`, `synth_design -generic CLOCK_FREQ=<MHZ·10⁶>`, place, route, bitstream y reportes. **No se versiona ningún `.xci`.**
- Así cambiar la frecuencia es cambiar **un argumento** (`py tools/run.py bit top_uart_echo --mhz 100`), y el Wizard y el divisor de la UART nunca quedan desalineados (resuelve H-4).
- Las dos corridas de B-05 (50 y 100 MHz) pasan por el Wizard. La Fase 12 barre frecuencias con el mismo argumento.
- Si `create_ip clk_wiz` falla en batch, se usa como alternativa una instancia directa de `MMCME2_BASE` en `$RTL/top/clk_gen.v` con los divisores calculados en el Tcl (B-05 lo detalla).

### D-14 · Contrato de TX: valid/ready, sin detector de flanco (nueva)

B-03 propone un detector de flanco sobre `i_tx_start`. Se descarta. En `uart_tx.v`, `o_busy` se registra con `r_next_state != IDLE` en el mismo flanco que `r_state <= r_next_state`, así que **`o_busy == (r_state != IDLE)` en todo ciclo**: el núcleo ya es un handshake valid/ready (`ready = ~o_busy`) y un `start` nunca se pierde ni se duplica si se respeta la regla. El detector de flanco además introduce un filo nuevo: un `start` que sube mientras `busy = 1` y se sostiene hasta que `busy` baja **no se envía nunca**.

Contrato de `uart_if`:

- Un byte se acepta en el flanco en que `i_tx_start = 1` y `o_tx_busy = 0`; `i_tx_data` se captura ahí.
- `i_tx_start` sostenido = más bytes (semántica valid/ready normal). La Debug Unit pulsa un ciclo por byte.
- `o_tx_busy` vale 1 desde el ciclo siguiente al de aceptación; no hay ventana de doble `start`.

Cambios en B-03/B-04: se borra la tarea 2 de B-03; el caso 9 de B-04 pasa a "`i_tx_start` sostenido N handshakes envía N bytes iguales, sin byte espurio ni corrupto"; el caso 10 verifica `o_tx_busy == 0` exactamente en los ciclos en que la FSM está en reposo.

## Decisiones de los contratos (M1 a M4)

El detalle vive en los contratos; acá queda el porqué. Las marcadas **[A]** obligan al RTL de A y entran en su aprobación de B-06/B-07/B-08.

| ID | Decisión | Dónde | Por qué |
| --- | --- | --- | --- |
| D-15 | Python se invoca con `py` (3.14 ya instalado, con pyserial); runner único `tools/run.py`. Corrige "no hay Python" de la preauditoría | `convenciones.md` §2-3 | `python` es el alias de la Store por el orden del `PATH`; `py` funciona |
| D-16 | Parte `xc7a35tcpg236-1`; Vivado en batch non-project | `convenciones.md` §2 | El `.xpr` tiene `xc7a35ticpg236-1L`, que no es la de la Basys3 |
| D-17 | imem y dmem de 256 palabras; la dirección da la vuelta (`addr[9:2]`) **[A]** | `interfaz_cpu.md` §4-5 | `dbg_mem_addr` de 8 bits en la hoja de ruta; sobra para los programas de prueba |
| D-18 | Accesos desalineados: se ignoran los bits bajos, igual en el ISS **[A]** | `interfaz_cpu.md` §4 | Lo más simple, y la hoja de ruta lo sugiere |
| D-19 | Reset del CPU pone x1-x31 y los dirty en 0; palabra limpia se lee 0 **[A]** | `interfaz_cpu.md` §3-4 | Ejecuciones deterministas iguales al ISS sin ciclo de borrado de dmem |
| D-20 | imem en `system`, inicializada en HALT; `L` rellena con HALT hasta 255 | `interfaz_cpu.md` §5, `protocolo.md` §4 | Responde la pregunta del enunciado sobre reprogramar y el caso sin HALT |
| D-21 | `L` en dos fases (`K` tras `N`, `K` final) | `protocolo.md` §4 | Un `N` inválido se rechaza antes de los datos; sin lógica de descarte |
| D-22 | Byte pendiente de 1 en la Debug Unit; `A` fuera de `R` se ignora | `protocolo.md` §2 | Dos comandos seguidos funcionan; un `A` tardío no genera respuestas extra |
| D-23 | `V` responde `56 01` + tamaños, sin usar `A5` | `protocolo.md` §4 | `A5` queda reservado al dump: la resincronización del host no se confunde |
| D-24 | 16 palabras de latch (la 15 = validez y riesgos), un único layout de info **[A]** | `dump.md` §3 | Un solo decodificador; los bits de stall/flush dibujan el diagrama espacio-tiempo |
| D-25 | Ciclos (W1) los cuenta la Debug Unit: flancos con `en && !halted` | `dump.md` §1 | No depende del CPU; coincide con `r_cycles` del stub |
| D-26 | Formato canónico JSON común a ISS, RTL y placa; `pc` = dirección del HALT | `dump.md` §6 | Una sola comparación para los tres niveles de B-27 |
| D-27 | `system.v` sin reloj ni pines es lo que se simula; los tops de placa solo agregan Wizard, reset y pines | `interfaz_cpu.md` §7 | Los TB no necesitan modelos de IP de Xilinx; `CPU_STUB` elige stub o CPU real |

## Hallazgos resueltos sin decisión

- **H-2 (`FIRST_TICK` 652 vs 651): es del TB, no del RTL.** `tb_baud_gen` lee `o_baud_tick` en el mismo `always @(posedge)` en el que el DUT lo actualiza con `<=`, así que lo ve un ciclo tarde. El período (651) es correcto. Se arregla el TB (leer en `negedge`, regla de D-03), no `baud_gen`.
- **H-7 (nuevo, menor) · `uart_tx` desplaza `o_tx` un ciclo en los bits 1 a 7.** En el tick de fin de bit dentro de `DATA`, `o_tx <= r_shift[0]` usa el valor previo al shift, así que el bit 0 dura 16 ticks + 1 clock y el bit 7, 16 ticks − 1 clock (20 ns sobre 8,68 µs a 50 MHz, inocuo). Se corrige igual en B-03, en commit propio: en ese tick, `o_tx <= r_shift[1]`.

# UART de TP3

## Origen

Copiada de `TP2_UART/src` y `TP2_UART/sim` sin cambios (verificado por hash, los 6 archivos idénticos). Último commit de origen en TP2 (`git log -1 -- TP2_UART/src`): `5aa0c8d54d7060375082bdcbe86a63aa73e370bd`. Commit de la importación en TP3: pendiente (los cambios quedan sin commitear por ahora).

Archivos importados: `baud_gen.v`, `uart_rx.v`, `uart_tx.v` (en `rtl/uart/`) y `tb_baud_gen.sv`, `tb_uart_rx.sv`, `tb_uart_tx.sv` (en `tb/uart/`). No se importan `uart_top.v`, `interface_rx.v`, `interface_tx.v`, `interface_circuit.v` ni `ALU.v` (específicos del protocolo de TP2, D-09).

## Auditoría

| Punto | Esperado | Estado | Evidencia | Arreglo |
| --- | --- | --- | --- | --- |
| Divisor de baudios | Calculado desde `CLOCK_FREQ` y `BAUD_RATE`, redondeado | Parcial: trunca; `OVERSAMPLE` es parámetro pero RX/TX asumen 16 (H-3); `CNTR_WIDTH = 0` si el divisor es 1 | `baud_gen.v` L2-4, L10-11 | B-02 |
| Latencia del tick | Fija y documentada | Sí: `o_baud_tick` sale de un registro, 1 ciclo después de `r_counter == CNTR_MAX`. El `FIRST_TICK` que falla es una carrera del TB (H-2) | `baud_gen.v` L27-37 | B-02 (TB) |
| Muestreo de RX | 16×, centro del bit | Sí: tick 7 de cada bit | `uart_rx.v` L23, L97 | — |
| Sincronizador de RX | 2 FF | Sí, sin `ASYNC_REG` en el RTL (en TP2 estaba en el XDC por nombre de celda) | `uart_rx.v` L16-17, L59-65 | B-03 |
| Inicio falso | Descarta glitches | Sí: si en el tick 7 del start la línea está en 1, vuelve a `IDLE` | `uart_rx.v` L40-41 | B-04 lo prueba |
| Error de framing | Stop en 0 detectado sin falsos positivos | **No (H-1):** el stop se evalúa en el tick 15, a 10,0 bits del flanco de start, en el borde con el start siguiente. Margen hacia emisor rápido ≈ 0,4 %; −0,5 % ya da errores | `uart_rx.v` L51-55, L102-124 | B-04 (D-07) |
| Interfaz RX | `valid` de 1 ciclo, sin `valid` en bytes con error | Parcial: `o_valid` dura 1 ciclo, pero también sube con error de framing, junto con `o_error` | `uart_rx.v` L110-124 | B-04 (D-08) |
| Interfaz TX | Handshake sin pérdidas ni duplicados | Sí: `o_busy == (r_state != IDLE)` en todo ciclo, así que es un valid/ready (`ready = ~o_busy`); `i_start` sostenido envía varios bytes, que es lo esperado (D-14) | `uart_tx.v` L73-79, L81-89 | — |
| Temporización de TX | Bits de igual duración | Parcial (H-7): el bit 0 dura 16 ticks + 1 clock y el bit 7, 16 ticks − 1 clock, porque `o_tx <= r_shift[0]` usa el valor previo al desplazamiento | `uart_tx.v` L67, L86-87 | B-03 |
| Reset | Síncrono, activo en alto | Sí, en todos los `always` | `if (i_reset)` | — |
| Estilo | `timescale`, `default_nettype none`, sin `initial`/`negedge`/`#` | Parcial: faltan `timescale` y `default_nettype`; el resto cumple | los 3 archivos | B-03 |
| Latches / multi-driven | Ninguno | Sí (síntesis OOC, ver abajo) | `build/synth_ooc/*/vivado.log` | — |

Arreglos asignados:

- B-02: divisor redondeado, `OVERSAMPLE` como `localparam`, rechazo de divisor < 2, TB de baud corregido (H-2).
- B-03: `ASYNC_REG`, estilo, H-7, wrapper `uart_if`.
- B-04: D-07 (stop a mitad de bit) y D-08 (sin `valid` en framing), TB automático.

## Línea base de TB (Icarus 12, sin cambios)

Comando: `py TP3_FINAL/tools/run.py tbs` (código de salida 1). Salida: `tbs: 2/3 PASS`.

| TB | PASS | FAIL | Resultado del runner |
| --- | --- | --- | --- |
| tb_uart_rx | 26 | 0 | PASS |
| tb_uart_tx | 22 | 0 | PASS |
| tb_baud_gen | 59 | 1 | FAIL: `FIRST_TICK cycle=652 expected=651` (H-2, error del TB) |

Nota sobre `tb_baud_gen`: 59 y 1 son los contadores del propio TB (línea `Test summary: PASS=59 FAIL=1 TOTAL=60`). El log solo tiene 29 líneas que empiezan con `PASS`: en cada tick el TB cuenta además un PASS silencioso del chequeo de ancho de pulso (`PULSE_WIDTH`) que no imprime. Para rx y tx los contadores coinciden con las líneas del log.

## Síntesis out-of-context (xc7a35tcpg236-1, Vivado 2024.1)

Comando: `py TP3_FINAL/tools/run.py synth_ooc <top>`; los tres dan PASS (sin latches, multi-driven ni implicit nets).

| Módulo | LUT | FF | Latches / multi-driven / implicit |
| --- | --- | --- | --- |
| baud_gen (50 MHz / 115200, por defecto tras B-02; con la versión de TP2, 100 MHz / 9600: 10 LUT, 11 FF) | 5 | 6 | 0 / 0 / 0 |
| uart_rx (tras B-04: 3 bits de estado, `WAIT_IDLE`, stop en el tick `SAMPLE`; antes 13 LUT, 29 FF) | 23 | 30 | 0 / 0 / 0 |
| uart_tx (tras H-7; en TP2 eran 19 LUT) | 20 | 19 | 0 / 0 / 0 |
| uart_if (baud_gen + uart_rx + uart_tx; tras B-04, antes 38 LUT, 54 FF) | 44 | 55 | 0 / 0 / 0 |

## Baud rate

`baud_gen #(CLOCK_FREQ, BAUD_RATE)`. Sobremuestreo fijo de 16 (`localparam`, lo asumen `uart_rx` y `uart_tx`).

DIV = round(CLOCK_FREQ / (BAUD_RATE·16)) = (CLOCK_FREQ + BAUD_RATE·8) / (BAUD_RATE·16), en enteros.
Error = (CLOCK_FREQ / (DIV·16) − BAUD_RATE) / BAUD_RATE. Error positivo = la FPGA transmite más rápido.

| Clock | DIV | Baud real | Error |
| --- | --- | --- | --- |
| 50 MHz | 27 | 115 741 | +0,47 % |
| 75 MHz | 41 | 114 329 | −0,76 % |
| 100 MHz | 54 | 115 741 | +0,47 % |
| 125 MHz | 68 | 114 890 | −0,27 % |

Rango válido: DIV ≥ 2 (con DIV < 2 la elaboración falla con `BAUD_GEN_ERROR_DIVISOR_MENOR_A_2`).
Latencia: el primer tick llega en el flanco número DIV después de soltar el reset y luego uno cada DIV ciclos.
H-2 resuelto: el `FIRST_TICK` de TP2 (652 vs 651) era una carrera del TB, que leía `o_baud_tick` en el mismo
`always @(posedge)` en que el DUT lo actualiza. El TB nuevo lee en `negedge` y mide 651. El RTL no cambió por eso.
Frecuencia final de la Fase 12: <se agrega cuando se elija>.

## Interfaz

Módulo `uart_if #(CLOCK_FREQ, BAUD_RATE)` en `rtl/uart/uart_if.v`. Es el único punto de instanciación de
`baud_gen`, `uart_rx` y `uart_tx`.

| Puerto | Dir | Regla |
| --- | --- | --- |
| `i_clock` | in | Reloj del sistema |
| `i_reset` | in | Síncrono, activo en alto, ya sincronizado. Con reset: `o_tx = 1`, `o_tx_busy = 0`, sin pulsos de RX |
| `i_rx` | in | Línea serie asíncrona; se sincroniza adentro (2 FF, `ASYNC_REG`) |
| `o_tx` | out | Línea serie; 1 en reposo |
| `i_tx_start` | in | "valid" del handshake de TX |
| `i_tx_data[7:0]` | in | Se captura en el flanco que acepta el byte |
| `o_tx_busy` | out | "not ready". Vale `1` exactamente mientras el transmisor no está en reposo |
| `o_rx_valid` | out | 1 ciclo por byte bueno |
| `o_rx_data[7:0]` | out | Válido en el ciclo de `o_rx_valid` |
| `o_rx_frame_err` | out | 1 ciclo por byte con stop en 0, sin `o_rx_valid` (desde B-04) |

Reglas de TX (D-14):
- Un byte se acepta en el flanco en que `i_tx_start = 1` y `o_tx_busy = 0`.
- `o_tx_busy` vale 1 desde el ciclo siguiente al de aceptación hasta que termina el stop bit. No hay ventana para un doble start.
- `i_tx_start` sostenido envía un byte por cada aceptación (semántica valid/ready). Para enviar un solo byte, pulsar un ciclo.
- `i_tx_start` con `o_tx_busy = 1` no tiene efecto ni corrompe el byte en curso.

Sin FIFO: un byte por vez en cada sentido. Si el consumidor no atiende `o_rx_valid` en ese ciclo, el byte se pierde.

H-7 corregido en `uart_tx`: en el tick de fin de bit dentro de `DATA`, `o_tx` toma `r_shift[1]` (el bit siguiente) en vez de
`r_shift[0]`. Medido con un TB temporal (tick cada 4 clocks, dato `8'h55`): antes el bit 0 duraba 65 clocks y el bit 7, 63;
ahora los 8 bits duran 64. Los TB de TP2 no lo detectan (muestrean a mitad de bit).

## Verificación

Comando: `py TP3_FINAL/tools/run.py tbs` (6/6 PASS). TB de sistema: `tb_uart` (módulo `tb_uart`, 11 casos, sobre `uart_if`) con la BFM `tb/common/uart_bfm.svh`, que pone y decodifica tramas con tiempos reales de bit, independientes del DUT. `tb_uart_fast32` y `tb_uart_fast128` son el mismo TB con `BAUD_RATE` = 50 MHz / 32 (DIV = 2) y 50 MHz / 128 (DIV = 8).

| # | Caso | Estímulo | Verifica |
| --- | --- | --- | --- |
| 1 | 256 valores | RX: bytes `(m + 5) % 256` con 1 bit de pausa. TX: 0..255 por handshake | Los 256 de RX y de TX coinciden |
| 2 | 64 seguidos | Sin pausa entre stop y start, emisor ideal | 64 recibidos, en orden, sin framing |
| 3 | Desvío | Caso 2 con −2, −1, −0,5, 0, +0,5, +1, +2 % de período de bit | Igual que el caso 2 en los 7 |
| 4 | Glitch | 0 durante ¼ de bit en reposo | Sin pulsos; el byte siguiente llega bien |
| 5 | Reset en trama | Reset a 4,5 bits de un byte RX y a 3,5 bits de un byte TX | Sin pulsos espurios; `o_tx = 1` y `o_tx_busy = 0` con reset; el byte siguiente llega bien |
| 6 | Baud alto | Todo el TB con `CLK/32` y `CLK/128` | Mismo resultado |
| 7 | Stop en 0 | Trama con stop en 0 | 1 pulso de `o_rx_frame_err`, ningún `o_rx_valid`; el byte siguiente llega bien |
| 8 | Start con busy | `i_tx_start` con `o_tx_busy = 1` | El byte en curso sale intacto y no sale otro |
| 9 | Start sostenido | `i_tx_start` en 1 durante 3 aceptaciones | Exactamente 3 bytes |
| 10 | Aserciones por ciclo | Monitor en cada ciclo | `o_rx_valid` de 1 ciclo y nunca junto con `o_rx_frame_err`; `o_tx_busy == (TX fuera de IDLE)`; `o_tx_busy` sube tras aceptar |
| 11 | Dato cambia tras aceptar | `i_tx_data` cambia justo después de la aceptación | Sale el byte capturado |

### Antes del arreglo (`uart_rx` de B-03, sin tocar)

`py TP3_FINAL/tools/run.py tb tb_uart` falla (252 errores; los casos 1, 2, 4, 5, 8, 9, 11 y C3 con 0 y +ppm no fallan):

```text
  140 FAIL C10: o_rx_valid y o_rx_frame_err en el mismo ciclo
    1 FAIL C3 -5000 ppm: 60 errores de framing
    1 FAIL C3 -10000 ppm: 47 errores de framing
    1 FAIL C3 -10000 ppm: recibidos N de 64
    5 FAIL C3 -10000 ppm: byte K (esperado/recibido)
    1 FAIL C3 -20000 ppm: 32 errores de framing
    1 FAIL C3 -20000 ppm: recibidos N de 64
    5 FAIL C3 -20000 ppm: byte K (esperado/recibido)
    1 FAIL C7: hubo o_rx_valid con stop en 0
```

Causa (H-1, D-07, D-08): el stop se evaluaba en el tick 15 (≈ 10,0 bits), sin margen frente a un emisor más rápido; y un framing error generaba `o_rx_valid` junto con `o_error`.

### Después del arreglo

```text
PASS tb_baud_gen: 215 chequeos
PASS tb_uart_rx: 25 chequeos
PASS tb_uart_tx: 22 chequeos
PASS tb_uart: 1064 chequeos
PASS tb_uart: 1064 chequeos   (tb_uart_fast32)
PASS tb_uart: 1064 chequeos   (tb_uart_fast128)
```

Qué cambió en `uart_rx.v`: `r_state` de 2 a 3 bits; estado nuevo `WAIT_IDLE`; `STOP -> IDLE` en el tick `SAMPLE` (centro del stop, ≈ 9,5 bits) en vez del 15; `o_data`, `o_valid` y `o_error` se generan en ese mismo tick; con stop en 0 solo se pulsa `o_error` (sin `o_valid`) y se espera la línea en 1 antes de volver a IDLE.

### Mutaciones

`py TP3_FINAL/tools/run.py mutate` copia el archivo a `build/mut/<nombre>/`, aplica el reemplazo y exige que el TB falle. Mutaciones: `tx_orden_bits` (`r_shift >> 1` por `<< 1` en `uart_tx.v`) y `rx_muestreo_tarde` (`SAMPLE = 4'd7` por `4'd14` en `uart_rx.v`). Resultado: las dos `detectada` (el TB falla en C1 TX y en C3 -20000 ppm respectivamente).

## Resultados en placa

Basys3 por USB (COM7), `top_uart_echo`, Clock Wizard creado por `build_bit.tcl` (`--clk wiz`), `echo_test.py` a 115200 baud, semilla 1. Programación con `py TP3_FINAL/tools/run.py program <bit>`. Fecha de todas las corridas: 2026-11-01. Commit de los bitstreams: `e1261f2` más los archivos de B-05 todavía sin commitear (actualizar con el hash del commit de B-05).

| Clock | Reloj | DIV | Error baud | Ráfaga | Enviados | Recibidos | Errados | Perdidos | Tiempo | WNS | WHS | LUT | FF | Fecha | Commit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| wiz | 50 MHz | 27 | +0,47 % | 256 | 100000 | 100000 | 0 | 0 | 12,7 s | 16,581 | 0,160 | 48 | 69 | 2026-11-01 | e1261f2 + B-05 |
| wiz | 50 MHz | 27 | +0,47 % | 1 | 4096 | 4096 | 0 | 0 | 65,8 s | 16,581 | 0,160 | 48 | 69 | 2026-11-01 | e1261f2 + B-05 |
| wiz | 50 MHz | 27 | +0,47 % | 16 | 4096 | 4096 | 0 | 0 | 4,3 s | 16,581 | 0,160 | 48 | 69 | 2026-11-01 | e1261f2 + B-05 |
| wiz | 50 MHz | 27 | +0,47 % | 256 | 4096 | 4096 | 0 | 0 | 0,7 s | 16,581 | 0,160 | 48 | 69 | 2026-11-01 | e1261f2 + B-05 |
| wiz | 50 MHz | 27 | PC a 57600 (rota a propósito) | 256 | 1000 | 505 | 501 | 495 | 3,1 s | 16,581 | 0,160 | 48 | 69 | 2026-11-01 | e1261f2 + B-05 |
| wiz | 100 MHz | 54 | +0,47 % | 256 | 100000 | 100000 | 0 | 0 | 12,7 s | 6,097 | 0,131 | 49 | 70 | 2026-11-01 | e1261f2 + B-05 |

LED (LD0 a LD3, `o_led[3:0]`): LD3 (`locked`) encendido en todas las corridas. LD0 (conmuta por byte recibido) parpadea y termina apagado cuando la cantidad de bytes es par (100000 y 4096); LD1 (framing) y LD2 (overrun) quedaron apagados en todas las corridas buenas, incluida la ráfaga de 256. En la corrida a 57600 LD0 parpadeó y terminó encendido, y LD1 (framing, sticky) se encendió y no se apagó; btnC los apagó. El Clock Wizard por script funcionó (no se usó `mmcm`).

## Estado

UART reutilizada de TP2 con cambios: divisor redondeado y OVERSAMPLE fijo (0877287), estilo y ASYNC_REG (9082460), H-7 en uart_tx (9082460), stop a mitad de bit y framing sin valid en uart_rx (e1261f2).
Validada en placa a 50 y 100 MHz con 100 000 bytes de eco sin errores ni pérdidas.

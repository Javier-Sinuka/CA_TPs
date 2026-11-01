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
| baud_gen (100 MHz / 9600, por defecto) | 10 | 11 | 0 / 0 / 0 |
| uart_rx | 13 | 29 | 0 / 0 / 0 |
| uart_tx | 19 | 19 | 0 / 0 / 0 |

## Baud rate

Pendiente (B-02).

## Interfaz

Pendiente (B-03).

## Verificación

Pendiente (B-04).

## Resultados en placa

Pendiente (B-05).

## Estado

Pendiente (B-05).

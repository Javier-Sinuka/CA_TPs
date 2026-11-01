# B-03 · Wrapper `uart_if`, estilo, `ASYNC_REG` y H-7

`S` · etiquetas `uart` · milestone M0 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

Un `uart_if.v` que es el único punto de instanciación de la UART, con el contrato valid/ready de D-14, y el núcleo con estilo de `convenciones.md` §4, `ASYNC_REG` en el RTL y la corrección de H-7 en `uart_tx`.

## Antes de empezar

- Leer: [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §4, §5, §7; [`decisiones.md`](../../../TP3_FINAL/doc/documentation/decisiones.md) D-04, D-08, D-09, D-10, D-14 y H-7.
- Precondiciones: B-01 cerrado. B-02 puede estar en curso (toca otros archivos).
- Rama: `b/B-03-uart-if`.
- **Importante:** el cambio de framing (D-08: byte con stop en 0 → `o_rx_frame_err` **sin** `o_rx_valid`) **no** se hace acá. Se hace en `uart_rx.v` junto con D-07, en B-04. En este issue `uart_if` solo renombra `o_error` → `o_rx_frame_err`; mientras B-04 no esté cerrado, un byte con error de framing todavía produce `o_rx_valid` y `o_rx_frame_err` en el mismo ciclo.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_rx.v` | estilo (commit 1) y `ASYNC_REG` (commit 2) |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_tx.v` | estilo (commit 1) y H-7 (commit 3) |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_if.v` | paso 4 (commit 4) |
| modificar | `TP3_FINAL/tools/tbs.py` | `SYNTH["uart_if"]` |
| modificar | `TP3_FINAL/doc/documentation/uart.md` | sección "Interfaz" |
| no tocar | `baud_gen.v` (es de B-02), los TB | |

Después de **cada** commit: `py TP3_FINAL/tools/run.py tb tb_uart_rx` y `py TP3_FINAL/tools/run.py tb tb_uart_tx` tienen que dar PASS y los conteos `grep -c "^PASS" TP3_FINAL/build/tb_uart_rx.log` = 26 y `tb_uart_tx.log` = 22 (los de la línea base de `uart.md`).

## Pasos

1. **Estilo (commit 1, sin efecto funcional).** En `uart_rx.v` y `uart_tx.v`:
   - Agregar como primeras dos líneas `` `timescale 1ns/1ps `` y `` `default_nettype none ``, y una línea en blanco.
   - Agregar después de `endmodule` una línea en blanco y `` `default_nettype wire ``.
   - Nada más. No renombrar señales ni reformatear.

   Verificar: los dos TB en PASS con los mismos conteos; `iverilog -g2012 -Wall -o TP3_FINAL/build/lint.vvp TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_rx.v TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_tx.v` sin errores.

2. **`ASYNC_REG` (commit 2, sin efecto funcional).** En `uart_rx.v`, reemplazar

   ```verilog
       reg [1:0] r_rx_sync;
   ```

   por

   ```verilog
       // Sincronizador de la entrada asíncrona: 2 FF juntos en el mismo slice.
       (* ASYNC_REG = "TRUE" *) reg [1:0] r_rx_sync;
   ```

   Verificar: TB iguales. `py TP3_FINAL/tools/run.py synth_ooc uart_rx` → PASS, y `grep -i "ASYNC_REG" TP3_FINAL/build/synth_ooc/uart_rx/vivado.log` no muestra warnings de atributo desconocido.

3. **H-7 (commit 3, cambio funcional mínimo).** En `uart_tx.v`, dentro del `case (r_next_state)` del bloque de `o_tx`, reemplazar la línea

   ```verilog
                   DATA: begin o_tx <= r_shift[0]; end
   ```

   por

   ```verilog
                   // En el tick de fin de bit r_shift todavía no se desplazó: el bit siguiente es r_shift[1] (H-7).
                   DATA: begin
                       if (r_state == DATA && i_baud_tick && r_tick_counter == 15) begin
                           o_tx <= r_shift[1];
                       end else begin
                           o_tx <= r_shift[0];
                       end
                   end
   ```

   Por qué es correcto: al pasar de `START` a `DATA` `r_state` es `START`, así que se usa `r_shift[0]` (bit 0, como antes). En el tick final de un bit dentro de `DATA` con `r_next_state = DATA`, `r_shift` se desplaza en ese mismo flanco, así que el bit siguiente es el `r_shift[1]` actual. En el último bit `r_next_state = STOP` y esta rama no se ejecuta. Resultado: los 8 bits duran exactamente 16 ticks.

   Verificar: `tb_uart_tx` en PASS con 22 chequeos (muestrea a mitad de bit, el cambio de 1 clock no lo afecta).

4. **`uart_if.v` (commit 4).** Crear con exactamente:

   ```verilog
   `timescale 1ns/1ps
   `default_nettype none

   // Única forma de instanciar la UART en TP3 (D-01, D-09).
   // TX: handshake valid/ready (D-14). Un byte se acepta en el flanco en que
   //     i_tx_start = 1 y o_tx_busy = 0; i_tx_data se captura ahí. Mantener
   //     i_tx_start en 1 envía un byte por cada aceptación.
   // RX: o_rx_valid dura 1 ciclo por byte; o_rx_data es válido en ese ciclo.
   //     o_rx_frame_err dura 1 ciclo por byte con stop en 0 (D-08, desde B-04 sin o_rx_valid).
   // i_reset: síncrono, activo en alto, ya sincronizado por el top (D-10).
   module uart_if #(
       parameter integer CLOCK_FREQ = 50_000_000,
       parameter integer BAUD_RATE  = 115_200
   )(
       input  wire       i_clock,
       input  wire       i_reset,
       input  wire       i_rx,
       output wire       o_tx,
       input  wire       i_tx_start,
       input  wire [7:0] i_tx_data,
       output wire       o_tx_busy,
       output wire       o_rx_valid,
       output wire [7:0] o_rx_data,
       output wire       o_rx_frame_err
   );
       wire w_baud_tick;

       baud_gen #(
           .CLOCK_FREQ(CLOCK_FREQ),
           .BAUD_RATE(BAUD_RATE)
       ) u_baud (
           .i_reset(i_reset),
           .i_clock(i_clock),
           .o_baud_tick(w_baud_tick)
       );

       uart_rx u_rx (
           .i_clock(i_clock),
           .i_baud_tick(w_baud_tick),
           .i_reset(i_reset),
           .i_rx(i_rx),
           .o_valid(o_rx_valid),
           .o_data(o_rx_data),
           .o_error(o_rx_frame_err)
       );

       uart_tx u_tx (
           .i_clock(i_clock),
           .i_baud_tick(w_baud_tick),
           .i_reset(i_reset),
           .i_start(i_tx_start),
           .i_data(i_tx_data),
           .o_busy(o_tx_busy),
           .o_tx(o_tx)
       );
   endmodule

   `default_nettype wire
   ```

   Nombres de instancia fijos (`u_baud`, `u_rx`, `u_tx`): los usan B-04 y los XDC.

   En `TP3_FINAL/tools/tbs.py`, agregar a `SYNTH`:

   ```python
       "uart_if": [f"{RTL}/uart/baud_gen.v", f"{RTL}/uart/uart_rx.v",
                   f"{RTL}/uart/uart_tx.v", f"{RTL}/uart/uart_if.v"],
   ```

   Verificar:
   - `iverilog -g2012 -Wall -o TP3_FINAL/build/lint.vvp -s uart_if TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/baud_gen.v TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_rx.v TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_tx.v TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_if.v` → sin errores ni warnings de cables implícitos o anchos.
   - `py TP3_FINAL/tools/run.py synth_ooc uart_if` → PASS.

5. **Reset.** Confirmar leyendo los tres archivos que todos los `always` son `@(posedge i_clock)` con `if (i_reset)` adentro y que no hay `negedge` ni `initial`. No hay nada que cambiar; anotar "verificado" en el PR.

6. **`uart.md`, sección "Interfaz".** Reemplazar `Pendiente (B-03).` por:

   ```markdown
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
   ```

## Validación

```bash
py TP3_FINAL/tools/run.py tb tb_uart_rx       # PASS (26 líneas PASS en el log)
py TP3_FINAL/tools/run.py tb tb_uart_tx       # PASS (22 líneas PASS en el log)
py TP3_FINAL/tools/run.py synth_ooc uart_rx    # PASS
py TP3_FINAL/tools/run.py synth_ooc uart_tx    # PASS
py TP3_FINAL/tools/run.py synth_ooc uart_if    # PASS
git log --oneline -5                           # los 5 commits de abajo, en ese orden
```

## Listo cuando

- [ ] Los commits 1 y 2 no cambian ningún conteo de PASS de `tb_uart_rx` (26) ni `tb_uart_tx` (22).
- [ ] El commit 3 cambia solo el bloque de `o_tx` de `uart_tx.v` y `tb_uart_tx` sigue en 22 PASS.
- [ ] `uart_if.v` existe con los puertos y nombres de instancia exactos del paso 4 y sintetiza sin latches, multi-driven ni implicit.
- [ ] `uart.md` tiene la sección "Interfaz".

## No hacer

- No agregar detector de flanco a `i_tx_start` (D-14 lo descartó).
- No enmascarar `o_rx_valid` con `o_error` en el wrapper (D-08 se resuelve en `uart_rx`, en B-04).
- No tocar el muestreo del stop (B-04).
- No agregar sincronizador de reset en `uart_if` (D-10).
- No mezclar los cambios de estilo con el de H-7 en el mismo commit.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| Con `default_nettype none` un TB de TP2 deja de compilar por un cable implícito | El cable implícito está en el TB: declararlo en el TB con el ancho correcto, en el mismo commit 1, y anotarlo en el PR |
| `tb_uart_tx` falla después del commit 3 | Revisar que la condición sea `r_state == DATA` (no `r_next_state`). Si sigue fallando, detenerse y preguntar |
| Icarus avisa `baud_gen` sin parámetro `OVERSAMPLE` | B-02 todavía no está mergeado y no importa: el `baud_gen` viejo tiene `OVERSAMPLE = 16` por defecto. No pasar el parámetro |
| `synth_ooc uart_if` falla por `uart_if` sin puertos conectados a pines | No debería en `-mode out_of_context`; detenerse y preguntar |

## Commits

1. `uart: estilo (timescale, default_nettype) sin cambio funcional`
2. `uart: ASYNC_REG en el sincronizador de RX`
3. `uart: tx sin desfase de 1 clock entre bits (H-7)`
4. `uart: wrapper uart_if con handshake valid/ready`
5. `docs: sección Interfaz de uart.md`

## Depende de / bloquea

Depende de: B-01.
Bloquea: B-04, B-05, B-10.

# B-02 · Divisor de baudios redondeado y TB de `baud_gen`

`S` · etiquetas `uart` · milestone M0 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

`baud_gen` con dos parámetros (`CLOCK_FREQ`, `BAUD_RATE`), divisor redondeado, rechazo de divisores menores a 2, y un `tb_baud_gen` nuevo que verifica 50, 75, 100 y 125 MHz a 115200 con error < 2 %.

## Antes de empezar

- Leer: [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §3, §4, §5; [`decisiones.md`](../../../TP3_FINAL/doc/documentation/decisiones.md) D-05, D-06 y H-2.
- Precondiciones: B-01 cerrado (`py TP3_FINAL/tools/run.py tb tb_uart_rx` da PASS).
- Rama: `b/B-02-baud`.
- B-03 trabaja en paralelo sobre `uart_rx.v`, `uart_tx.v` y `uart_if.v`: este issue no toca esos archivos.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| reescribir | `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/baud_gen.v` | paso 1 |
| reescribir | `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_baud_gen.sv` | paso 3 |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_baud_div1.sv` | paso 2 (TB que **debe** no compilar) |
| modificar | `TP3_FINAL/tools/tbs.py` | `tb_baud_gen` sin `legacy` |
| modificar | `TP3_FINAL/doc/documentation/uart.md` | sección "Baud rate" |

## Pasos

1. **`baud_gen.v`.** Reemplazar el archivo completo por:

   ```verilog
   `timescale 1ns/1ps
   `default_nettype none

   module baud_gen #(
       parameter integer CLOCK_FREQ = 50_000_000,
       parameter integer BAUD_RATE  = 115_200
   )(
       input  wire i_reset,
       input  wire i_clock,
       output reg  o_baud_tick
   );
       // uart_rx y uart_tx cuentan 16 ticks por bit: no cambiar sin cambiarlos a ellos.
       localparam integer OVERSAMPLE = 16;
       // Divisor redondeado al entero más cercano (D-06).
       localparam integer DIV        = (CLOCK_FREQ + (BAUD_RATE * OVERSAMPLE) / 2) / (BAUD_RATE * OVERSAMPLE);
       localparam integer CNTR_MAX   = DIV - 1;
       localparam integer CNTR_WIDTH = (DIV < 2) ? 1 : $clog2(DIV);

       // Un divisor menor a 2 no da un tick de un ciclo separado de otro: se rechaza en elaboración
       // instanciando un módulo que no existe (falla igual en Icarus y en Vivado).
       generate
           if (DIV < 2) begin : g_div_check
               BAUD_GEN_ERROR_DIVISOR_MENOR_A_2 u_error ();
           end
       endgenerate

       reg [CNTR_WIDTH-1:0] r_counter;

       always @(posedge i_clock) begin
           if (i_reset) begin
               r_counter <= {CNTR_WIDTH{1'b0}};
           end else if (r_counter == CNTR_MAX[CNTR_WIDTH-1:0]) begin
               r_counter <= {CNTR_WIDTH{1'b0}};
           end else begin
               r_counter <= r_counter + 1'b1;
           end
       end

       // El tick sale registrado: aparece 1 ciclo después de r_counter == CNTR_MAX.
       // Primer tick: en el flanco número DIV después de soltar el reset.
       always @(posedge i_clock) begin
           if (i_reset) begin
               o_baud_tick <= 1'b0;
           end else begin
               o_baud_tick <= (r_counter == CNTR_MAX[CNTR_WIDTH-1:0]);
           end
       end
   endmodule

   `default_nettype wire
   ```

   Nota: `$clog2(DIV)` es el ancho para contar de 0 a `DIV − 1` (es lo mismo que el `$clog2(CNTR_MAX + 1)` original).

2. **TB que no compila.** Crear `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_baud_div1.sv`:

   ```systemverilog
   `timescale 1ns/1ps
   // Este TB NO debe compilar: DIV = 1. Lo usa el paso 2 de B-02 a mano; no va en TBS.
   module tb_baud_div1;
       reg r_clock = 1'b0, r_reset = 1'b1;
       wire w_tick;
       baud_gen #(.CLOCK_FREQ(16_000_000), .BAUD_RATE(1_000_000)) u_dut (
           .i_reset(r_reset), .i_clock(r_clock), .o_baud_tick(w_tick));
   endmodule
   ```

   Verificar:

   ```bash
   iverilog -g2012 -o TP3_FINAL/build/div1.vvp TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/baud_gen.v TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_baud_div1.sv
   ```

   → código distinto de 0 y un mensaje que contiene `BAUD_GEN_ERROR_DIVISOR_MENOR_A_2`. Pegar el mensaje en el PR.

3. **`tb_baud_gen.sv`.** Reemplazar el archivo completo por:

   ```systemverilog
   `timescale 1ns/1ps

   // Mide el período del tick de baud_gen para varias frecuencias de reloj.
   // Cada instancia de baud_check tiene su propio reloj y su propio DUT.
   module baud_check #(
       parameter integer CLOCK_FREQ = 50_000_000,
       parameter integer BAUD_RATE  = 115_200,
       parameter integer EXP_DIV    = 27,
       parameter integer N_PERIODS  = 20
   )();
       localparam real HALF_NS = 1.0e9 / CLOCK_FREQ / 2.0;
       reg  r_clock = 1'b0;
       reg  r_reset = 1'b1;
       wire w_tick;
       integer errors = 0;
       integer checks = 0;
       reg     done = 1'b0;
       integer cycle, last, periods, first;
       real    err_pct;

       always #(HALF_NS) r_clock = ~r_clock;

       baud_gen #(.CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(BAUD_RATE)) u_dut (
           .i_reset(r_reset), .i_clock(r_clock), .o_baud_tick(w_tick));

       initial begin
           cycle = 0; last = -1; periods = 0; first = -1;
           repeat (4) @(posedge r_clock);
           @(negedge r_clock);
           r_reset = 1'b0;
           // cycle = cantidad de flancos de subida desde que se soltó el reset.
           while (periods < N_PERIODS) begin
               @(posedge r_clock);
               cycle = cycle + 1;
               @(negedge r_clock);          // leer lejos del flanco (convenciones §5)
               if (w_tick) begin
                   if (first < 0) begin
                       first = cycle;
                       checks = checks + 1;
                       if (first != EXP_DIV) begin
                           errors = errors + 1;
                           $display("FAIL FIRST_TICK CLK=%0d: ciclo %0d, esperado %0d", CLOCK_FREQ, first, EXP_DIV);
                       end
                   end else begin
                       periods = periods + 1;
                       checks = checks + 1;
                       if (cycle - last != EXP_DIV) begin
                           errors = errors + 1;
                           $display("FAIL PERIOD CLK=%0d: %0d ciclos, esperado %0d", CLOCK_FREQ, cycle - last, EXP_DIV);
                       end
                   end
                   last = cycle;
                   // El tick dura exactamente 1 ciclo.
                   @(posedge r_clock);
                   cycle = cycle + 1;
                   @(negedge r_clock);
                   checks = checks + 1;
                   if (w_tick) begin
                       errors = errors + 1;
                       $display("FAIL PULSE_WIDTH CLK=%0d: tick de más de 1 ciclo", CLOCK_FREQ);
                   end
               end
           end
           err_pct = (CLOCK_FREQ / (EXP_DIV * 16.0) - BAUD_RATE) * 100.0 / BAUD_RATE;
           checks = checks + 1;
           if (err_pct > 2.0 || err_pct < -2.0) begin
               errors = errors + 1;
               $display("FAIL ERROR CLK=%0d: error de baudios %0.3f %%", CLOCK_FREQ, err_pct);
           end
           $display("CLK=%0d BAUD=%0d DIV=%0d err=%0.3f%%", CLOCK_FREQ, BAUD_RATE, EXP_DIV, err_pct);
           done = 1'b1;
       end
   endmodule

   module tb_baud_gen;
       // DIV esperado = round(CLOCK_FREQ / (BAUD_RATE * 16)), calculado a mano (no con la fórmula del RTL).
       baud_check #(.CLOCK_FREQ( 50_000_000), .BAUD_RATE(115_200), .EXP_DIV( 27)) c50  ();
       baud_check #(.CLOCK_FREQ( 75_000_000), .BAUD_RATE(115_200), .EXP_DIV( 41)) c75  ();
       baud_check #(.CLOCK_FREQ(100_000_000), .BAUD_RATE(115_200), .EXP_DIV( 54)) c100 ();
       baud_check #(.CLOCK_FREQ(125_000_000), .BAUD_RATE(115_200), .EXP_DIV( 68)) c125 ();
       baud_check #(.CLOCK_FREQ(100_000_000), .BAUD_RATE(  9_600), .EXP_DIV(651)) c9600();

       integer errors, checks;

       initial begin
           #(50_000_000);   // watchdog: 50 ms simulados (lo esperado es < 3 ms)
           $fatal(1, "FAIL tb_baud_gen: watchdog");
       end

       initial begin
           wait (c50.done && c75.done && c100.done && c125.done && c9600.done);
           errors = c50.errors + c75.errors + c100.errors + c125.errors + c9600.errors;
           checks = c50.checks + c75.checks + c100.checks + c125.checks + c9600.checks;
           if (errors != 0) $fatal(1, "FAIL tb_baud_gen: %0d errores", errors);
           $display("PASS tb_baud_gen: %0d chequeos", checks);
           $finish;
       end
   endmodule
   ```

   En `TP3_FINAL/tools/tbs.py`, en la entrada `tb_baud_gen`, borrar `"legacy": True,`.

   Verificar: `py TP3_FINAL/tools/run.py tb tb_baud_gen` → `PASS tb_baud_gen`. El log contiene exactamente estas 5 líneas de resumen (el orden puede variar):

   ```
   CLK=50000000 BAUD=115200 DIV=27 err=0.469%
   CLK=75000000 BAUD=115200 DIV=41 err=-0.756%
   CLK=100000000 BAUD=115200 DIV=54 err=0.469%
   CLK=125000000 BAUD=115200 DIV=68 err=-0.269%
   CLK=100000000 BAUD=9600 DIV=651 err=0.006%
   ```

   y `PASS tb_baud_gen: 215 chequeos` (5 instancias × (1 primer tick + 20 períodos + 21 anchos de pulso + 1 error)).

4. **Prueba de que el TB detecta un divisor mal calculado.** Cambiar temporalmente en `baud_gen.v` `(BAUD_RATE * OVERSAMPLE) / 2` por `0` (vuelve a truncar). Correr `py TP3_FINAL/tools/run.py tb tb_baud_gen` → `FAIL`, con líneas `FAIL PERIOD CLK=75000000` y `FAIL PERIOD CLK=125000000`. **Revertir** el cambio (`git checkout -- TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/baud_gen.v` antes de commitear el paso 1, o deshacerlo a mano) y volver a ver PASS.

5. **Síntesis.** `py TP3_FINAL/tools/run.py synth_ooc baud_gen` → PASS.

6. **`uart.md`, sección "Baud rate".** Reemplazar `Pendiente (B-02).` por:

   ```markdown
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
   ```

## Validación

```bash
py TP3_FINAL/tools/run.py tb tb_baud_gen     # PASS tb_baud_gen: 215 chequeos
py TP3_FINAL/tools/run.py tbs                # 3/3 PASS
py TP3_FINAL/tools/run.py synth_ooc baud_gen # PASS
```

## Listo cuando

- [ ] `tb_baud_gen` pasa con las 5 líneas de resumen del paso 3 y sin la marca `legacy`.
- [ ] El paso 4 (truncar) hizo fallar el TB y el cambio está revertido.
- [ ] El paso 2 no compila y el mensaje nombra `BAUD_GEN_ERROR_DIVISOR_MENOR_A_2`.
- [ ] `run.py tbs` da `3/3 PASS` (los TB de RX y TX de TP2 no instancian `baud_gen`, así que no cambian).
- [ ] `uart.md` tiene la sección "Baud rate" completa.

## No hacer

- No tocar `uart_rx.v`, `uart_tx.v` ni `uart_if.v` (B-03).
- No volver a exponer `OVERSAMPLE` como `parameter`.
- No agregar `tb_baud_div1` a `TBS`.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| Icarus da error de sintaxis en `CNTR_MAX[CNTR_WIDTH-1:0]` (part-select de un `localparam integer`) | Reemplazar en las dos comparaciones por `r_counter == CNTR_MAX` y repetir. Si con eso aparece un warning de ancho con `-Wall`, dejarlo y anotarlo en el PR |
| El paso 2 compila sin error | Detenerse y preguntar (el `generate` no se está evaluando) |
| `FIRST_TICK` sale `EXP_DIV + 1` | El TB está leyendo en el flanco: verificar que la lectura de `w_tick` esté después de `@(negedge r_clock)`. No cambiar `EXP_DIV` |
| Las líneas `err=` difieren en el tercer decimal | Aceptable si el signo y los dos primeros decimales coinciden; pegar la salida real en `uart.md` |
| Cualquier otro `FAIL PERIOD` | Detenerse y preguntar |

## Commits

1. `uart: divisor de baudios redondeado y OVERSAMPLE fijo en 16`
2. `uart: tb_baud_gen por frecuencia, leyendo en negedge (H-2)`
3. `docs: sección Baud rate de uart.md`

## Depende de / bloquea

Depende de: B-01.
Bloquea: B-04, B-05.

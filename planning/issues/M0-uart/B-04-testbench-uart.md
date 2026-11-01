# B-04 · TB automático de la UART, H-1 (stop a mitad de bit) y mutaciones

`M` · etiquetas `uart` `test` · milestone M0 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

`tb_uart.sv` contra `uart_if` que pasa los 11 casos a 115200 y con baud alto, la BFM reutilizable `uart_bfm.svh`, la evidencia de H-1 antes y después del arreglo de `uart_rx` (D-07 + D-08), los TB de módulo terminando en `$fatal`/`PASS`, y el objetivo `mutate` del runner.

## Antes de empezar

- Leer: [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §3, §4, §5; [`decisiones.md`](../../../TP3_FINAL/doc/documentation/decisiones.md) D-03, D-07, D-08, D-11, D-14; la sección "Interfaz" de `TP3_FINAL/doc/documentation/uart.md` (la escribió B-03).
- Precondiciones: B-02 y B-03 cerrados. Comprobar: `py TP3_FINAL/tools/run.py tbs` → `3/3 PASS`; existe `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_if.v`.
- Rama: `b/B-04-tb-uart`.
- El orden de los pasos es obligatorio: **primero** el TB en rojo contra el `uart_rx` actual, **después** el arreglo.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/common/uart_bfm.svh` | paso 1 |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_uart.sv` | paso 2 |
| modificar | `TP3_FINAL/tools/run.py` | objetivo `mutate` (paso 8) |
| modificar | `TP3_FINAL/tools/tbs.py` | entradas `tb_uart*`, sin `legacy`, `MUTATIONS` |
| reescribir | `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_rx.v` | paso 5 |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_uart_rx.sv` | caso T5 y final (paso 6) |
| modificar | `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_uart_tx.sv` | final (paso 6) |
| modificar | `TP3_FINAL/doc/documentation/uart.md` | sección "Verificación" |

## Pasos

1. **BFM.** Crear `TP3_FINAL/VIVADO/TP_FINAL/tb/common/uart_bfm.svh` con exactamente (la API la usan B-16 y B-28; no cambiar nombres):

   ```systemverilog
   // uart_bfm.svh: modelo de la PC en la línea serie (8N1, LSB primero).
   // Se incluye DENTRO de un módulo de TB que declara antes del include:
   //     reg  bfm_rx = 1'b1;   // conectado a i_rx del DUT
   //     wire bfm_tx;          // conectado a o_tx del DUT
   // El TB fija bfm_bit_ns (y si hace falta bfm_gap_ns y bfm_timeout_ns) antes de usar las tareas.
   // Los tiempos son reales, en las unidades del `timescale del TB (ns), y no dependen del DUT.

   real bfm_bit_ns;
   real bfm_gap_ns     = 0.0;
   real bfm_timeout_ns = 1.0e9;

   // Envía un byte por bfm_rx y después deja la línea en reposo bfm_gap_ns.
   task automatic bfm_send_byte(input [7:0] b);
       integer i;
       begin
           bfm_rx = 1'b0;
           #(bfm_bit_ns);
           for (i = 0; i < 8; i = i + 1) begin
               bfm_rx = b[i];
               #(bfm_bit_ns);
           end
           bfm_rx = 1'b1;
           #(bfm_bit_ns);
           if (bfm_gap_ns > 0.0) #(bfm_gap_ns);
       end
   endtask

   // Espera un start en bfm_tx (a lo sumo bfm_timeout_ns) y decodifica un byte muestreando a mitad de bit.
   // ok = 0 si no llegó el start o si el stop vino en 0. Vuelve a mitad del stop bit.
   // Se llama con la línea en reposo: detecta el nivel bajo con resolución de 1 ns.
   task automatic bfm_recv_byte(output [7:0] b, output reg ok);
       integer i;
       real waited;
       begin
           b = 8'h00;
           ok = 1'b0;
           waited = 0.0;
           while (bfm_tx !== 1'b0 && waited < bfm_timeout_ns) begin
               #(1.0);
               waited = waited + 1.0;
           end
           if (bfm_tx === 1'b0) begin
               #(bfm_bit_ns / 2.0);
               if (bfm_tx === 1'b0) begin
                   for (i = 0; i < 8; i = i + 1) begin
                       #(bfm_bit_ns);
                       b[i] = bfm_tx;
                   end
                   #(bfm_bit_ns);
                   ok = (bfm_tx === 1'b1);
               end
           end
       end
   endtask
   ```

2. **`tb_uart.sv`.** Crear `TP3_FINAL/VIVADO/TP_FINAL/tb/uart/tb_uart.sv` con exactamente:

   ```systemverilog
   `timescale 1ns/1ps

   // TB automático de uart_if (B-04). Casos 1-11 de planning/issues/M0-uart/B-04-testbench-uart.md.
   // Las entradas del DUT se manejan con <= en negedge; las salidas se leen en negedge.
   module tb_uart;
       parameter integer CLOCK_FREQ = 50_000_000;
       parameter integer BAUD_RATE  = 115_200;
       localparam real CLK_HALF_NS = 1.0e9 / CLOCK_FREQ / 2.0;
       localparam real BIT_NS      = 1.0e9 / BAUD_RATE;

       reg        i_clock    = 1'b0;
       reg        i_reset    = 1'b1;
       reg        i_tx_start = 1'b0;
       reg  [7:0] i_tx_data  = 8'h00;
       wire       o_tx_busy;
       wire       o_rx_valid;
       wire [7:0] o_rx_data;
       wire       o_rx_frame_err;

       reg  bfm_rx = 1'b1;
       wire bfm_tx;
   `include "uart_bfm.svh"

       always #(CLK_HALF_NS) i_clock = ~i_clock;

       uart_if #(
           .CLOCK_FREQ(CLOCK_FREQ),
           .BAUD_RATE(BAUD_RATE)
       ) u_dut (
           .i_clock(i_clock),
           .i_reset(i_reset),
           .i_rx(bfm_rx),
           .o_tx(bfm_tx),
           .i_tx_start(i_tx_start),
           .i_tx_data(i_tx_data),
           .o_tx_busy(o_tx_busy),
           .o_rx_valid(o_rx_valid),
           .o_rx_data(o_rx_data),
           .o_rx_frame_err(o_rx_frame_err)
       );

       integer errors = 0;
       integer checks = 0;

       task automatic fail(input string msg);
           begin
               errors = errors + 1;
               $display("FAIL %0s", msg);
           end
       endtask

       task automatic check(input bit cond, input string msg);
           begin
               checks = checks + 1;
               if (!cond) fail(msg);
           end
       endtask

       // ---- Monitor de RX y caso 10 (aserciones en cada ciclo) ----
       reg [7:0] rx_buf [0:1023];
       integer rx_count      = 0;
       integer ferr_count    = 0;
       reg     prev_rx_valid = 1'b0;
       reg     prev_busy     = 1'b0;

       // En el negedge N, i_tx_start/i_reset valen lo que valían en el posedge anterior (se manejan con <=),
       // y prev_busy es o_tx_busy de antes de ese posedge: así se sabe si ahí se aceptó un byte.
       always @(negedge i_clock) begin
           if (!i_reset) begin
               if (o_rx_valid) begin
                   rx_buf[rx_count % 1024] = o_rx_data;
                   rx_count = rx_count + 1;
               end
               if (o_rx_frame_err) ferr_count = ferr_count + 1;
               if (o_rx_valid && prev_rx_valid) fail("C10: o_rx_valid de más de 1 ciclo");
               if (o_rx_valid && o_rx_frame_err) fail("C10: o_rx_valid y o_rx_frame_err en el mismo ciclo");
               if (o_tx_busy !== (u_dut.u_tx.r_state != 2'd0)) fail("C10: o_tx_busy distinto de (TX fuera de IDLE)");
               if (i_tx_start && !prev_busy && o_tx_busy !== 1'b1) fail("C10: o_tx_busy no subió tras aceptar un byte");
           end
           prev_rx_valid = o_rx_valid;
           prev_busy     = o_tx_busy;
       end

       // ---- Ayudas de TX ----
       // Espera reposo, presenta el byte un ciclo (handshake valid/ready) y vuelve.
       task tx_send(input [7:0] b);
           begin
               @(negedge i_clock);
               while (o_tx_busy) @(negedge i_clock);
               i_tx_data  <= b;
               i_tx_start <= 1'b1;
               @(negedge i_clock);
               i_tx_start <= 1'b0;
           end
       endtask

       task tx_check(input [7:0] b, input string tag);
           reg [7:0] r;
           reg       rok;
           begin
               fork
                   tx_send(b);
                   bfm_recv_byte(r, rok);
               join
               check(rok && r == b, $sformatf("%0s: enviado %02h, recibido %02h, ok=%0d", tag, b, r, rok));
           end
       endtask

       // Verifica que no salga ningún byte por TX durante t_ns.
       task tx_none(input real t_ns, input string tag);
           reg [7:0] r;
           reg       rok;
           begin
               bfm_timeout_ns = t_ns;
               bfm_recv_byte(r, rok);
               bfm_timeout_ns = 20.0 * BIT_NS;
               check(!rok, $sformatf("%0s: salió un byte de más (%02h)", tag, r));
           end
       endtask

       // ---- Ayudas de RX ----
       // Envía n bytes (m*k + 5) % 256 con el emisor desviado ppm y gap_ns entre bytes, y verifica que lleguen todos.
       task rx_burst(input integer n, input integer k, input integer ppm, input real gap_ns, input string tag);
           integer m, base, ferr0, shown;
           reg [7:0] expv;
           begin
               bfm_bit_ns = BIT_NS * (1.0 + ppm / 1.0e6);
               bfm_gap_ns = gap_ns;
               base  = rx_count;
               ferr0 = ferr_count;
               for (m = 0; m < n; m = m + 1) bfm_send_byte((m * k + 5) % 256);
               #(3.0 * BIT_NS);
               bfm_bit_ns = BIT_NS;
               bfm_gap_ns = 0.0;
               check(rx_count - base == n, $sformatf("%0s: recibidos %0d de %0d", tag, rx_count - base, n));
               check(ferr_count == ferr0, $sformatf("%0s: %0d errores de framing", tag, ferr_count - ferr0));
               shown = 0;
               for (m = 0; m < n && m < rx_count - base; m = m + 1) begin
                   expv = (m * k + 5) % 256;
                   checks = checks + 1;
                   if (rx_buf[(base + m) % 1024] !== expv) begin
                       if (shown < 5) fail($sformatf("%0s: byte %0d esperado %02h, recibido %02h", tag, m, expv, rx_buf[(base + m) % 1024]));
                       else errors = errors + 1;
                       shown = shown + 1;
                   end
               end
           end
       endtask

       // Trama con stop en 0 y después la línea en reposo 2 bits.
       task send_bad_stop(input [7:0] b);
           integer m;
           begin
               bfm_rx = 1'b0;
               #(BIT_NS);
               for (m = 0; m < 8; m = m + 1) begin
                   bfm_rx = b[m];
                   #(BIT_NS);
               end
               bfm_rx = 1'b0;
               #(BIT_NS);
               bfm_rx = 1'b1;
               #(2.0 * BIT_NS);
           end
       endtask

       // ---- Watchdog: el doble de lo esperado (~11 000 bits) ----
       initial begin
           #(25000.0 * BIT_NS);
           $fatal(1, "FAIL tb_uart: watchdog");
       end

       integer i, j, base, ferr0, acc;
       integer ppm_list [0:6];
       reg [7:0] got;
       reg       ok;

       initial begin
           bfm_bit_ns     = BIT_NS;
           bfm_gap_ns     = 0.0;
           bfm_timeout_ns = 20.0 * BIT_NS;
           ppm_list[0] = -20000; ppm_list[1] = -10000; ppm_list[2] = -5000; ppm_list[3] = 0;
           ppm_list[4] =   5000; ppm_list[5] =  10000; ppm_list[6] = 20000;
           $display("tb_uart: CLOCK_FREQ=%0d BAUD_RATE=%0d BIT_NS=%0.1f", CLOCK_FREQ, BAUD_RATE, BIT_NS);
           repeat (10) @(negedge i_clock);
           i_reset <= 1'b0;
           #(2.0 * BIT_NS);

           $display("CASO 1: los 256 valores por RX y por TX");
           rx_burst(256, 1, 0, BIT_NS, "C1 RX");
           for (i = 0; i < 256; i = i + 1) tx_check(i, "C1 TX");
           #(2.0 * BIT_NS);

           $display("CASO 2: 64 bytes seguidos, emisor ideal");
           rx_burst(64, 37, 0, 0.0, "C2");

           $display("CASO 3: 64 bytes seguidos con el emisor desviado");
           for (j = 0; j < 7; j = j + 1)
               rx_burst(64, 37, ppm_list[j], 0.0, $sformatf("C3 %0d ppm", ppm_list[j]));

           $display("CASO 4: glitch de 1/4 de bit en reposo");
           base = rx_count; ferr0 = ferr_count;
           bfm_rx = 1'b0;
           #(BIT_NS / 4.0);
           bfm_rx = 1'b1;
           #(2.0 * BIT_NS);
           check(rx_count == base && ferr_count == ferr0, "C4: el glitch produjo un pulso de RX");
           rx_burst(1, 37, 0, 0.0, "C4 siguiente");

           $display("CASO 5: reset en mitad de trama (RX y TX)");
           base = rx_count; ferr0 = ferr_count;
           fork
               bfm_send_byte(8'hFF);   // datos en 1: tras el reset la línea queda en 1 y no hay start falso
               begin
                   #(4.5 * BIT_NS);
                   @(negedge i_clock); i_reset <= 1'b1;
                   repeat (2) @(negedge i_clock);
                   i_reset <= 1'b0;
               end
           join
           #(2.0 * BIT_NS);
           check(rx_count == base && ferr_count == ferr0, "C5 RX: pulso espurio después del reset");
           rx_burst(1, 37, 0, 0.0, "C5 RX siguiente");
           fork
               tx_send(8'h00);
               begin
                   #(3.5 * BIT_NS);
                   @(negedge i_clock); i_reset <= 1'b1;
                   @(negedge i_clock);
                   check(bfm_tx === 1'b1 && o_tx_busy === 1'b0, "C5 TX: con reset la línea no volvió a reposo");
                   i_reset <= 1'b0;
               end
           join
           #(2.0 * BIT_NS);
           tx_check(8'hA5, "C5 TX siguiente");

           $display("CASO 7: stop en 0");
           base = rx_count; ferr0 = ferr_count;
           send_bad_stop(8'h5C);
           check(ferr_count - ferr0 == 1, $sformatf("C7: %0d pulsos de o_rx_frame_err, esperado 1", ferr_count - ferr0));
           check(rx_count == base, "C7: hubo o_rx_valid con stop en 0");
           rx_burst(1, 37, 0, 0.0, "C7 siguiente");

           $display("CASO 8: i_tx_start con o_tx_busy = 1");
           fork
               begin
                   tx_send(8'h12);
                   #(3.0 * BIT_NS);
                   @(negedge i_clock);
                   i_tx_data  <= 8'h34;
                   i_tx_start <= 1'b1;
                   @(negedge i_clock);
                   i_tx_start <= 1'b0;
               end
               begin
                   bfm_recv_byte(got, ok);
                   check(ok && got == 8'h12, $sformatf("C8: recibido %02h ok=%0d, esperado 12", got, ok));
                   tx_none(3.0 * BIT_NS, "C8");
               end
           join

           $display("CASO 9: i_tx_start sostenido durante 3 aceptaciones");
           fork
               begin
                   @(negedge i_clock);
                   i_tx_data  <= 8'h6B;
                   i_tx_start <= 1'b1;
                   acc = 0;
                   // En cada negedge con start en 1 y busy en 0, el posedge siguiente acepta un byte.
                   // Al contar la 3.ª se avanza un negedge (ya pasó esa aceptación) y se baja start:
                   // ahí busy vale 1, así que no hay una 4.ª.
                   while (acc < 3) begin
                       if (!o_tx_busy) acc = acc + 1;
                       @(negedge i_clock);
                   end
                   i_tx_start <= 1'b0;
               end
               begin
                   for (j = 0; j < 3; j = j + 1) begin
                       bfm_recv_byte(got, ok);
                       check(ok && got == 8'h6B, $sformatf("C9: byte %0d = %02h ok=%0d, esperado 6B", j, got, ok));
                   end
                   tx_none(3.0 * BIT_NS, "C9");
               end
           join

           $display("CASO 11: cambio de i_tx_data después de la aceptación");
           fork
               begin
                   tx_send(8'hC3);
                   i_tx_data <= 8'h3C;
               end
               begin
                   bfm_recv_byte(got, ok);
                   check(ok && got == 8'hC3, $sformatf("C11: recibido %02h ok=%0d, esperado C3", got, ok));
               end
           join
           #(2.0 * BIT_NS);

           if (errors != 0) $fatal(1, "FAIL tb_uart: %0d errores", errors);
           $display("PASS tb_uart: %0d chequeos", checks);
           $finish;
       end
   endmodule
   ```

   Notas para el ejecutor (no cambian el código): el caso 6 son las entradas `tb_uart_fast32` y `tb_uart_fast128` de `tbs.py` (paso 7), que corren este mismo TB con otro `BAUD_RATE`; el caso 10 es el `always @(negedge)` del monitor.

3. **Runner.** `run.py` ya soporta la clave `incdirs` desde B-01 (comprobar que `run_tb` arma `incdirs` con `spec.get("incdirs", [])`; si no, detenerse). En `TP3_FINAL/tools/tbs.py`, agregar debajo de `TB = ...`:

   ```python
   UART_RTL = [f"{RTL}/uart/baud_gen.v", f"{RTL}/uart/uart_rx.v",
               f"{RTL}/uart/uart_tx.v", f"{RTL}/uart/uart_if.v"]
   ```

   y en `TBS`:

   ```python
       "tb_uart": {"top": "tb_uart", "files": UART_RTL + [f"{TB}/uart/tb_uart.sv"],
                   "incdirs": [f"{TB}/common"]},
   ```

4. **Rojo (evidencia de H-1).** Con el `uart_rx.v` de B-03, sin tocarlo: `py TP3_FINAL/tools/run.py tb tb_uart` → **tiene que fallar**. Tarda del orden de 1-2 minutos. Esperado en `TP3_FINAL/build/tb_uart.log`:
   - `FAIL C3 -5000 ppm`, `FAIL C3 -10000 ppm`, `FAIL C3 -20000 ppm` (errores de framing, bytes perdidos o mal recibidos).
   - `FAIL C7: hubo o_rx_valid con stop en 0` y líneas `FAIL C10: o_rx_valid y o_rx_frame_err en el mismo ciclo` (D-08 todavía no aplicado).
   - Los casos 1, 2, 4, 5, 8, 9, 11 y C3 con 0 y +ppm sin `FAIL`.

   Guardar el resumen: `grep "^FAIL" TP3_FINAL/build/tb_uart.log | sort | uniq -c | head -40` y pegarlo en `uart.md` (paso 9) como "Antes del arreglo". **Commit 1** con el TB, la BFM y los cambios del runner (el TB falla a propósito en este commit).

5. **Arreglo D-07 + D-08.** Reemplazar `TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/uart_rx.v` completo por:

   ```verilog
   `timescale 1ns/1ps
   `default_nettype none

   module uart_rx (
       input  wire       i_clock,
       input  wire       i_baud_tick,
       input  wire       i_reset,
       input  wire       i_rx,
       output reg        o_valid,
       output reg  [7:0] o_data,
       output reg        o_error
   );
       reg [2:0] r_state;
       reg [2:0] r_next_state;
       reg [3:0] r_tick_counter;
       reg [2:0] r_bit_counter;
       reg [7:0] r_shift;

       // Sincronizador de la entrada asíncrona: 2 FF juntos en el mismo slice.
       (* ASYNC_REG = "TRUE" *) reg [1:0] r_rx_sync;
       wire w_rx = r_rx_sync[1];

       localparam IDLE      = 3'd0;
       localparam START     = 3'd1;
       localparam DATA      = 3'd2;
       localparam STOP      = 3'd3;
       localparam WAIT_IDLE = 3'd4;
       localparam SAMPLE    = 4'd7;

       // El conteo de ticks arranca en el flanco de start, así que el tick SAMPLE de cada bit cae en su centro.
       // El stop se evalúa en su centro (≈ 9,5 bits del flanco), no en su final: con tramas seguidas, el
       // final del stop es el borde del start siguiente (H-1, D-07).
       // IDLE      -> START     : w_rx == 0
       // START     -> IDLE      : tick SAMPLE con w_rx == 1 (inicio falso)
       // START     -> DATA      : tick 15
       // DATA      -> STOP      : tick 15 del bit 7
       // STOP      -> IDLE      : tick SAMPLE con w_rx == 1 (byte bueno: o_valid)
       // STOP      -> WAIT_IDLE : tick SAMPLE con w_rx == 0 (framing: o_error, sin o_valid, D-08)
       // WAIT_IDLE -> IDLE      : w_rx == 1 (no tomar el resto de un stop en 0 como un start nuevo)

       wire w_stop_sample = (r_state == STOP) && i_baud_tick && (r_tick_counter == SAMPLE);

       always @(*) begin
           r_next_state = r_state;
           case (r_state)
               IDLE: begin
                   if (w_rx == 1'b0) begin
                       r_next_state = START;
                   end
               end
               START: begin
                   if (i_baud_tick && r_tick_counter == SAMPLE && w_rx == 1'b1) begin
                       r_next_state = IDLE;
                   end else if (i_baud_tick && r_tick_counter == 15) begin
                       r_next_state = DATA;
                   end
               end
               DATA: begin
                   if (i_baud_tick && r_tick_counter == 15 && r_bit_counter == 7) begin
                       r_next_state = STOP;
                   end
               end
               STOP: begin
                   if (w_stop_sample) begin
                       r_next_state = w_rx ? IDLE : WAIT_IDLE;
                   end
               end
               WAIT_IDLE: begin
                   if (w_rx == 1'b1) begin
                       r_next_state = IDLE;
                   end
               end
               default: begin
                   r_next_state = IDLE;
               end
           endcase
       end

       always @(posedge i_clock) begin
           if (i_reset) begin
               r_rx_sync <= 2'b11;
           end else begin
               r_rx_sync <= {r_rx_sync[0], i_rx};
           end
       end

       always @(posedge i_clock) begin
           if (i_reset) begin
               r_state <= IDLE;
           end else begin
               r_state <= r_next_state;
           end
       end

       always @(posedge i_clock) begin
           if (i_reset) begin
               r_tick_counter <= 4'b0;
           end else if (r_next_state == IDLE || r_next_state == WAIT_IDLE
                        || (i_baud_tick && r_tick_counter == 15)) begin
               r_tick_counter <= 4'b0;
           end else if (i_baud_tick) begin
               r_tick_counter <= r_tick_counter + 1'b1;
           end
       end

       always @(posedge i_clock) begin
           if (i_reset) begin
               r_bit_counter <= 3'b0;
           end else if (i_baud_tick && r_tick_counter == 15 && r_bit_counter == 7) begin
               r_bit_counter <= 3'b0;
           end else if (i_baud_tick && r_tick_counter == 15 && r_state == DATA) begin
               r_bit_counter <= r_bit_counter + 1'b1;
           end
       end

       always @(posedge i_clock) begin
           if (i_reset) begin
               r_shift <= 8'b0;
           end else if (r_state == DATA && i_baud_tick && r_tick_counter == SAMPLE) begin
               r_shift <= {w_rx, r_shift[7:1]};
           end
       end

       always @(posedge i_clock) begin
           if (i_reset) begin
               o_data <= 8'b0;
           end else if (w_stop_sample) begin
               o_data <= r_shift;
           end
       end

       always @(posedge i_clock) begin
           if (i_reset) begin
               o_valid <= 1'b0;
           end else begin
               o_valid <= w_stop_sample && (w_rx == 1'b1);
           end
       end

       always @(posedge i_clock) begin
           if (i_reset) begin
               o_error <= 1'b0;
           end else begin
               o_error <= w_stop_sample && (w_rx == 1'b0);
           end
       end
   endmodule

   `default_nettype wire
   ```

   Qué cambió respecto de B-03 (para el mensaje del commit y `uart.md`): `r_state` de 2 a 3 bits; estado nuevo `WAIT_IDLE`; `STOP → IDLE` en el tick `SAMPLE` en vez del 15; `o_data`/`o_valid`/`o_error` se generan en ese mismo tick; `o_valid` solo con stop en 1 y `o_error` solo con stop en 0; el contador de ticks también se pone en 0 al entrar a `WAIT_IDLE`. Temporización: el stop se muestrea en el 8.º tick del stop, es decir a 9 bits + 8/16 desde el flanco de start más la latencia del sincronizador (2-3 clocks) y la fase del tick (0 a 1 tick). Tolerancia estimada ≈ ±4-5 % (antes ≈ +0,4 % hacia el emisor rápido).

   Verificar: `py TP3_FINAL/tools/run.py tb tb_uart` → `PASS tb_uart: ... chequeos`. Si falla, ver "Si algo falla"; no tocar el TB para que pase.

6. **TB de módulo con `$fatal`/`PASS`.**
   - `tb_uart_rx.sv`:
     - Agregar `` `timescale 1ns/1ps `` como primera línea.
     - Reemplazar el bloque del caso T5:

       ```systemverilog
               $display("TEST T5 | Framing error with stop bit low");
               fork
                   send_frame(8'h5C, 1'b0);
                   wait_and_check_frame(8'h5C, 1'b1, "T5");
               join
       ```

       por

       ```systemverilog
               $display("TEST T5 | Framing error with stop bit low: error pulse without valid (D-08)");
               fork
                   send_frame(8'h5C, 1'b0);
                   begin
                       @(posedge o_error);
                       #1;
                       check_valid_and_error(1'b0, 1'b1, "T5");
                       check_data(8'h5C, "T5");
                   end
               join
       ```

     - Reemplazar

       ```systemverilog
               if (fail_count == 0) $display("All tests PASSED.");
               else $display("Some tests FAILED.");
               $finish;
       ```

       por

       ```systemverilog
               if (fail_count != 0) $fatal(1, "FAIL tb_uart_rx: %0d errores", fail_count);
               $display("PASS tb_uart_rx: %0d chequeos", pass_count);
               $finish;
       ```

     - En el `initial` del watchdog, reemplazar las dos líneas `$display("TIMEOUT! ...");` y `$finish;` por `$fatal(1, "FAIL tb_uart_rx: watchdog");`.
   - `tb_uart_tx.sv`: lo mismo (timescale, final y watchdog) con `tb_uart_tx` en los mensajes. Sin cambios de casos.
   - En `tbs.py`, borrar `"legacy": True,` de `tb_uart_rx` y `tb_uart_tx`. La rama `legacy` de `run_tb` queda sin uso; dejarla.

   Verificar: `py TP3_FINAL/tools/run.py tb tb_uart_rx` → `PASS tb_uart_rx: 25 chequeos` (antes 26: T5 pasó de 4 a 3 chequeos). `py TP3_FINAL/tools/run.py tb tb_uart_tx` → `PASS tb_uart_tx: 22 chequeos`.

7. **Baud alto (caso 6).** Agregar a `TBS`:

   ```python
       "tb_uart_fast32": {"top": "tb_uart", "files": UART_RTL + [f"{TB}/uart/tb_uart.sv"],
                          "incdirs": [f"{TB}/common"], "params": {"BAUD_RATE": 1_562_500}},
       "tb_uart_fast128": {"top": "tb_uart", "files": UART_RTL + [f"{TB}/uart/tb_uart.sv"],
                           "incdirs": [f"{TB}/common"], "params": {"BAUD_RATE": 390_625}},
   ```

   `1_562_500 = 50 MHz / 32` (DIV = 2, un tick cada 2 clocks: el que usan B-16 y la Fase 10) y `390_625 = 50 MHz / 128` (DIV = 8, control).

   Verificar: `py TP3_FINAL/tools/run.py tb tb_uart_fast32` y `... tb_uart_fast128` → `PASS`.

8. **Mutaciones.** En `tbs.py`, agregar al final:

   ```python
   # Cada mutación copia el archivo a build/mut/<name>/, reemplaza "old" (que tiene que aparecer
   # exactamente una vez) por "new", y corre el TB esperando que FALLE.
   MUTATIONS = [
       {"name": "tx_orden_bits", "file": f"{RTL}/uart/uart_tx.v", "tb": "tb_uart",
        "old": "r_shift <= r_shift >> 1;", "new": "r_shift <= r_shift << 1;"},
       {"name": "rx_muestreo_tarde", "file": f"{RTL}/uart/uart_rx.v", "tb": "tb_uart",
        "old": "localparam SAMPLE    = 4'd7;", "new": "localparam SAMPLE    = 4'd14;"},
   ]
   ```

   En `run.py`: cambiar `from tbs import SYNTH, TBS` por `from tbs import MUTATIONS, SYNTH, TBS`, agregar la función

   ```python
   def run_mutate() -> bool:
       ok_all = True
       for m in MUTATIONS:
           src = REPO / m["file"]
           text = src.read_text()
           n = text.count(m["old"])
           if n != 1:
               print(f"FAIL mutate {m['name']}: el texto original aparece {n} veces")
               ok_all = False
               continue
           mfile = BUILD / "mut" / m["name"] / src.name
           mfile.parent.mkdir(parents=True, exist_ok=True)
           mfile.write_text(text.replace(m["old"], m["new"]))
           spec = dict(TBS[m["tb"]])
           spec["files"] = [mfile.relative_to(REPO).as_posix() if f == m["file"] else f
                            for f in spec["files"]]
           name = f"mut_{m['name']}"
           TBS[name] = spec
           detected = not run_tb(name)
           print(f"{'PASS' if detected else 'FAIL'} mutate {m['name']}: "
                 f"{'detectada' if detected else 'NO detectada'}")
           ok_all = ok_all and detected
       return ok_all
   ```

   y en `main`: `sub.add_parser("mutate")` y la rama `elif a.cmd == "mutate": ok = run_mutate()` (antes del `else` de `synth_ooc`). Actualizar el docstring con la línea `py TP3_FINAL/tools/run.py mutate`.

   Verificar: `py TP3_FINAL/tools/run.py mutate` → dos líneas `FAIL mut_...` del TB (esperadas) seguidas de `PASS mutate tx_orden_bits: detectada` y `PASS mutate rx_muestreo_tarde: detectada`, y código de salida 0.

   Por qué `SAMPLE = 14` se detecta: con el muestreo a 15/16 del bit, un emisor 2 % más rápido ya cambió de bit cuando la FPGA muestrea el bit 7 (≈ 8,82 bits contra ≈ 8,85-8,9 de muestreo): falla `C3 -20000 ppm`.

9. **`uart.md`, sección "Verificación".** Reemplazar `Pendiente (B-04).` por: la tabla de casos (número, estímulo, qué verifica: copiar las dos tablas de "Casos" de abajo), el bloque "Antes del arreglo" (salida del paso 4), "Después del arreglo" (las líneas `PASS` de `tb_uart`, `tb_uart_fast32`, `tb_uart_fast128`, `tb_uart_rx`, `tb_uart_tx`, `tb_baud_gen`), el párrafo de "Qué cambió" del paso 5 y el procedimiento de mutación (las dos mutaciones y el comando).

### Casos

| # | Caso | Estímulo | Verifica |
| --- | --- | --- | --- |
| 1 | 256 valores | RX: bytes `(m + 5) % 256`, m = 0..255, con 1 bit de pausa. TX: `i` = 0..255 por handshake | Los 256 de RX y de TX coinciden; 1 `o_rx_valid` por byte |
| 2 | 64 seguidos | Sin pausa entre stop y start, emisor ideal | 64 recibidos, en orden, sin framing |
| 3 | Desvío | Caso 2 con −2, −1, −0,5, 0, +0,5, +1, +2 % de período de bit | Igual que el caso 2 en los 7 |
| 4 | Glitch | 0 durante ¼ de bit en reposo | Sin pulsos; el byte siguiente llega bien |
| 5 | Reset en trama | Reset a 4,5 bits de un byte RX (`0xFF`) y a 3,5 bits de un byte TX | Sin pulsos espurios; `o_tx = 1` y `o_tx_busy = 0` con reset; el byte siguiente llega bien en los dos sentidos |
| 6 | Baud alto | Todo el TB con `BAUD_RATE` = `CLK/32` y `CLK/128` | Mismo resultado |

| # | Caso | Verifica |
| --- | --- | --- |
| 7 | Stop en 0 | 1 pulso de `o_rx_frame_err`, ningún `o_rx_valid`; el byte siguiente llega bien |
| 8 | Start con busy | El byte en curso sale intacto y no sale un segundo byte |
| 9 | Start sostenido | 3 aceptaciones → exactamente 3 bytes iguales, ninguno de más |
| 10 | Aserciones por ciclo | `o_rx_valid` nunca 2 ciclos seguidos ni junto con `o_rx_frame_err`; `o_tx_busy == (TX fuera de IDLE)`; `o_tx_busy` sube en el ciclo siguiente a una aceptación |
| 11 | Dato cambia tras aceptar | Sale el byte capturado en la aceptación |

## Validación

```bash
py TP3_FINAL/tools/run.py tbs      # 6/6 PASS: tb_baud_gen, tb_uart_rx, tb_uart_tx, tb_uart, tb_uart_fast32, tb_uart_fast128
py TP3_FINAL/tools/run.py mutate   # 2 mutaciones detectadas, código 0
py TP3_FINAL/tools/run.py synth_ooc uart_rx   # PASS
py TP3_FINAL/tools/run.py synth_ooc uart_if   # PASS
```

## Listo cuando

- [ ] El commit 1 (TB en rojo) existe y `uart.md` tiene su salida "Antes del arreglo" con fallas en C3 −0,5/−1/−2 % y en C7.
- [ ] Después del commit 2, `run.py tbs` da `6/6 PASS`.
- [ ] `run.py mutate` detecta las dos mutaciones.
- [ ] `tb_uart_rx` y `tb_uart_tx` terminan con `$fatal` si fallan y ya no tienen la marca `legacy`.
- [ ] `uart.md` tiene la sección "Verificación" completa.

## No hacer

- No modificar `tb_uart.sv` para hacerlo pasar después del paso 5: si falla, es el RTL o una duda que hay que preguntar.
- No cambiar la API de `uart_bfm.svh`.
- No tocar `uart_tx.v`, `baud_gen.v` ni `uart_if.v` (salvo que un caso falle por ellos: entonces detenerse y preguntar).

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| Icarus no acepta `string`, `$sformatf` o `bit` | Confirmar `-g2012` en el comando del log. Si aun así falla, detenerse y preguntar (no reescribir el TB en Verilog-2001) |
| Icarus no acepta el `` `include `` dentro del módulo | Verificar que la entrada de `tbs.py` tenga `"incdirs": [f"{TB}/common"]` (el log muestra el `-I.../tb/common`) |
| En el paso 4 **no** falla C3 −0,5 % pero sí −1 % y −2 % | Aceptable: registrar lo que salió. Si no falla ninguno de C3, detenerse y preguntar (la evidencia de H-1 no se reprodujo) |
| En el paso 4 falla C2 (emisor ideal) | Registrarlo como parte de la evidencia y seguir |
| Después del paso 5 falla algún C3 | Pegar las líneas `FAIL` y detenerse a preguntar; no ajustar `ppm_list` |
| `C10: o_tx_busy distinto de (TX fuera de IDLE)` | El nombre `u_dut.u_tx.r_state` o su ancho cambió: verificar `uart_if.v` (instancia `u_tx`) y `uart_tx.v` (`reg [1:0] r_state`) |
| Una mutación queda "NO detectada" | Detenerse y preguntar; no agregar casos por cuenta propia |
| `tb_uart` tarda más de 5 minutos | Pegar el tiempo en el PR y seguir; no reducir casos |

## Commits

1. `uart: tb_uart y BFM; falla a propósito por H-1 (stop evaluado al final del bit)`
2. `uart: rx evalúa el stop a mitad de bit y no da valid con framing (D-07, D-08)`
3. `uart: tb de módulo terminan en $fatal/PASS`
4. `uart: tb_uart con baud alto (CLK/32 y CLK/128)`
5. `tools: objetivo mutate`
6. `docs: sección Verificación de uart.md`

## Depende de / bloquea

Depende de: B-02, B-03.
Bloquea: B-05, B-16 (usa `uart_bfm.svh`), B-28.

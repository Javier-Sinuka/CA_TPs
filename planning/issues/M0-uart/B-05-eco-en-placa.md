# B-05 · Eco en placa a 50 y 100 MHz

`M` · etiquetas `uart` `hw` · milestone M0 · **Modelo sugerido:** Sonnet (pasos de código) + usuario (pasos `[manual]`) · [índice](../README.md)

## Objetivo

La UART probada en la Basys3 contra el bridge USB-UART: 100 000 bytes aleatorios de eco con 0 errores y 0 perdidos, a 50 MHz y a 100 MHz, con el Clock Wizard generado por script, y el estado final de la UART escrito en `uart.md`.

## Antes de empezar

- Leer: [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §2, §3, §4, §6; [`decisiones.md`](../../../TP3_FINAL/doc/documentation/decisiones.md) D-10, D-12, D-13, D-14, D-16; sección "Interfaz" de `TP3_FINAL/doc/documentation/uart.md`.
- Precondiciones: B-02, B-03 y B-04 cerrados. Comprobar: `py TP3_FINAL/tools/run.py tbs` → `6/6 PASS`; existe `TP3_FINAL/VIVADO/TP_FINAL/tb/common/uart_bfm.svh`.
- Rama: `b/B-05-eco-placa`.
- Los pasos marcados **[manual]** los hace el usuario con la placa conectada; el ejecutor deja todo listo y le pide los resultados.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/rtl/top/top_uart_echo.v` | paso 1 |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/rtl/top/clk_gen.v` | paso 4 (alternativa MMCM) |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/top/tb_uart_echo.sv` | paso 2 |
| crear | `TP3_FINAL/constraints/basys3_uart_echo.xdc` | paso 3 |
| crear | `TP3_FINAL/tools/build_bit.tcl` | paso 4 |
| crear | `TP3_FINAL/tools/program.tcl` | paso 5 |
| modificar | `TP3_FINAL/tools/run.py`, `TP3_FINAL/tools/tbs.py` | objetivos `bit`, `program`; tablas `BITS`, TB nuevo |
| crear | `TP3_FINAL/sw/host/__init__.py` | vacío (si no existe) |
| crear | `TP3_FINAL/sw/host/echo_test.py` | paso 6 |
| modificar | `TP3_FINAL/doc/documentation/uart.md` | "Resultados en placa" y "Estado" |

## Pasos

1. **`top_uart_echo.v`.** Crear con exactamente:

   ```verilog
   `timescale 1ns/1ps
   `default_nettype none

   // Eco por UART para validar la UART en la placa (B-05): lo que llega por RX vuelve por TX.
   module top_uart_echo #(
       parameter integer CLOCK_FREQ = 50_000_000,   // build_bit.tcl lo fija con -generic = salida del Wizard
       parameter integer BAUD_RATE  = 115_200
   )(
       input  wire       i_clk100,      // W5, 100 MHz de la placa
       input  wire       i_btn_reset,   // U18 (btnC), activo en alto
       input  wire       i_rx,          // B18
       output wire       o_tx,          // A18
       output wire [3:0] o_led          // [0] conmuta por byte, [1] framing, [2] overrun, [3] locked
   );
       wire w_clock;
       wire w_locked;

       // Clock Wizard clk_wiz_0 creado por build_bit.tcl (o clk_gen.v con --clk mmcm): mismo nombre y
       // puertos clk_in1, clk_out1, locked. Sin puerto de reset (USE_RESET = false): nunca se resetea el MMCM.
       clk_wiz_0 u_clk (
           .clk_in1(i_clk100),
           .clk_out1(w_clock),
           .locked(w_locked)
       );

       // Reset del sistema (D-10): botón o Wizard sin enganchar, sincronizado con 2 FF.
       // El valor inicial arranca en reset (único valor inicial permitido fuera de memorias).
       (* ASYNC_REG = "TRUE" *) reg [1:0] r_reset_sync = 2'b11;
       always @(posedge w_clock) begin
           r_reset_sync <= {r_reset_sync[0], i_btn_reset | ~w_locked};
       end
       wire w_reset = r_reset_sync[1];

       wire       w_rx_valid;
       wire       w_rx_frame_err;
       wire [7:0] w_rx_data;
       wire       w_tx_busy;

       reg        r_hold_full;
       reg  [7:0] r_hold_data;
       reg        r_led_toggle;
       reg        r_led_frame;
       reg        r_led_overrun;

       uart_if #(
           .CLOCK_FREQ(CLOCK_FREQ),
           .BAUD_RATE(BAUD_RATE)
       ) u_uart (
           .i_clock(w_clock),
           .i_reset(w_reset),
           .i_rx(i_rx),
           .o_tx(o_tx),
           .i_tx_start(r_hold_full),
           .i_tx_data(r_hold_data),
           .o_tx_busy(w_tx_busy),
           .o_rx_valid(w_rx_valid),
           .o_rx_data(w_rx_data),
           .o_rx_frame_err(w_rx_frame_err)
       );

       // Retención de 1 byte (D-12). r_hold_full es el "valid" del handshake de TX (D-14):
       // el byte sale en el flanco en que r_hold_full = 1 y w_tx_busy = 0.
       wire w_tx_accept = r_hold_full && !w_tx_busy;
       wire w_hold_free = !r_hold_full || w_tx_accept;

       always @(posedge w_clock) begin
           if (w_reset) begin
               r_hold_full <= 1'b0;
               r_hold_data <= 8'h00;
           end else if (w_rx_valid && w_hold_free) begin
               r_hold_full <= 1'b1;
               r_hold_data <= w_rx_data;
           end else if (w_tx_accept) begin
               r_hold_full <= 1'b0;
           end
       end

       always @(posedge w_clock) begin
           if (w_reset) begin
               r_led_toggle  <= 1'b0;
               r_led_frame   <= 1'b0;
               r_led_overrun <= 1'b0;
           end else begin
               if (w_rx_valid)                 r_led_toggle  <= ~r_led_toggle;
               if (w_rx_frame_err)             r_led_frame   <= 1'b1;
               if (w_rx_valid && !w_hold_free) r_led_overrun <= 1'b1;
           end
       end

       assign o_led = {w_locked, r_led_overrun, r_led_frame, r_led_toggle};
   endmodule

   `default_nettype wire
   ```

2. **TB del eco (antes de ir a la placa).** Crear `TP3_FINAL/VIVADO/TP_FINAL/tb/top/tb_uart_echo.sv` con exactamente:

   ```systemverilog
   `timescale 1ns/1ps

   // Reemplazo del Clock Wizard solo para simulación: reloj directo y locked en 1.
   module clk_wiz_0 (
       input  wire clk_in1,
       output wire clk_out1,
       output wire locked
   );
       assign clk_out1 = clk_in1;
       assign locked   = 1'b1;
   endmodule

   // 64 bytes seguidos por RX deben volver iguales por TX, sin overrun ni framing.
   module tb_uart_echo;
       localparam integer CLOCK_FREQ = 100_000_000;
       localparam integer BAUD_RATE  = 3_125_000;   // CLOCK_FREQ / 32: DIV = 2
       localparam real    BIT_NS     = 1.0e9 / BAUD_RATE;
       localparam integer N          = 64;

       reg        r_clk = 1'b0;
       reg        r_btn = 1'b0;
       wire [3:0] w_led;
       reg  bfm_rx = 1'b1;
       wire bfm_tx;
   `include "uart_bfm.svh"

       always #5 r_clk = ~r_clk;

       top_uart_echo #(
           .CLOCK_FREQ(CLOCK_FREQ),
           .BAUD_RATE(BAUD_RATE)
       ) u_dut (
           .i_clk100(r_clk),
           .i_btn_reset(r_btn),
           .i_rx(bfm_rx),
           .o_tx(bfm_tx),
           .o_led(w_led)
       );

       integer errors = 0;
       integer checks = 0;
       integer ks, kr;
       reg [7:0] got;
       reg       ok;

       function automatic [7:0] pat(input integer m);
           pat = (m * 73 + 11) % 256;
       endfunction

       initial begin
           #(40.0 * N * BIT_NS);
           $fatal(1, "FAIL tb_uart_echo: watchdog");
       end

       initial begin
           bfm_bit_ns     = BIT_NS;
           bfm_timeout_ns = 30.0 * BIT_NS;
           repeat (20) @(negedge r_clk);
           fork
               for (ks = 0; ks < N; ks = ks + 1) bfm_send_byte(pat(ks));
               for (kr = 0; kr < N; kr = kr + 1) begin
                   bfm_recv_byte(got, ok);
                   checks = checks + 1;
                   if (!ok || got !== pat(kr)) begin
                       errors = errors + 1;
                       $display("FAIL eco %0d: esperado %02h, recibido %02h ok=%0d", kr, pat(kr), got, ok);
                   end
               end
           join
           @(negedge r_clk);
           checks = checks + 1;
           if (w_led !== 4'b1000) begin   // locked, sin overrun, sin framing, 64 bytes => toggle en 0
               errors = errors + 1;
               $display("FAIL LEDs: %b, esperado 1000", w_led);
           end
           if (errors != 0) $fatal(1, "FAIL tb_uart_echo: %0d errores", errors);
           $display("PASS tb_uart_echo: %0d chequeos", checks);
           $finish;
       end
   endmodule
   ```

   En `tbs.py`, agregar a `TBS`:

   ```python
       "tb_uart_echo": {"top": "tb_uart_echo",
                        "files": UART_RTL + [f"{RTL}/top/top_uart_echo.v", f"{TB}/top/tb_uart_echo.sv"],
                        "incdirs": [f"{TB}/common"]},
   ```

   Verificar: `py TP3_FINAL/tools/run.py tb tb_uart_echo` → `PASS tb_uart_echo: 65 chequeos`.

3. **XDC.** Crear `TP3_FINAL/constraints/basys3_uart_echo.xdc` con exactamente (pines tomados de `TP2_UART/constraints/Basys3_UART.xdc`):

   ```tcl
   ## Basys3 · top_uart_echo (B-05).
   ## Sin create_clock: el reloj de entrada lo restringe el XDC del Clock Wizard
   ## (o build_bit.tcl en modo --clk mmcm).
   set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports i_clk100]
   set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports i_btn_reset]
   set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports i_rx]
   set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports o_tx]
   set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {o_led[0]}]
   set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {o_led[1]}]
   set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {o_led[2]}]
   set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {o_led[3]}]

   ## Entradas asíncronas: van a sincronizadores de 2 FF (ASYNC_REG en el RTL).
   set_false_path -from [get_ports {i_btn_reset i_rx}]
   set_false_path -to   [get_ports {o_tx o_led[*]}]

   set_property CONFIG_VOLTAGE 3.3 [current_design]
   set_property CFGBVS VCCO [current_design]
   ```

4. **Bitstream por script.** Crear `TP3_FINAL/tools/build_bit.tcl` con exactamente:

   ```tcl
   # Uso: vivado -mode batch -source build_bit.tcl -tclargs <top> <mhz> <outdir> <wiz|mmcm> <xdc> <defines> <archivo.v> ...
   #   <defines>: nombres separados por coma para synth_design -verilog_define (por ejemplo CPU_STUB), o "-" si no hay.
   # Flujo non-project (D-13): el Clock Wizard clk_wiz_0 se crea en memoria con salida <mhz> (puertos clk_in1,
   # clk_out1, locked; sin reset), y el top recibe CLOCK_FREQ = <mhz>·10^6 por -generic.
   # Nada de esto se versiona fuera de este script.
   set top   [lindex $argv 0]
   set mhz   [lindex $argv 1]
   set out   [lindex $argv 2]
   set clk   [lindex $argv 3]
   set xdc   [lindex $argv 4]
   set defs  [lindex $argv 5]
   set files [lrange $argv 6 end]
   set part  xc7a35tcpg236-1
   set freq  [expr {$mhz * 1000000}]
   set div   [format %.3f [expr {1000.0 / $mhz}]]
   set vdefs [list CLKOUT0_DIVIDE=$div]
   if {$defs ne "-"} {
       foreach d [split $defs ,] { lappend vdefs $d }
   }

   file mkdir $out
   create_project -in_memory -part $part
   set_property target_language Verilog [current_project]

   set incdirs {}
   foreach f $files {
       read_verilog $f
       lappend incdirs [file dirname $f]
   }
   read_xdc $xdc

   if {$clk eq "wiz"} {
       create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_0 -dir $out/ip
       set_property -dict [list \
           CONFIG.PRIM_IN_FREQ {100.000} \
           CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $mhz \
           CONFIG.USE_RESET {false} \
           CONFIG.USE_LOCKED {true}] [get_ips clk_wiz_0]
       set_property generate_synth_checkpoint false [get_files clk_wiz_0.xci]
       generate_target all [get_ips clk_wiz_0]
   } else {
       # clk_gen.v ya está en $files; acá solo falta restringir el reloj de entrada.
       set fh [open $out/clk100.xdc w]
       puts $fh "create_clock -period 10.000 -name sys_clk_pin \[get_ports i_clk100\]"
       close $fh
       read_xdc $out/clk100.xdc
   }

   synth_design -top $top -part $part -generic CLOCK_FREQ=$freq \
       -verilog_define $vdefs -include_dirs [lsort -unique $incdirs]

   # Tiene que haber al menos 2 relojes: el de entrada y el de salida del Wizard/MMCM.
   if {[llength [get_clocks]] < 2} {
       error "build_bit: relojes insuficientes: [get_clocks]"
   }

   opt_design
   place_design
   route_design

   report_timing_summary -file $out/timing.rpt
   report_utilization    -file $out/util.rpt
   report_clocks         -file $out/clocks.rpt
   set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
   set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
   write_bitstream -force $out/$top.bit

   set fh [open $out/summary.txt w]
   puts $fh "TOP=$top MHZ=$mhz CLK=$clk WNS=$wns WHS=$whs"
   close $fh
   ```

   Crear `TP3_FINAL/VIVADO/TP_FINAL/rtl/top/clk_gen.v` (solo se usa con `--clk mmcm`, si el Wizard por script falla):

   ```verilog
   `timescale 1ns/1ps
   `default_nettype none

   // Alternativa al Clock Wizard (D-13): MMCM instanciado a mano, mismo nombre y puertos que el IP.
   // VCO = 100 MHz × 10 = 1000 MHz; salida = 1000 MHz / CLKOUT0_DIVIDE.
   // build_bit.tcl define CLKOUT0_DIVIDE = 1000 / MHZ (20.000 para 50 MHz, 10.000 para 100 MHz).
   `ifndef CLKOUT0_DIVIDE
   `define CLKOUT0_DIVIDE 20.000
   `endif

   module clk_wiz_0 (
       input  wire clk_in1,
       output wire clk_out1,
       output wire locked
   );
       wire w_clkfb;
       wire w_clkout0;

       MMCME2_BASE #(
           .CLKIN1_PERIOD(10.0),
           .DIVCLK_DIVIDE(1),
           .CLKFBOUT_MULT_F(10.0),
           .CLKOUT0_DIVIDE_F(`CLKOUT0_DIVIDE)
       ) u_mmcm (
           .CLKIN1(clk_in1),
           .CLKFBIN(w_clkfb),
           .CLKFBOUT(w_clkfb),
           .CLKFBOUTB(),
           .CLKOUT0(w_clkout0),
           .CLKOUT0B(),
           .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
           .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
           .LOCKED(locked),
           .PWRDWN(1'b0),
           .RST(1'b0)
       );

       BUFG u_bufg (
           .I(w_clkout0),
           .O(clk_out1)
       );
   endmodule

   `default_nettype wire
   ```

   En `tbs.py`, agregar al final:

   ```python
   # Bitstreams: top -> archivos y XDC. --clk mmcm agrega CLK_GEN.
   CLK_GEN = f"{RTL}/top/clk_gen.v"
   BITS = {
       "top_uart_echo": {"files": UART_RTL + [f"{RTL}/top/top_uart_echo.v"],
                         "xdc": "TP3_FINAL/constraints/basys3_uart_echo.xdc"},
   }
   ```

   En `run.py`: importar `BITS, CLK_GEN` desde `tbs`, y agregar:

   ```python
   def run_bit(top: str, mhz: int, clk: str, defines: list[str] | None = None) -> bool:
       spec = BITS[top]
       out = BUILD / "bit" / f"{top}_{mhz}mhz_{clk}"
       log = out / "vivado.log"
       files = [(REPO / f).as_posix() for f in spec["files"]]
       if clk == "mmcm":
           files.append((REPO / CLK_GEN).as_posix())
       defs = ",".join(defines) if defines else "-"
       rc = run_vivado("build_bit.tcl", log,
                       [top, str(mhz), out.as_posix(), clk, (REPO / spec["xdc"]).as_posix(), defs, *files])
       bad = bad_synth_lines(log)
       for l in bad:
           print(f"  {l}")
       summary = out / "summary.txt"
       wns_ok = False
       if summary.exists():
           text = summary.read_text().strip()
           print(text)
           m = re.search(r"WNS=(-?[0-9.]+)", text)
           wns_ok = m is not None and float(m.group(1)) >= 0.0
       ok = rc == 0 and not bad and wns_ok
       bit = (out / f"{top}.bit").relative_to(REPO).as_posix()
       print(f"{'PASS' if ok else 'FAIL'} bit {top} {mhz} MHz ({clk}) -> {bit}")
       return ok


   def run_program(bit: str) -> bool:
       log = BUILD / "program" / "vivado.log"
       rc = run_vivado("program.tcl", log, [Path(bit).resolve().as_posix()])
       print(f"{'PASS' if rc == 0 else 'FAIL'} program {bit}")
       return rc == 0
   ```

   y en `main`:

   ```python
       pb = sub.add_parser("bit")
       pb.add_argument("top", choices=sorted(BITS))
       pb.add_argument("--mhz", type=int, default=50)
       pb.add_argument("--clk", choices=["wiz", "mmcm"], default="wiz")
       pb.add_argument("--define", action="append", default=[], metavar="NAME",
                       help="repetible; va a synth_design -verilog_define (B-17 usa --define CPU_STUB)")
       sub.add_parser("program").add_argument("bitfile")
       ...
       elif a.cmd == "bit":
           ok = run_bit(a.top, a.mhz, a.clk, a.define)
       elif a.cmd == "program":
           ok = run_program(a.bitfile)
   ```

   Actualizar el docstring de `run.py` con las dos invocaciones nuevas.

   Verificar: `py TP3_FINAL/tools/run.py bit top_uart_echo --mhz 50` → imprime `TOP=top_uart_echo MHZ=50 CLK=wiz WNS=<≥0> WHS=<≥0>` y `PASS bit top_uart_echo 50 MHz (wiz) -> TP3_FINAL/build/bit/top_uart_echo_50mhz_wiz/top_uart_echo.bit`. Tarda unos minutos. Repetir con `--mhz 100`.

5. **Programación.** Crear `TP3_FINAL/tools/program.tcl` con exactamente:

   ```tcl
   # Uso: vivado -mode batch -source program.tcl -tclargs <archivo.bit>
   set bit [lindex $argv 0]
   open_hw_manager
   connect_hw_server
   open_hw_target
   set dev [lindex [get_hw_devices xc7a35t_0] 0]
   current_hw_device $dev
   set_property PROGRAM.FILE $bit $dev
   program_hw_devices $dev
   close_hw_target
   disconnect_hw_server
   close_hw_manager
   ```

6. **Script de PC.** Crear `TP3_FINAL/sw/host/__init__.py` vacío (si no existe) y `TP3_FINAL/sw/host/echo_test.py` con exactamente:

   ```python
   """Prueba de eco contra top_uart_echo (B-05).

   Uso (cwd = TP3_FINAL/sw):
       py -m host.echo_test --port COM5 --count 100000 --burst 256 --seed 1
   Devuelve 0 si no hubo bytes errados ni perdidos, 1 si los hubo, 2 si no se pudo usar el puerto.
   """
   from __future__ import annotations

   import argparse
   import random
   import sys
   import time

   import serial


   def run(port: str, baud: int, count: int, burst: int, seed: int) -> tuple[int, int, int, int, float]:
       """Envía count bytes pseudoaleatorios en ráfagas y compara el eco de cada ráfaga."""
       rng = random.Random(seed)
       sent = received = wrong = lost = 0
       t0 = time.monotonic()
       with serial.Serial(port, baud, timeout=0.05) as ser:
           time.sleep(0.1)
           ser.reset_input_buffer()
           remaining = count
           while remaining > 0:
               n = min(burst, remaining)
               data = bytes(rng.randrange(256) for _ in range(n))
               ser.write(data)
               sent += n
               # Tiempo de línea de la ráfaga (10 bits por byte) dos veces, más 0,5 s de margen.
               deadline = time.monotonic() + 0.5 + 2 * n * 10 / baud
               buf = bytearray()
               while len(buf) < n and time.monotonic() < deadline:
                   buf += ser.read(n - len(buf))
               received += len(buf)
               lost += n - len(buf)
               wrong += sum(1 for a, b in zip(data, buf) if a != b)
               if len(buf) < n:
                   # Faltaron bytes: descartar lo que llegue tarde para que la ráfaga siguiente arranque limpia.
                   time.sleep(0.1)
                   ser.reset_input_buffer()
               remaining -= n
       return sent, received, wrong, lost, time.monotonic() - t0


   def main(argv: list[str] | None = None) -> int:
       p = argparse.ArgumentParser(description="Eco UART contra top_uart_echo")
       p.add_argument("--port", required=True, help="por ejemplo COM5")
       p.add_argument("--baud", type=int, default=115200)
       p.add_argument("--count", type=int, default=100_000)
       p.add_argument("--burst", type=int, default=256)
       p.add_argument("--seed", type=int, default=1)
       a = p.parse_args(argv)
       try:
           sent, received, wrong, lost, dt = run(a.port, a.baud, a.count, a.burst, a.seed)
       except serial.SerialException as e:
           print(f"ERROR: no se pudo usar {a.port}: {e}", file=sys.stderr)
           return 2
       print(f"sent={sent} received={received} wrong={wrong} lost={lost} "
             f"time={dt:.1f}s port={a.port} baud={a.baud} burst={a.burst} seed={a.seed}")
       return 0 if wrong == 0 and lost == 0 else 1


   if __name__ == "__main__":
       sys.exit(main())
   ```

   Verificar sin placa: `cd TP3_FINAL/sw && py -m host.echo_test --port COM99 --count 10` → `ERROR: no se pudo usar COM99: ...` y código 2.

7. **[manual] Corrida a 50 MHz.** Conectar la Basys3 por USB, encenderla.
   1. Puerto: `py -m serial.tools.list_ports -v` → anotar el `COMx` de la Basys3 (el que dice `USB Serial Port` / FTDI).
   2. `py TP3_FINAL/tools/run.py program TP3_FINAL/build/bit/top_uart_echo_50mhz_wiz/top_uart_echo.bit` → `PASS program`. LED 3 encendido (locked).
   3. `cd TP3_FINAL/sw && py -m host.echo_test --port COMx --count 100000 --burst 256 --seed 1` → `sent=100000 received=100000 wrong=0 lost=0 ...`, código 0. LED 0 parpadea durante la corrida; LED 1 y LED 2 apagados al final.
   4. Ráfagas de prueba: repetir con `--count 4096 --burst 1`, `--burst 16` y `--burst 256`; anotar los resultados y los LED 1/2.
   5. Corrida rota a propósito: `py -m host.echo_test --port COMx --count 1000 --baud 57600` → `wrong` o `lost` mayores que 0 y código 1. Después, botón central (btnC) para borrar los LED pegajosos.

8. **[manual] Corrida a 100 MHz.** Igual que el paso 7 (subpasos 2 y 3) con `TP3_FINAL/build/bit/top_uart_echo_100mhz_wiz/top_uart_echo.bit`.

9. **`uart.md`.** Reemplazar `Pendiente (B-05).` de "Resultados en placa" por la tabla (una fila por corrida de los pasos 7 y 8, incluidas las de ráfaga y la rota):

   ```markdown
   | Clock | Reloj | DIV | Error baud | Ráfaga | Enviados | Recibidos | Errados | Perdidos | Tiempo | WNS | WHS | LUT | FF | Fecha | Commit |
   | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
   ```

   WNS/WHS de `summary.txt`; LUT/FF de `util.rpt` ("Slice LUTs", "Slice Registers"); commit = `git rev-parse --short HEAD` del bitstream.

   Reemplazar `Pendiente (B-05).` de "Estado" por la frase final, con los hashes reales (`git log --oneline -- TP3_FINAL/VIVADO/TP_FINAL/rtl/uart/`):

   ```markdown
   UART reutilizada de TP2 con cambios: divisor redondeado y OVERSAMPLE fijo (<hash B-02>), estilo y ASYNC_REG
   (<hashes B-03>), H-7 en uart_tx (<hash>), stop a mitad de bit y framing sin valid en uart_rx (<hash B-04>).
   Validada en placa a 50 y 100 MHz con 100 000 bytes de eco sin errores ni pérdidas.
   ```

## Validación

```bash
py TP3_FINAL/tools/run.py tbs                                  # 7/7 PASS (incluye tb_uart_echo)
py TP3_FINAL/tools/run.py bit top_uart_echo --mhz 50           # PASS, WNS ≥ 0
py TP3_FINAL/tools/run.py bit top_uart_echo --mhz 100          # PASS, WNS ≥ 0
```

[manual] `py -m host.echo_test --port COMx --count 100000 --seed 1` (cwd `TP3_FINAL/sw`) → `wrong=0 lost=0`, código 0, en las dos frecuencias.

## Listo cuando

- [ ] `tb_uart_echo` pasa.
- [ ] Los dos bitstreams se generan por script, con WNS y WHS ≥ 0, sin latches ni multi-driven.
- [ ] [manual] Eco de 100 000 bytes con 0 errados y 0 perdidos a 50 MHz y a 100 MHz.
- [ ] [manual] La corrida a 57600 devuelve código 1.
- [ ] `uart.md` tiene la tabla de resultados y la frase de "Estado" con los commits.

## No hacer

- No crear el Clock Wizard en el GUI ni versionar `.xci` (D-13).
- No agrandar el eco con una FIFO si aparece overrun en ráfagas largas: registrar el resultado y avisar (D-12).
- No modificar la UART en este issue. Si el eco falla y el TB pasa, detenerse y preguntar.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `create_ip` o `generate_target` falla en batch | Usar la alternativa: `py TP3_FINAL/tools/run.py bit top_uart_echo --mhz 50 --clk mmcm` (y 100). Anotar en `uart.md` que se usó `mmcm` |
| `build_bit: relojes insuficientes` en modo `wiz` | El XDC del IP no se aplicó: pasar a `--clk mmcm` y anotarlo |
| WNS < 0 | No debería pasar con la UART sola a 100 MHz: pegar `timing.rpt` (peor camino) en el PR y detenerse |
| `bad_synth_lines` marca líneas del IP del Wizard (no de nuestros `.v`) | Pegarlas en el PR y detenerse a preguntar; no relajar la expresión regular |
| `program` no encuentra `xc7a35t_0` | [manual] Revisar cable USB, interruptor de encendido y que no haya otro Vivado con el hardware abierto |
| `echo_test` da `lost` > 0 solo con `--burst 256` y el LED 2 (overrun) encendido | Registrarlo como limitación del eco (D-12) y repetir con `--burst 64`; la UART se da por buena si `--burst 64` da 0/0 |
| `echo_test` da errores con cualquier ráfaga | Revisar que el puerto sea el de la Basys3 y la velocidad 115200; si persiste, detenerse y preguntar |

## Commits

1. `uart: top de eco con retención de 1 byte y su TB`
2. `tools: bitstream non-project con Clock Wizard por script y programación`
3. `sw-host: echo_test.py`
4. `docs: resultados del eco en placa y estado de la UART`

## Depende de / bloquea

Depende de: B-02, B-03, B-04.
Bloquea: cierre de M0; B-17 (reutiliza `build_bit.tcl`, `program.tcl` y el patrón del top).

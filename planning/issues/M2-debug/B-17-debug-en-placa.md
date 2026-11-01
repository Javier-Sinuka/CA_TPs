# B-17 · Debug Unit + stub en la placa

`M` · etiquetas `debug-unit` `hw` · milestone M2 · **Modelo sugerido:** Sonnet (pasos de placa: los ejecuta una persona) · [índice](../README.md)

## Objetivo
`top_debug` (Clock Wizard + reset + `system` con `cpu_stub`) sintetizado a 50 MHz con timing cumplido, y el guion de B-16 corrido 20 veces seguidas desde la PC contra la placa, sin reprogramarla.

## Antes de empezar
- Leer: `interfaz_cpu.md` §7, `decisiones.md` D-10, D-13, D-27; B-05 (cómo quedó `top_uart_echo.v`, `build_bit.tcl` y su XDC); B-16 (guion).
- Precondiciones: B-05 cerrado (eco en placa y `run.py bit` funcionando), B-16 cerrado, B-23 cerrado (`sw/host/link.py`).
- Hardware: Basys3 por USB; anotar el puerto COM (Administrador de dispositivos → "USB Serial Port (COMx)").
- Rama: `b/B-17-debug-placa`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/rtl/top/top_debug.v` | Paso 1 |
| crear | `TP3_FINAL/constraints/basys3_debug.xdc` | Paso 2 |
| crear | `TP3_FINAL/sw/host/guion_debug.py` | Paso 4 |
| modificar | lista de fuentes de `build_bit.tcl` / `run.py bit` | Paso 3 |
| modificar | `TP3_FINAL/doc/documentation/debug.md` | Paso 6 (crear si no existe) |

## Pasos
1. `rtl/top/top_debug.v`. El bloque de reloj y el sincronizador de reset se copian **tal cual** de `top_uart_echo.v` (B-05). El código de abajo asume que B-05 instancia `clk_wiz_0` con puertos `clk_in1`, `clk_out1`, `locked`; si B-05 usa otro nombre (o `clk_gen.v` con `MMCME2_BASE`), usar el de B-05 sin cambiar nada más.

```verilog
`timescale 1ns/1ps
`default_nettype none

// Top de placa: reloj, reset y pines alrededor de system (D-27). El CPU es el
// stub: se sintetiza con el define CPU_STUB.
module top_debug #(
    parameter CLOCK_FREQ = 50_000_000      // lo fija build_bit.tcl a partir de --mhz
)(
    input  wire        i_clock,            // 100 MHz, W5
    input  wire        i_btn_reset,        // btnC, U18
    input  wire        i_rx,               // RsRx, B18
    output wire        o_tx,               // RsTx, A18
    output wire [15:0] o_led
);
    wire w_clk;
    wire w_locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1 (i_clock),
        .clk_out1(w_clk),
        .locked  (w_locked)
    );

    // Reset único del diseño (D-10): botón o Wizard sin enganchar, 2 FF.
    (* ASYNC_REG = "TRUE" *) reg [1:0] r_reset_sync = 2'b11;
    always @(posedge w_clk) begin
        r_reset_sync <= {r_reset_sync[0], i_btn_reset | ~w_locked};
    end
    wire w_reset = r_reset_sync[1];

    wire [7:0] w_leds;

    system #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE (115_200),
        .HALT_AT   (20)
    ) u_system (
        .i_clock(w_clk),
        .i_reset(w_reset),
        .i_rx   (i_rx),
        .o_tx   (o_tx),
        .o_leds (w_leds)
    );

    assign o_led = {w_locked, 7'd0, w_leds};
endmodule

`default_nettype wire
```

   LEDs resultantes: `LD0` conmuta por byte recibido, `LD1` framing pegajoso, `LD2` overrun pegajoso, `LD3` `halted`, `LD4..LD7` estado de la FSM (`o_state`), `LD15` `locked`.

2. `constraints/basys3_debug.xdc`, completo:

```tcl
## Reloj de 100 MHz
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports i_clock]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports i_clock]

## Botón central y UART USB
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports i_btn_reset]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports i_rx]
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports o_tx]

## LEDs
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {o_led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {o_led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {o_led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {o_led[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {o_led[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {o_led[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {o_led[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {o_led[7]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {o_led[8]}]
set_property -dict { PACKAGE_PIN V3  IOSTANDARD LVCMOS33 } [get_ports {o_led[9]}]
set_property -dict { PACKAGE_PIN W3  IOSTANDARD LVCMOS33 } [get_ports {o_led[10]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {o_led[11]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {o_led[12]}]
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports {o_led[13]}]
set_property -dict { PACKAGE_PIN P1  IOSTANDARD LVCMOS33 } [get_ports {o_led[14]}]
set_property -dict { PACKAGE_PIN L1  IOSTANDARD LVCMOS33 } [get_ports {o_led[15]}]

## Entradas asíncronas y salidas sin relación de timing
set_false_path -from [get_ports {i_btn_reset i_rx}]
set_false_path -to   [get_ports {o_tx o_led[*]}]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
```

3. Build. Registrar `top_debug` en la lista de fuentes que usa `build_bit.tcl` **de la misma forma en que B-05 registró `top_uart_echo`**, con estas fuentes: `rtl/uart/{baud_gen,uart_rx,uart_tx,uart_if}.v`, `rtl/debug/{debug_unit,cpu_stub,imem,system}.v`, `rtl/debug/cpu_ports.vh` (como include), `rtl/top/top_debug.v`, y `constraints/basys3_debug.xdc`. El top necesita el define `CPU_STUB`: si `build_bit.tcl` / `run.py bit` no aceptan defines, agregar el argumento `--define NOMBRE` (repetible) que se pasa a `synth_design` como `-verilog_define NOMBRE=1`.
   Correr: `py TP3_FINAL/tools/run.py bit top_debug --mhz 50 --define CPU_STUB`.
   Verificar en los reportes que genera `build_bit.tcl`: sin `inferring latch` ni `multi-driven`; **WNS ≥ 0** y **WHS ≥ 0**. Anotar WNS, WHS, LUT y FF totales, y LUT/FF de `u_system/u_debug` (`report_utilization -hierarchical`; si `build_bit.tcl` no lo genera, agregarlo a sus reportes).
4. `sw/host/guion_debug.py`: corre el guion de B-16 contra la placa usando **solo** la API pública de `sw/host/link.py` (B-23), y compara cada dump con `stub_model.stub_dump` (igualdad de `Dump`). Uso:

```
cd TP3_FINAL/sw
py -m host.guion_debug --port COM5 --repeat 20
```

   Pasos por repetición, idénticos a la tabla de B-16 (`V`, `L A`, 5×`S`, `R`, `D`, `X`, `L B`, `R B`, `invalido`, `D final`), con las mismas palabras `progA`/`progB` y los mismos dumps esperados (`stub_dump(k, 20)` para `S k`, `stub_dump(20, 20)` para `R`/`D`). Para el comando inválido (`7A` → `45 01`) usar `link.raw_error(0x7A)` de B-23 y verificar que devuelve `1` (no abrir el puerto por fuera de `link.py`). Imprime `rep N: OK` o `rep N: FAIL <paso>: <detalle>`; al final `PASS guion_debug: 20/20` y código 0, o `FAIL guion_debug: k/20` y código 1.
5. En la placa (persona): programar el bitstream (Hardware Manager → Program Device, o el script de programación de B-05 si existe). Comprobar `LD15` encendido. Correr el comando del paso 4. Pegar la salida en el PR.
6. `doc/documentation/debug.md`: sección "Placa con stub" con fecha, commit, WNS, WHS, LUT/FF (total y Debug Unit), puerto usado, resultado `20/20` y el significado de los LEDs del paso 1.

## Validación
```
py TP3_FINAL/tools/run.py bit top_debug --mhz 50 --define CPU_STUB → código 0, WNS ≥ 0
cd TP3_FINAL/sw; py -m host.guion_debug --port COMx --repeat 20 → "PASS guion_debug: 20/20"
```
Prueba de que el script detecta fallas: correrlo con `--port` de la placa y la placa en reset (mantener `btnC`) → tiene que terminar en `FAIL` con código 1 (timeout de `V`).

## Listo cuando
- [ ] Síntesis sin latches ni `multi-driven`, timing cumplido a 50 MHz (WNS y WHS ≥ 0, anotados en `debug.md`).
- [ ] El guion pasa en la placa 20 veces seguidas sin reprogramar la FPGA (`PASS guion_debug: 20/20`).
- [ ] `debug.md` tiene la sección "Placa con stub" completa.

## No hacer
- No cambiar `system.v` ni `debug_unit.v` para "hacer andar" la placa: si algo anda en simulación y no en la placa, detenerse y reportar (es un hallazgo).
- No subir `BAUD_RATE` ni cambiar la frecuencia.

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| `LD15` apagado | El Wizard no engancha: revisar que el XDC tenga `create_clock` en `i_clock` y que el Wizard reciba 100 MHz |
| `V` no responde | Puerto equivocado o velocidad distinta de 115200; probar con `echo_test.py` de B-05 para descartar la UART |
| `LD1` (framing) encendido | Baud desalineado: el `CLOCK_FREQ` del top no es la salida del Wizard (revisar `--mhz`) |
| Falla 1 de cada N repeticiones | Anotar el paso; correr `--repeat 100` y reportar: es un hallazgo para B-16 |
| `clk_wiz_0` no encontrado en síntesis | El IP no se generó: usar el mismo mecanismo que B-05 |

## Commits
1. `debug: top_debug y XDC de la placa`
2. `tools: build de top_debug con define CPU_STUB`
3. `sw-host: guion_debug para la placa`
4. `docs: resultados de la Debug Unit en placa`

## Depende de / bloquea
Depende de: B-05, B-16, B-23. Bloquea: cierre de M2, B-25 (prueba contra placa), B-29. Se cierra junto con el último criterio de B-23 (es la misma corrida).

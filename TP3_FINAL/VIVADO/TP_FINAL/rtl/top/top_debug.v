`timescale 1ns/1ps
`default_nettype none

// Top de placa de la Debug Unit (B-17): reloj, reset y pines alrededor de system (D-27).
// El CPU lo elige el define de síntesis: con CPU_STUB (run.py bit ... --define CPU_STUB) es el stub.
// LEDs: [0] conmuta por byte recibido, [1] framing pegajoso, [2] overrun pegajoso, [3] halted,
//       [7:4] estado de la FSM de la Debug Unit, [15] locked del Wizard.
module top_debug #(
    parameter integer CLOCK_FREQ = 50_000_000,   // build_bit.tcl lo fija con -generic = salida del Wizard
    parameter integer BAUD_RATE  = 115_200
)(
    input  wire        i_clk100,      // W5, 100 MHz de la placa
    input  wire        i_btn_reset,   // U18 (btnC), activo en alto
    input  wire        i_rx,          // B18
    output wire        o_tx,          // A18
    output wire [15:0] o_led
);
    wire w_clock;
    wire w_locked;

    // Clock Wizard clk_wiz_0 creado por build_bit.tcl (o clk_gen.v con --clk mmcm): mismo nombre y
    // puertos clk_in1, clk_out1, locked. Sin puerto de reset (USE_RESET = false).
    clk_wiz_0 u_clk (
        .clk_in1(i_clk100),
        .clk_out1(w_clock),
        .locked(w_locked)
    );

    // Reset único del diseño (D-10): botón o Wizard sin enganchar, sincronizado con 2 FF.
    // El valor inicial arranca en reset (único valor inicial permitido fuera de memorias).
    (* ASYNC_REG = "TRUE" *) reg [1:0] r_reset_sync = 2'b11;
    always @(posedge w_clock) begin
        r_reset_sync <= {r_reset_sync[0], i_btn_reset | ~w_locked};
    end
    wire w_reset = r_reset_sync[1];

    wire [7:0] w_leds;

    system #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .HALT_AT(20)
    ) u_system (
        .i_clock(w_clock),
        .i_reset(w_reset),
        .i_rx(i_rx),
        .o_tx(o_tx),
        .o_leds(w_leds)
    );

    assign o_led = {w_locked, 7'd0, w_leds};
endmodule

`default_nettype wire

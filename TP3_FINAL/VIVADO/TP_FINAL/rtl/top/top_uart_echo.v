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

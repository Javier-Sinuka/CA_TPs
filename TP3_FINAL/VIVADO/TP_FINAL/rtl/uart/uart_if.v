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

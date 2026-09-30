module uart_top #(
    parameter CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 9600
)(
    input wire i_clock,
    input wire i_reset,
    input wire i_rx,
    output wire o_tx,
    output wire [7:0] o_leds,
    output wire o_reset_led,
    output wire o_tx_busy_led,
    output reg o_error_led
);
    // Basys 3 button input: two-stage synchronizer, initially held in reset.
    // Vivado implements the initial value with the FPGA register INIT attribute.
    (* ASYNC_REG = "TRUE" *) reg [1:0] r_reset_sync = 2'b11;

    wire w_reset;
    wire w_baud_tick;
    wire w_rx_valid;
    wire [7:0] w_rx_data;
    wire w_rx_error;
    wire w_tx_busy;
    wire w_tx_start;
    wire [7:0] w_tx_data;
    wire w_error;

    // Both assertion and release reach the design through the synchronizer.
    always @(posedge i_clock) begin
        r_reset_sync <= {r_reset_sync[0], i_reset};
    end

    assign w_reset = r_reset_sync[1];

    baud_gen #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        // The existing uart_rx and uart_tx counters require 16 ticks per bit.
        .OVERSAMPLE(16)
    ) u_baud_gen (
        .i_clock(i_clock),
        .i_reset(w_reset),
        .o_baud_tick(w_baud_tick)
    );

    // uart_rx already synchronizes the asynchronous serial input internally.
    uart_rx u_uart_rx (
        .i_clock(i_clock),
        .i_reset(w_reset),
        .i_baud_tick(w_baud_tick),
        .i_rx(i_rx),
        .o_valid(w_rx_valid),
        .o_data(w_rx_data),
        .o_error(w_rx_error)
    );

    // This module contains interface_rx, the command FSM, ALU and interface_tx.
    interface_circuit u_interface_circuit (
        .i_clock(i_clock),
        .i_reset(w_reset),
        .i_rx_valid(w_rx_valid),
        .i_rx_data(w_rx_data),
        .i_rx_error(w_rx_error),
        .i_tx_busy(w_tx_busy),
        .o_tx_start(w_tx_start),
        .o_tx_data(w_tx_data),
        .o_error(w_error)
    );

    uart_tx u_uart_tx (
        .i_clock(i_clock),
        .i_reset(w_reset),
        .i_baud_tick(w_baud_tick),
        .i_start(w_tx_start),
        .i_data(w_tx_data),
        .o_busy(w_tx_busy),
        .o_tx(o_tx)
    );

    // The TX interface holds the latest queued ALU result until the next one.
    assign o_leds = w_tx_data;
    assign o_reset_led = w_reset;
    assign o_tx_busy_led = w_tx_busy;

    // Latch the one-clock error pulse so it remains visible until reset.
    always @(posedge i_clock) begin
        if (w_reset) begin
            o_error_led <= 1'b0;
        end else if (w_error) begin
            o_error_led <= 1'b1;
        end
    end
endmodule

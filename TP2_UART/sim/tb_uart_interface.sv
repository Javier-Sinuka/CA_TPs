`timescale 1ns/1ps

module tb_uart_interface;
    localparam CLOCK_PERIOD_NS = 10;
    localparam CLOCK_FREQ = 100_000_000;
    // Accelerate simulation: eight clock cycles per tick, 16 ticks per bit.
    localparam BAUD_RATE = 781_250;
    localparam BIT_PERIOD_NS = 128 * CLOCK_PERIOD_NS;

    reg i_clock = 1'b0;
    reg i_reset = 1'b1;
    reg i_rx = 1'b1;
    wire w_baud_tick;
    wire w_rx_valid;
    wire [7:0] w_rx_data;
    wire w_rx_error;
    wire w_tx_busy;
    wire w_tx_start;
    wire [7:0] w_tx_data;
    wire w_tx;
    wire w_error;
    reg [7:0] r_expected [0:31];
    integer r_expected_count = 0;
    integer r_received_count = 0;

    baud_gen #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(16)
    ) u_baud_gen (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .o_baud_tick(w_baud_tick)
    );

    uart_rx u_uart_rx (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_baud_tick(w_baud_tick),
        .i_rx(i_rx),
        .o_valid(w_rx_valid),
        .o_data(w_rx_data),
        .o_error(w_rx_error)
    );

    interface_circuit UUT (
        .i_clock(i_clock),
        .i_reset(i_reset),
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
        .i_reset(i_reset),
        .i_baud_tick(w_baud_tick),
        .i_start(w_tx_start),
        .i_data(w_tx_data),
        .o_busy(w_tx_busy),
        .o_tx(w_tx)
    );

    always #(CLOCK_PERIOD_NS / 2) i_clock = ~i_clock;

    always @(posedge i_clock) begin
        if (!i_reset && w_error) $fatal(1, "Unexpected receive/overflow error");
    end

    // Independent serial stimulus: time-based 8N1 frames, LSB first.
    // It does not use internal baud ticks or UART state to drive the input.
    task automatic send_frame(input [7:0] i_data);
        @(negedge i_clock);
        i_rx = 1'b0;
        #(BIT_PERIOD_NS);
        for (integer r_bit = 0; r_bit < 8; r_bit = r_bit + 1) begin
            i_rx = i_data[r_bit];
            #(BIT_PERIOD_NS);
        end
        i_rx = 1'b1;
        #(BIT_PERIOD_NS);
    endtask

    task automatic command(input [7:0] i_a, input [7:0] i_b,
                           input [7:0] i_op, input [7:0] i_result);
        r_expected[r_expected_count] = i_result;
        r_expected_count = r_expected_count + 1;
        send_frame(i_a);
        send_frame(i_b);
        send_frame(i_op);
    endtask

    // Decode the actual serial output, including start/stop validation.
    initial begin : serial_monitor
        reg [7:0] r_captured;
        wait (!i_reset);
        forever begin
            @(negedge w_tx);
            #(BIT_PERIOD_NS / 2);
            if (w_tx !== 1'b0) $fatal(1, "Invalid TX start bit");
            for (integer r_bit = 0; r_bit < 8; r_bit = r_bit + 1) begin
                #(BIT_PERIOD_NS);
                r_captured[r_bit] = w_tx;
            end
            #(BIT_PERIOD_NS);
            if (w_tx !== 1'b1) $fatal(1, "Invalid TX stop bit");
            if (r_received_count >= r_expected_count)
                $fatal(1, "Unexpected serial result %02h", r_captured);
            if (r_captured !== r_expected[r_received_count])
                $fatal(1, "Serial result %0d: expected %02h, got %02h",
                       r_received_count, r_expected[r_received_count], r_captured);
            r_received_count = r_received_count + 1;
        end
    end

    initial begin
        repeat (4) @(negedge i_clock);
        i_reset = 1'b0;
        repeat (8) @(negedge i_clock);
        // Consecutive commands; the independent monitor receives replies in parallel.
        command(8'h12, 8'h34, 8'h20, 8'h46);
        command(8'h03, 8'h05, 8'h22, 8'hFE);
        command(8'hF0, 8'h5A, 8'h24, 8'h50);
        command(8'hF0, 8'h5A, 8'h25, 8'hFA);
        command(8'hF0, 8'h5A, 8'h26, 8'hAA);
        command(8'h80, 8'h02, 8'h03, 8'hE0);
        command(8'h80, 8'h02, 8'h02, 8'h20);
        command(8'hF0, 8'h5A, 8'h27, 8'h05);
        command(8'hFF, 8'h01, 8'h20, 8'h00);
        command(8'h10, 8'h20, 8'h00, 8'h00);
        command(8'h00, 8'h01, 8'h22, 8'hFF);
        command(8'h05, 8'h0A, 8'h20, 8'h0F);
        wait (r_received_count == r_expected_count);
        #(2 * 10 * BIT_PERIOD_NS);
        $display("PASS tb_uart_interface: %0d serial commands/replies", r_received_count);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "UART integration timeout: received=%0d expected=%0d",
               r_received_count, r_expected_count);
    end
endmodule

`timescale 1ns/1ps

module tb_uart_top;
    parameter BAUD_RATE = 781_250;
    localparam CLOCK_FREQ = 100_000_000;
    localparam CLOCK_PERIOD_NS = 10;
    // Independent host timing, not derived from the DUT's baud ticks.
    localparam BIT_PERIOD_NS = 1_000_000_000 / BAUD_RATE;

    reg i_clock = 1'b0;
    reg i_reset = 1'b0;
    reg i_rx = 1'b1;
    wire o_tx;
    wire [7:0] o_leds;
    wire o_reset_led;
    wire o_tx_busy_led;
    wire o_error_led;
    integer r_response_count = 0;

    uart_top #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) UUT (.*);

    always #(CLOCK_PERIOD_NS / 2) i_clock = ~i_clock;

    task automatic check(input bit i_condition, input string i_message);
        if (!i_condition) $fatal(1, "%s", i_message);
    endtask

    task automatic send_frame(input [7:0] i_data, input bit i_stop);
        @(negedge i_clock);
        i_rx = 1'b0;
        #(BIT_PERIOD_NS);
        for (integer r_bit = 0; r_bit < 8; r_bit = r_bit + 1) begin
            i_rx = i_data[r_bit];
            #(BIT_PERIOD_NS);
        end
        i_rx = i_stop;
        #(BIT_PERIOD_NS);
        i_rx = 1'b1;
    endtask

    task automatic receive_response(input [7:0] i_expected);
        reg [7:0] r_captured;
        @(negedge o_tx);
        #(BIT_PERIOD_NS / 2);
        check(o_tx === 1'b0 && o_tx_busy_led === 1'b1, "TX start/busy");
        check(o_leds === i_expected, "LEDs must display the queued result");
        for (integer r_bit = 0; r_bit < 8; r_bit = r_bit + 1) begin
            #(BIT_PERIOD_NS);
            r_captured[r_bit] = o_tx;
        end
        #(BIT_PERIOD_NS);
        check(o_tx === 1'b1, "TX stop bit");
        if (r_captured !== i_expected)
            $fatal(1, "Serial result: expected %02h, got %02h", i_expected, r_captured);
        r_response_count = r_response_count + 1;
        wait (o_tx_busy_led === 1'b0);
        #(BIT_PERIOD_NS);
        check(o_leds === i_expected && o_error_led === 1'b0,
              "Result must remain visible after TX completes, without errors");
    endtask

    task automatic command(input [7:0] i_a, input [7:0] i_b,
                           input [7:0] i_op, input [7:0] i_expected);
        fork
            begin
                send_frame(i_a, 1);
                send_frame(i_b, 1);
                send_frame(i_op, 1);
            end
            receive_response(i_expected);
        join
    endtask

    task automatic reset_board;
        // Change the button away from clock edges, as on the physical board.
        @(negedge i_clock);
        #2;
        i_reset = 1'b1;
        repeat (6) @(negedge i_clock);
        check(o_reset_led === 1'b1 && o_tx === 1'b1 && o_leds === 8'h00 &&
              o_tx_busy_led === 1'b0 && o_error_led === 1'b0,
              "Button must reset UART, data and error status");
        #3;
        i_reset = 1'b0;
        repeat (6) @(negedge i_clock);
        check(o_reset_led === 1'b0, "Synchronized reset release");
        #(2 * BIT_PERIOD_NS);
    endtask

    initial begin
        // The FPGA INIT value provides reset even with the button released.
        #1;
        check(o_reset_led === 1'b1, "Power-up reset");
        repeat (6) @(negedge i_clock);
        check(o_reset_led === 1'b0 && o_tx === 1'b1 && o_leds === 8'h00 &&
              o_tx_busy_led === 1'b0 && o_error_led === 1'b0, "Power-up idle state");

        command(8'h12, 8'h34, 8'h20, 8'h46); // ADD
        command(8'h03, 8'h05, 8'h22, 8'hFE); // SUB
        command(8'hF0, 8'h5A, 8'h24, 8'h50); // AND
        command(8'hF0, 8'h5A, 8'h25, 8'hFA); // OR
        command(8'hF0, 8'h5A, 8'h26, 8'hAA); // XOR
        command(8'h80, 8'h02, 8'h03, 8'hE0); // SRA
        command(8'h80, 8'h02, 8'h02, 8'h20); // SRL
        command(8'hF0, 8'h5A, 8'h27, 8'h05); // NOR
        command(8'hFF, 8'h01, 8'h20, 8'h00); // Eight-bit wrap
        command(8'h10, 8'h20, 8'h00, 8'h00); // Unknown opcode

        send_frame(8'h55, 1);
        send_frame(8'h66, 0);
        #(3 * BIT_PERIOD_NS);
        check(o_error_led === 1'b1, "Framing error must light LD10");
        #(3 * BIT_PERIOD_NS);
        check(o_error_led === 1'b1 && o_tx_busy_led === 1'b0,
              "Error LED must hold after the internal error pulse");
        reset_board();
        command(8'h06, 8'h07, 8'h20, 8'h0D);

        send_frame(8'hEE, 1);
        reset_board();
        command(8'h02, 8'h03, 8'h20, 8'h05);

        // Reset during a reply: TX returns to idle and the next command is valid.
        send_frame(8'hAA, 1);
        send_frame(8'hBB, 1);
        send_frame(8'h20, 1);
        wait (o_tx_busy_led === 1'b1);
        #(2 * BIT_PERIOD_NS);
        reset_board();
        command(8'h07, 8'h08, 8'h20, 8'h0F);

        $display("PASS tb_uart_top: %0d replies, reset and board LEDs, baud=%0d",
                 r_response_count, BAUD_RATE);
        $finish;
    end

    initial begin
        #(1000 * BIT_PERIOD_NS);
        $fatal(1, "UART TOP timeout");
    end
endmodule

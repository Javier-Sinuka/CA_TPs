module tb_uart_rx;
    // Parameters
    parameter CLOCK_PERIOD_NS = 10;
    parameter TICK_DIV = 8;
    parameter OVERSAMPLE = 16;
    localparam integer TAG_WIDTH = 8 * 12;

    // DUT inputs
    reg i_clock;
    reg i_baud_tick;
    reg i_reset;
    reg i_rx;

    // DUT outputs
    wire o_valid;
    wire [7:0] o_data;
    wire o_error;

    // Variables for automatic checking
    integer pass_count;
    integer fail_count;
    integer tick_div_count;

    // UART RX DUT
    uart_rx UUT (
        .i_clock(i_clock),
        .i_baud_tick(i_baud_tick),
        .i_reset(i_reset),
        .i_rx(i_rx),
        .o_valid(o_valid),
        .o_data(o_data),
        .o_error(o_error)
    );

    // 100 MHz simulation clock period (10 ns)
    always #(CLOCK_PERIOD_NS / 2) i_clock = ~i_clock;

    // Generate a one-cycle baud tick every TICK_DIV clocks
    always @(posedge i_clock) begin
        if (i_reset) begin
            tick_div_count <= 0;
            i_baud_tick <= 1'b0;
        end else if (tick_div_count == TICK_DIV - 1) begin
            tick_div_count <= 0;
            i_baud_tick <= 1'b1;
        end else begin
            tick_div_count <= tick_div_count + 1;
            i_baud_tick <= 1'b0;
        end
    end

    task automatic wait_baud_ticks;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge i_baud_tick);
                #1;
            end
        end
    endtask

    task automatic drive_bit;
        input bit_value;
        begin
            @(negedge i_clock);
            i_rx = bit_value;
            wait_baud_ticks(OVERSAMPLE);
        end
    endtask

    task automatic send_frame;
        input [7:0] data;
        input stop_value;
        integer bit_idx;
        begin
            drive_bit(1'b0);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                drive_bit(data[bit_idx]);
            end
            drive_bit(stop_value);
            @(negedge i_clock);
            i_rx = 1'b1;
            wait_baud_ticks(2);
        end
    endtask

    task automatic send_false_start;
        begin
            @(negedge i_clock);
            i_rx = 1'b0;
            wait_baud_ticks(OVERSAMPLE / 4);
            @(negedge i_clock);
            i_rx = 1'b1;
            wait_baud_ticks(OVERSAMPLE);
        end
    endtask

    task automatic check_data;
        input [7:0] expected;
        input [TAG_WIDTH-1:0] tag;
        begin
            if (o_data === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %s | DATA=0x%02h", tag, o_data);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %s | EXPECTED=0x%02h GOT=0x%02h", tag, expected, o_data);
            end
        end
    endtask

    task automatic check_valid_and_error;
        input expected_valid;
        input expected_error;
        input [TAG_WIDTH-1:0] tag;
        begin
            if (o_valid === expected_valid) begin
                pass_count = pass_count + 1;
                $display("PASS %s | VALID=%b", tag, o_valid);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %s | EXPECTED VALID=%b GOT=%b", tag, expected_valid, o_valid);
            end
            if (o_error === expected_error) begin
                pass_count = pass_count + 1;
                $display("PASS %s | ERROR=%b", tag, o_error);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %s | EXPECTED ERROR=%b GOT=%b", tag, expected_error, o_error);
            end
        end
    endtask

    task automatic wait_and_check_frame;
        input [7:0] expected_data;
        input expected_error;
        input [TAG_WIDTH-1:0] tag;
        begin
            @(posedge o_valid);
            #1;
            check_valid_and_error(1'b1, expected_error, tag);
            check_data(expected_data, tag);
            @(posedge i_clock);
            #1;
            if (o_valid === 1'b0) begin
                pass_count = pass_count + 1;
                $display("PASS %s | Valid pulse width OK", tag);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %s | Valid stayed high too long", tag);
            end
        end
    endtask

    task automatic check_no_valid;
        input [TAG_WIDTH-1:0] tag;
        begin
            if (o_valid === 1'b0) begin
                pass_count = pass_count + 1;
                $display("PASS %s | No valid pulse", tag);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %s | Unexpected valid pulse", tag);
            end
            if (o_error === 1'b0) begin
                pass_count = pass_count + 1;
                $display("PASS %s | No error pulse", tag);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %s | Unexpected error pulse", tag);
            end
        end
    endtask

    initial begin
        i_clock = 1'b0;
        i_baud_tick = 1'b0;
        i_reset = 1'b1;
        i_rx = 1'b1;
        pass_count = 0;
        fail_count = 0;
        tick_div_count = 0;

        $display("Starting UART RX testbench...");
        $display("CLOCK_PERIOD_NS=%0d TICK_DIV=%0d OVERSAMPLE=%0d", CLOCK_PERIOD_NS, TICK_DIV, OVERSAMPLE);
        repeat (4) @(posedge i_clock);
        @(negedge i_clock);
        i_reset = 1'b0;

        $display("TEST T1 | Receive 0xA5");
        fork
            send_frame(8'hA5, 1'b1);
            wait_and_check_frame(8'hA5, 1'b0, "T1");
        join

        $display("TEST T2 | Receive 0x00");
        fork
            send_frame(8'h00, 1'b1);
            wait_and_check_frame(8'h00, 1'b0, "T2");
        join

        $display("TEST T3 | Receive 0xFF");
        fork
            send_frame(8'hFF, 1'b1);
            wait_and_check_frame(8'hFF, 1'b0, "T3");
        join

        $display("TEST T4 | False start glitch should be ignored");
        fork
            send_false_start();
            begin
                wait_baud_ticks(OVERSAMPLE + 4);
                check_no_valid("T4");
            end
        join

        $display("TEST T5 | Framing error with stop bit low");
        fork
            send_frame(8'h5C, 1'b0);
            wait_and_check_frame(8'h5C, 1'b1, "T5");
        join

        $display("TEST T6 | Two sequential frames 0x41 then 0x42");
        fork
            begin
                send_frame(8'h41, 1'b1);
                send_frame(8'h42, 1'b1);
            end
            begin
                wait_and_check_frame(8'h41, 1'b0, "T6A");
                wait_and_check_frame(8'h42, 1'b0, "T6B");
            end
        join

        $display("--------------------------------------------");
        $display("Test summary: PASS=%0d FAIL=%0d TOTAL=%0d", pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0) $display("All tests PASSED.");
        else $display("Some tests FAILED.");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("TIMEOUT! Simulation did not finish in expected time.");
        $finish;
    end
endmodule

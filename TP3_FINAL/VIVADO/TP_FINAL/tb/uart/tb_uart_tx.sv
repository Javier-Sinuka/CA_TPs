module tb_uart_tx;
    // Parameters
    parameter CLOCK_PERIOD_NS = 10;
    parameter TICK_DIV = 8;
    parameter OVERSAMPLE = 16;
    localparam integer TAG_WIDTH = 8 * 8;

    // DUT inputs
    reg i_clock;
    reg i_baud_tick;
    reg i_reset;
    reg i_start;
    reg [7:0] i_data;

    // DUT outputs
    wire o_busy;
    wire o_tx;

    // Variables for automatic checking
    integer pass_count;
    integer fail_count;
    integer tick_div_count;

    // UART TX DUT
    uart_tx UUT (
        .i_clock(i_clock),
        .i_baud_tick(i_baud_tick),
        .i_reset(i_reset),
        .i_start(i_start),
        .i_data(i_data),
        .o_busy(o_busy),
        .o_tx(o_tx)
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

    task automatic start_tx;
        input [7:0] d;
        begin
            @(negedge i_clock);
            i_data = d;
            i_start = 1'b1;
            @(negedge i_clock);
            i_start = 1'b0;
        end
    endtask

    task automatic check_data;
        input [7:0] expected;
        input [7:0] got;
        input [TAG_WIDTH-1:0] tag;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %s | DATA=0x%02h", tag, got);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %s | EXPECTED=0x%02h GOT=0x%02h", tag, expected, got);
            end
        end
    endtask

    task automatic receive_and_check;
        input [7:0] expected;
        input [TAG_WIDTH-1:0] tag;
        integer bit_idx;
        reg [7:0] captured;
        begin
            @(negedge o_tx);
            wait_baud_ticks(OVERSAMPLE / 2);
            if (o_tx === 1'b0) begin
                pass_count = pass_count + 1;
                $display("PASS %s | START bit OK", tag);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %s | START bit invalid (%b)", tag, o_tx);
            end

            wait_baud_ticks(OVERSAMPLE / 2);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                wait_baud_ticks(OVERSAMPLE / 2);
                captured[bit_idx] = o_tx;
                wait_baud_ticks(OVERSAMPLE / 2);
            end

            wait_baud_ticks(OVERSAMPLE / 2);
            if (o_tx === 1'b1) begin
                pass_count = pass_count + 1;
                $display("PASS %s | STOP bit OK", tag);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %s | STOP bit invalid (%b)", tag, o_tx);
            end
            check_data(expected, captured, tag);
        end
    endtask

    task automatic wait_idle;
        begin
            if (o_busy === 1'b1) begin
                @(negedge o_busy);
            end
            repeat (2) @(posedge i_clock);
        end
    endtask

    initial begin
        i_clock = 1'b0;
        i_baud_tick = 1'b0;
        i_reset = 1'b1;
        i_start = 1'b0;
        i_data = 8'h00;
        pass_count = 0;
        fail_count = 0;
        tick_div_count = 0;

        $display("Starting UART TX testbench...");
        $display("CLOCK_PERIOD_NS=%0d TICK_DIV=%0d OVERSAMPLE=%0d", CLOCK_PERIOD_NS, TICK_DIV, OVERSAMPLE);
        repeat (4) @(posedge i_clock);
        @(negedge i_clock);
        i_reset = 1'b0;

        $display("TEST T1 | Data 0xA5");
        fork
            start_tx(8'hA5);
            receive_and_check(8'hA5, "T1");
        join
        wait_idle();

        $display("TEST T2 | Data 0x00");
        fork
            start_tx(8'h00);
            receive_and_check(8'h00, "T2");
        join
        wait_idle();

        $display("TEST T3 | Data 0xFF");
        fork
            start_tx(8'hFF);
            receive_and_check(8'hFF, "T3");
        join
        wait_idle();

        $display("TEST T4 | i_data changes during frame (expect 0x5C)");
        fork
            start_tx(8'h5C);
            receive_and_check(8'h5C, "T4");
            begin
                @(posedge o_busy);
                wait_baud_ticks(40);
                i_data = 8'hFF;
            end
        join
        wait_idle();

        $display("TEST T5 | i_start pulse during frame (expect ignore)");
        fork
            start_tx(8'h99);
            receive_and_check(8'h99, "T5");
            begin
                @(posedge o_busy);
                wait_baud_ticks(40);
                i_data = 8'h00;
                i_start = 1'b1;
                @(negedge i_clock);
                i_start = 1'b0;
            end
        join
        wait_idle();

        repeat (2) @(posedge i_clock);
        if (o_busy === 1'b0) begin
            pass_count = pass_count + 1;
            $display("PASS T5_POST | o_busy returned to IDLE");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL T5_POST | o_busy stuck high (%b)", o_busy);
        end

        $display("TEST T6 | Two sequential bytes 0x11 then 0x22");
        fork
            start_tx(8'h11);
            receive_and_check(8'h11, "T6A");
        join
        wait_idle();
        fork
            start_tx(8'h22);
            receive_and_check(8'h22, "T6B");
        join
        wait_idle();

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

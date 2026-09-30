module tb_baud_gen;
    // Parameters
    parameter CLOCK_FREQ = 100_000_000;
    parameter BAUD_RATE = 9600;
    parameter OVERSAMPLE = 16;
    localparam integer TICK_DIV = CLOCK_FREQ / (BAUD_RATE * OVERSAMPLE);
    localparam integer NUM_TICKS_TO_TEST = 30;

    reg i_reset;
    reg i_clock;
    wire o_baud_tick;

    // Variables for automatic checking
    integer pass_count;
    integer fail_count;
    integer cycle_count;
    integer tick_count;
    integer last_tick_cycle;
    reg first_tick_seen;
    reg prev_tick;

    // baud_gen DUT
    baud_gen #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLE(OVERSAMPLE)
    ) UUT (
        .i_reset(i_reset),
        .i_clock(i_clock),
        .o_baud_tick(o_baud_tick)
    );

    // 100 MHz equivalent simulation clock period (10 ns)
    always #5 i_clock = ~i_clock;

    // Check period and pulse width on every clock
    always @(posedge i_clock) begin
        if (i_reset) begin
            cycle_count = 0;
            last_tick_cycle = 0;
            first_tick_seen = 0;
            prev_tick = 0;
            tick_count = 0;
        end else begin
            cycle_count = cycle_count + 1;
            if (o_baud_tick) begin
                tick_count = tick_count + 1;
                // Tick must be a single-cycle pulse
                if (prev_tick) begin
                    fail_count = fail_count + 1;
                    $display("FAIL PULSE_WIDTH | cycle=%0d Tick stayed high for more than one cycle", cycle_count);
                end else begin
                    pass_count = pass_count + 1;
                end
                if (!first_tick_seen) begin
                    if (cycle_count == TICK_DIV) begin
                        pass_count = pass_count + 1;
                        $display("PASS FIRST_TICK | cycle=%0d expected=%0d", cycle_count, TICK_DIV);
                    end else begin
                        fail_count = fail_count + 1;
                        $display("FAIL FIRST_TICK | cycle=%0d expected=%0d", cycle_count, TICK_DIV);
                    end
                    first_tick_seen = 1;
                end else begin
                    if (cycle_count - last_tick_cycle == TICK_DIV) begin
                        pass_count = pass_count + 1;
                        $display("PASS PERIOD | cycle=%0d interval=%0d", cycle_count, TICK_DIV);
                    end else begin
                        fail_count = fail_count + 1;
                        $display("FAIL PERIOD | cycle=%0d interval=%0d expected=%0d", cycle_count, cycle_count - last_tick_cycle, TICK_DIV);
                    end
                end
                last_tick_cycle = cycle_count;
            end
            prev_tick = o_baud_tick;
        end
    end

    initial begin
        i_clock = 0;
        i_reset = 1;
        pass_count = 0;
        fail_count = 0;
        cycle_count = 0;
        tick_count = 0;
        last_tick_cycle = 0;
        first_tick_seen = 0;
        prev_tick = 0;

        $display("Starting baud_gen testbench...");
        $display("CLOCK_FREQ=%0d BAUD_RATE=%0d OVERSAMPLE=%0d TICK_DIV=%0d", CLOCK_FREQ, BAUD_RATE, OVERSAMPLE, TICK_DIV);

        repeat (4) @(posedge i_clock);
        @(negedge i_clock);
        i_reset = 0;

        // Run until enough ticks are observed
        wait (tick_count >= NUM_TICKS_TO_TEST);
        repeat (2) @(posedge i_clock);

        $display("--------------------------------------------");
        $display("Test summary: PASS=%0d FAIL=%0d TOTAL=%0d", pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("All tests PASSED.");
        else
            $display("Some tests FAILED.");
        $finish;
    end
endmodule

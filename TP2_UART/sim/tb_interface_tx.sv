`timescale 1ns/1ps

module tb_interface_tx;
    reg i_clock = 1'b0;
    reg i_reset = 1'b1;
    reg i_wr = 1'b0;
    reg [7:0] i_w_data = 8'b0;
    reg i_busy = 1'b1;
    wire o_tx_full;
    wire o_start;
    wire [7:0] o_data;
    integer r_start_count = 0;

    interface_tx UUT (.*);
    always #5 i_clock = ~i_clock;

    always @(posedge i_clock) begin
        if (!i_reset && o_start) begin
            if (i_busy) $fatal(1, "Start while UART is busy");
            r_start_count = r_start_count + 1;
        end
    end

    task automatic check(input bit i_condition, input string i_message);
        if (!i_condition) $fatal(1, "%s", i_message);
    endtask

    task automatic write_byte(input [7:0] i_value);
        @(negedge i_clock);
        i_w_data = i_value;
        i_wr = 1'b1;
        @(negedge i_clock);
        i_wr = 1'b0;
    endtask

    initial begin
        repeat (2) @(negedge i_clock);
        i_reset = 1'b0;
        #1;
        check(o_tx_full === 1'b0 && o_start === 1'b0, "Reset TX");
        write_byte(8'hA5);
        check(o_tx_full === 1'b1 && o_start === 1'b0 && o_data === 8'hA5,
              "Queue result while UART is busy");

        write_byte(8'hFF);
        repeat (4) @(negedge i_clock);
        check(o_data === 8'hA5 && r_start_count == 0,
              "Writes while full must not overwrite the pending result");
        i_busy = 1'b0;
        repeat (5) @(negedge i_clock);
        check(r_start_count == 1 && o_start === 1'b0 && o_tx_full === 1'b1,
              "One start pulse, even with delayed busy acknowledgement");

        i_busy = 1'b1;
        repeat (4) @(negedge i_clock);
        check(o_data === 8'hA5 && o_tx_full === 1'b1, "Hold data while sending");
        i_busy = 1'b0;
        repeat (2) @(negedge i_clock);
        check(o_tx_full === 1'b0 && r_start_count == 1, "Release after busy falls");

        write_byte(8'h5C);
        @(negedge i_clock);
        check(r_start_count == 2 && o_data === 8'h5C, "Send a second result");
        i_busy = 1'b1;
        repeat (3) @(negedge i_clock);
        i_reset = 1'b1;
        @(negedge i_clock);
        check(o_start === 1'b0 && o_data === 8'b0, "Reset while transmitting");
        i_busy = 1'b0;
        i_reset = 1'b0;
        repeat (3) @(negedge i_clock);
        check(o_tx_full === 1'b0 && r_start_count == 2, "No stale result after reset");

        i_busy = 1'b1;
        write_byte(8'h42);
        i_reset = 1'b1;
        @(negedge i_clock);
        i_reset = 1'b0;
        i_busy = 1'b0;
        repeat (3) @(negedge i_clock);
        check(o_tx_full === 1'b0 && r_start_count == 2, "Reset discards a queued result");
        $display("PASS tb_interface_tx");
        $finish;
    end

    initial begin
        #10_000;
        $fatal(1, "TX interface timeout");
    end
endmodule

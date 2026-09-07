`timescale 1ns/1ps

module tb_interface_rx;
    reg i_clock = 1'b0;
    reg i_reset = 1'b1;
    reg i_valid = 1'b0;
    reg [7:0] i_data = 8'b0;
    reg i_error = 1'b0;
    reg i_rd = 1'b0;
    wire [7:0] o_r_data;
    wire o_rx_empty;
    wire o_error;

    interface_rx UUT (.*);
    always #5 i_clock = ~i_clock;

    task automatic check(input bit i_condition, input string i_message);
        if (!i_condition) $fatal(1, "%s", i_message);
    endtask

    task automatic cycle(input bit i_new_valid, input [7:0] i_new_data,
                         input bit i_new_error, input bit i_new_rd);
        @(negedge i_clock);
        i_valid = i_new_valid;
        i_data = i_new_data;
        i_error = i_new_error;
        i_rd = i_new_rd;
        @(posedge i_clock);
        #1;
    endtask

    initial begin
        repeat (2) @(negedge i_clock);
        check(o_rx_empty === 1'b1 && o_error === 1'b0, "Reset RX");
        i_reset = 1'b0;

        cycle(0, 8'hFF, 0, 0);
        check(o_rx_empty === 1'b1, "Data without valid must be ignored");
        cycle(1, 8'hA5, 0, 0);
        check(o_rx_empty === 1'b0 && o_r_data === 8'hA5, "Store first byte");
        cycle(0, 8'hFF, 0, 0);
        check(o_r_data === 8'hA5 && o_rx_empty === 1'b0, "Hold unread byte");

        cycle(1, 8'h5C, 0, 1);
        check(o_r_data === 8'h5C && o_rx_empty === 1'b0 && o_error === 1'b0,
              "Simultaneous read/write must retain the new byte");
        cycle(0, 0, 0, 1);
        check(o_rx_empty === 1'b1, "Read empties the buffer");
        cycle(1, 8'h42, 0, 1);
        check(o_r_data === 8'h42 && o_rx_empty === 1'b0,
              "Read while empty must not consume an arriving byte");

        cycle(1, 8'h11, 0, 0);
        check(o_error === 1'b1 && o_rx_empty === 1'b1, "Overflow must flush and report");
        cycle(0, 0, 0, 0);
        check(o_error === 1'b0, "Overflow error must last one cycle");
        cycle(1, 8'h33, 1, 0);
        check(o_error === 1'b1 && o_rx_empty === 1'b1, "Discard framing error");
        cycle(1, 8'h77, 0, 0);
        check(o_error === 1'b0 && o_r_data === 8'h77 && o_rx_empty === 1'b0,
              "Accept a good byte after an error");

        @(negedge i_clock);
        i_reset = 1'b1;
        @(posedge i_clock);
        #1;
        check(o_rx_empty === 1'b1 && o_r_data === 8'b0 && o_error === 1'b0,
              "Reset must discard a pending byte");
        $display("PASS tb_interface_rx");
        $finish;
    end

    initial begin
        #10_000;
        $fatal(1, "RX interface timeout");
    end
endmodule

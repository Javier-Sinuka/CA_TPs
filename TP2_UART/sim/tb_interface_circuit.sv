`timescale 1ns/1ps

module tb_interface_circuit;
    reg i_clock = 1'b0;
    reg i_reset = 1'b1;
    reg i_rx_valid = 1'b0;
    reg [7:0] i_rx_data = 8'b0;
    reg i_rx_error = 1'b0;
    reg r_force_busy = 1'b0;
    reg r_auto_busy = 1'b0;
    wire i_tx_busy = r_force_busy || r_auto_busy;
    wire o_tx_start;
    wire [7:0] o_tx_data;
    wire o_error;
    reg [7:0] r_expected [0:63];
    integer r_expected_count = 0;
    integer r_received_count = 0;
    integer r_error_count = 0;
    integer r_busy_counter = 0;
    integer r_before_count;
    integer r_before_errors;
    integer r_index;

    interface_circuit UUT (.*);
    always #5 i_clock = ~i_clock;

    // A byte-level TX model: acknowledge start, remain busy, then finish.
    always @(posedge i_clock) begin
        if (i_reset) begin
            r_auto_busy <= 1'b0;
            r_busy_counter <= 0;
        end else if (o_tx_start) begin
            if (i_tx_busy) $fatal(1, "TX started while busy");
            if (r_received_count >= r_expected_count)
                $fatal(1, "Unexpected or duplicate result %02h", o_tx_data);
            if (o_tx_data !== r_expected[r_received_count])
                $fatal(1, "Result %0d: expected %02h, got %02h",
                       r_received_count, r_expected[r_received_count], o_tx_data);
            r_received_count = r_received_count + 1;
            r_auto_busy <= 1'b1;
            r_busy_counter <= 20;
        end else if (r_auto_busy) begin
            if (r_busy_counter == 0) r_auto_busy <= 1'b0;
            else r_busy_counter <= r_busy_counter - 1;
        end
        if (!i_reset && o_error) r_error_count = r_error_count + 1;
    end

    task automatic send_byte(input [7:0] i_value, input bit i_bad);
        @(negedge i_clock);
        i_rx_data = i_value;
        i_rx_valid = 1'b1;
        i_rx_error = i_bad;
        @(negedge i_clock);
        i_rx_valid = 1'b0;
        i_rx_error = 1'b0;
    endtask

    task automatic expect_result(input [7:0] i_value);
        r_expected[r_expected_count] = i_value;
        r_expected_count = r_expected_count + 1;
    endtask

    task automatic command(input [7:0] i_a, input [7:0] i_b,
                           input [7:0] i_op, input [7:0] i_result);
        expect_result(i_result);
        // Three valid bytes on consecutive clock edges exercise read/write overlap.
        @(negedge i_clock);
        i_rx_valid = 1'b1;
        i_rx_data = i_a;
        @(negedge i_clock);
        i_rx_data = i_b;
        @(negedge i_clock);
        i_rx_data = i_op;
        @(negedge i_clock);
        i_rx_valid = 1'b0;
    endtask

    task automatic drain;
        wait (r_received_count == r_expected_count);
        @(negedge i_clock);
        wait (!r_auto_busy);
        repeat (4) @(negedge i_clock);
    endtask

    initial begin
        repeat (3) @(negedge i_clock);
        i_reset = 1'b0;
        command(8'h12, 8'h34, 8'h20, 8'h46); drain(); // ADD
        command(8'h03, 8'h05, 8'h22, 8'hFE); drain(); // SUB, signed result
        command(8'hF0, 8'h5A, 8'h24, 8'h50); drain(); // AND
        command(8'hF0, 8'h5A, 8'h25, 8'hFA); drain(); // OR
        command(8'hF0, 8'h5A, 8'h26, 8'hAA); drain(); // XOR
        command(8'h80, 8'h02, 8'h03, 8'hE0); drain(); // SRA
        command(8'h80, 8'h02, 8'h02, 8'h20); drain(); // SRL
        command(8'hF0, 8'h5A, 8'h27, 8'h05); drain(); // NOR
        command(8'hFF, 8'h01, 8'h20, 8'h00); drain(); // Eight-bit wrap
        command(8'h12, 8'h34, 8'h00, 8'h00); drain(); // Unknown opcode
        command(8'h80, 8'h0A, 8'h03, 8'hE0); drain(); // ALU uses B[2:0]
        command(8'h01, 8'h02, 8'hE0, 8'h03); drain(); // ALU uses opcode[5:0]

        // A partial command must not emit a result, even after a long pause.
        r_before_count = r_received_count;
        expect_result(8'h15);
        send_byte(8'h10, 0);
        repeat (15) @(negedge i_clock);
        send_byte(8'h05, 0);
        repeat (15) @(negedge i_clock);
        if (r_received_count != r_before_count) $fatal(1, "Premature result");
        send_byte(8'h20, 0);
        drain();

        // Framing errors at each position abort the partial command.
        for (r_index = 0; r_index < 3; r_index = r_index + 1) begin
            r_before_errors = r_error_count;
            if (r_index >= 1) send_byte(8'h55, 0);
            if (r_index >= 2) send_byte(8'h66, 0);
            send_byte(8'h77, 1);
            repeat (4) @(negedge i_clock);
            if (r_error_count != r_before_errors + 1) $fatal(1, "Missing RX error");
            command(8'h06, 8'h07, 8'h20, 8'h0D);
            drain();
        end

        // Keep TX unavailable: preserve one queued result and a second in the ALU.
        r_force_busy = 1'b1;
        r_before_count = r_received_count;
        command(8'h01, 8'h02, 8'h20, 8'h03);
        repeat (5) @(negedge i_clock);
        command(8'h04, 8'h05, 8'h20, 8'h09);
        repeat (10) @(negedge i_clock);
        if (r_received_count != r_before_count) $fatal(1, "Ignored TX busy");
        r_force_busy = 1'b0;
        drain();

        // Overflow while stalled aborts only the command not yet queued for TX.
        r_force_busy = 1'b1;
        command(8'h08, 8'h09, 8'h20, 8'h11);
        repeat (5) @(negedge i_clock);
        send_byte(8'h20, 0);
        send_byte(8'h30, 0);
        send_byte(8'h20, 0);
        send_byte(8'hAA, 0);
        r_before_errors = r_error_count;
        send_byte(8'hBB, 0);
        repeat (4) @(negedge i_clock);
        if (r_error_count != r_before_errors + 1) $fatal(1, "Missing overflow error");
        r_force_busy = 1'b0;
        drain();
        command(8'h10, 8'h01, 8'h22, 8'h0F);
        drain();

        // Reset in a partial command, then in a result waiting for TX.
        send_byte(8'hEE, 0);
        @(negedge i_clock);
        i_reset = 1'b1;
        repeat (2) @(negedge i_clock);
        i_reset = 1'b0;
        command(8'h02, 8'h03, 8'h20, 8'h05);
        drain();
        r_force_busy = 1'b1;
        send_byte(8'hEE, 0);
        send_byte(8'hDD, 0);
        send_byte(8'h20, 0);
        repeat (5) @(negedge i_clock);
        i_reset = 1'b1;
        repeat (2) @(negedge i_clock);
        i_reset = 1'b0;
        r_force_busy = 1'b0;
        repeat (5) @(negedge i_clock);
        command(8'h07, 8'h08, 8'h20, 8'h0F);
        drain();

        $display("PASS tb_interface_circuit: %0d results, %0d expected errors",
                 r_received_count, r_error_count);
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "Interface circuit timeout: received=%0d expected=%0d state=%0d tx_state=%0d",
               r_received_count, r_expected_count, UUT.r_state, UUT.u_interface_tx.r_state);
    end
endmodule

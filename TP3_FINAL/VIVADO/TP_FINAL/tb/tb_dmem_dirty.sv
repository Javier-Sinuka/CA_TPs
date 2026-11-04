`timescale 1ns/1ps
`default_nettype none

module tb_dmem_dirty;
    reg r_clock;
    reg r_reset;
    reg r_en;
    reg r_we;
    reg [31:0] r_addr;
    reg [31:0] r_store_data;
    reg [2:0] r_funct3;
    reg [7:0] r_dbg_addr;
    wire [31:0] w_load_data;
    wire [31:0] w_dbg_data;
    wire w_dbg_dirty;
    integer checks;
    integer errors;
    integer index;
    reg [31:0] r_expected;

    dmem dut (
        .i_clock(r_clock),
        .i_reset(r_reset),
        .i_en(r_en),
        .i_we(r_we),
        .i_addr(r_addr),
        .i_store_data(r_store_data),
        .i_funct3(r_funct3),
        .o_load_data(w_load_data),
        .i_dbg_addr(r_dbg_addr),
        .o_dbg_data(w_dbg_data),
        .o_dbg_dirty(w_dbg_dirty)
    );

    function automatic [31:0] pattern(input [7:0] word_index);
        begin
            pattern = {8'ha5, word_index, word_index ^ 8'hff, 8'h5a};
        end
    endfunction

    task automatic check_word(input [31:0] got, input [31:0] expected,
                              input [127:0] label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL dmem_dirty: %0s check=%0d addr=%08h dbg=%0d expected=%08h got=%08h",
                         label, checks, r_addr, r_dbg_addr, expected, got);
            end
        end
    endtask

    task automatic check_state(input [7:0] word_index,
                               input [31:0] expected_data,
                               input expected_dirty);
        begin
            r_dbg_addr = word_index;
            r_addr = {22'd0, word_index, 2'b00};
            r_funct3 = 3'b010;
            #1;
            check_word(w_dbg_data, expected_data, "debug data");
            check_word({31'd0, w_dbg_dirty}, {31'd0, expected_dirty}, "debug dirty");
            check_word(w_load_data, expected_data, "CPU load");
        end
    endtask

    task automatic write_word(input [31:0] addr, input [2:0] funct3,
                              input [31:0] data);
        begin
            @(negedge r_clock);
            r_en = 1'b1;
            r_we = 1'b1;
            r_addr = addr;
            r_funct3 = funct3;
            r_store_data = data;
            @(posedge r_clock);
            #1;
            r_we = 1'b0;
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #5 r_clock = ~r_clock;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL tb_dmem_dirty: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        r_reset = 1'b1;
        r_en = 1'b0;
        r_we = 1'b0;
        r_addr = 32'd0;
        r_store_data = 32'd0;
        r_funct3 = 3'b010;
        r_dbg_addr = 8'd0;

        @(posedge r_clock);
        #1;
        for (index = 0; index < 256; index = index + 1)
            check_state(index[7:0], 32'd0, 1'b0);

        @(negedge r_clock);
        r_reset = 1'b0;
        for (index = 0; index < 256; index = index + 1) begin
            if (index == 37)
                r_expected = 32'd0;
            else
                r_expected = pattern(index[7:0]);
            write_word(index * 4, 3'b010, r_expected);
            check_state(index[7:0], r_expected, 1'b1);
        end

        @(negedge r_clock);
        r_en = 1'b0;
        r_we = 1'b1;
        r_store_data = 32'hffff_ffff;
        for (index = 0; index < 256; index = index + 1) begin
            @(negedge r_clock);
            if (index == 37)
                r_expected = 32'd0;
            else
                r_expected = pattern(index[7:0]);
            check_state(index[7:0], r_expected, 1'b1);
            @(posedge r_clock);
            #1;
            check_word(w_dbg_data, r_expected, "paused debug after edge");
            check_word({31'd0, w_dbg_dirty}, 32'd1, "paused dirty after edge");
        end

        @(negedge r_clock);
        r_reset = 1'b1;
        r_en = 1'b0;
        r_we = 1'b1;
        r_addr = 32'd1020;
        r_funct3 = 3'b010;
        r_store_data = 32'hffff_ffff;
        @(posedge r_clock);
        #1;
        r_we = 1'b0;
        for (index = 0; index < 256; index = index + 1)
            check_state(index[7:0], 32'd0, 1'b0);

        @(negedge r_clock);
        r_reset = 1'b0;
        r_en = 1'b0;
        r_we = 1'b1;
        r_addr = 32'd1021;
        r_funct3 = 3'b000;
        r_store_data = 32'h0000_00aa;
        @(posedge r_clock);
        #1;
        r_we = 1'b0;
        check_state(8'd255, 32'd0, 1'b0);

        write_word(32'd1021, 3'b000, 32'h0000_00aa);
        check_state(8'd255, 32'h0000_aa00, 1'b1);
        check_state(8'd0, 32'd0, 1'b0);
        write_word(32'd1023, 3'b001, 32'h0000_beef);
        check_state(8'd255, 32'hbeef_aa00, 1'b1);
        write_word(32'd1020, 3'b000, 32'h0000_0044);
        check_state(8'd255, 32'hbeef_aa44, 1'b1);
        write_word(32'd0, 3'b010, 32'd0);
        check_state(8'd0, 32'd0, 1'b1);
        check_state(8'd1, 32'd0, 1'b0);

        @(negedge r_clock);
        r_en = 1'b0;
        r_we = 1'b1;
        r_store_data = 32'hffff_ffff;
        for (index = 0; index < 256; index = index + 1) begin
            @(negedge r_clock);
            if (index == 255)
                check_state(index[7:0], 32'hbeef_aa44, 1'b1);
            else if (index == 0)
                check_state(index[7:0], 32'd0, 1'b1);
            else
                check_state(index[7:0], 32'd0, 1'b0);
            @(posedge r_clock);
            #1;
            if (index == 255)
                check_word(w_dbg_data, 32'hbeef_aa44, "paused sparse data");
            else
                check_word(w_dbg_data, 32'd0, "paused sparse data");
        end

        @(negedge r_clock);
        r_reset = 1'b1;
        r_en = 1'b1;
        r_we = 1'b1;
        r_addr = 32'd1020;
        r_funct3 = 3'b010;
        r_store_data = 32'hffff_ffff;
        @(posedge r_clock);
        #1;
        r_we = 1'b0;
        check_state(8'd255, 32'd0, 1'b0);
        check_state(8'd0, 32'd0, 1'b0);

        if (errors != 0)
            $fatal(1, "FAIL tb_dmem_dirty: %0d errors in %0d checks", errors, checks);
        else begin
            $display("PASS tb_dmem_dirty: %0d checks", checks);
            $finish;
        end
    end
endmodule

`default_nettype wire

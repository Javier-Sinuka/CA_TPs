`timescale 1ns/1ps
`default_nettype none

module tb_regfile;
    reg r_clock;
    reg r_reset;
    reg r_en;
    reg r_reg_write;
    reg [4:0] r_rd;
    reg [31:0] r_wdata;
    reg [4:0] r_rs1;
    reg [4:0] r_rs2;
    reg [4:0] r_dbg_addr;
    wire [31:0] w_rs1_data;
    wire [31:0] w_rs2_data;
    wire [31:0] w_dbg_data;
    integer checks;
    integer errors;
    integer index;
    reg [31:0] r_expected;

    regfile dut (
        .i_clock(r_clock),
        .i_reset(r_reset),
        .i_en(r_en),
        .i_reg_write(r_reg_write),
        .i_rd(r_rd),
        .i_wdata(r_wdata),
        .i_rs1(r_rs1),
        .i_rs2(r_rs2),
        .o_rs1_data(w_rs1_data),
        .o_rs2_data(w_rs2_data),
        .i_dbg_addr(r_dbg_addr),
        .o_dbg_data(w_dbg_data)
    );

    task automatic check_word;
        input [31:0] got;
        input [31:0] expected;
        input [127:0] label;
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL regfile: %0s check=%0d expected=%08h got=%08h",
                         label, checks, expected, got);
            end
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #5 r_clock = ~r_clock;
    end

    initial begin
        #10000;
        $fatal(1, "FAIL tb_regfile: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        r_reset = 1'b1;
        r_en = 1'b0;
        r_reg_write = 1'b0;
        r_rd = 5'd0;
        r_wdata = 32'd0;
        r_rs1 = 5'd0;
        r_rs2 = 5'd0;
        r_dbg_addr = 5'd0;

        @(posedge r_clock);
        #1;
        for (index = 0; index < 32; index = index + 1) begin
            r_rs1 = index[4:0];
            r_rs2 = index[4:0];
            r_dbg_addr = index[4:0];
            #1;
            check_word(w_rs1_data, 32'd0, "initial rs1");
            check_word(w_rs2_data, 32'd0, "initial rs2");
            check_word(w_dbg_data, 32'd0, "initial debug");
        end

        @(negedge r_clock);
        r_reset = 1'b0;
        r_en = 1'b1;
        r_reg_write = 1'b1;
        for (index = 1; index < 32; index = index + 1) begin
            if (index != 1)
                @(negedge r_clock);
            r_rd = index[4:0];
            r_rs1 = index[4:0];
            r_rs2 = index[4:0];
            r_dbg_addr = index[4:0];
            r_expected = 32'h5100_0000 + index;
            r_wdata = r_expected;
            #1;
            check_word(w_rs1_data, r_expected, "rs1 bypass");
            check_word(w_rs2_data, r_expected, "rs2 bypass");
            check_word(w_dbg_data, 32'd0, "debug before write");
            @(posedge r_clock);
            #1;
            check_word(w_dbg_data, r_expected, "debug after write");
        end

        @(negedge r_clock);
        r_rd = 5'd0;
        r_wdata = 32'hffff_ffff;
        r_rs1 = 5'd0;
        r_rs2 = 5'd0;
        r_dbg_addr = 5'd0;
        #1;
        check_word(w_rs1_data, 32'd0, "x0 rs1");
        check_word(w_rs2_data, 32'd0, "x0 rs2");
        check_word(w_dbg_data, 32'd0, "x0 debug");
        @(posedge r_clock);
        #1;
        check_word(w_dbg_data, 32'd0, "x0 after write");

        @(negedge r_clock);
        r_en = 1'b0;
        r_rd = 5'd1;
        r_wdata = 32'hdead_beef;
        r_rs1 = 5'd1;
        r_rs2 = 5'd31;
        r_dbg_addr = 5'd1;
        #1;
        check_word(w_rs1_data, 32'h5100_0001, "paused rs1");
        check_word(w_rs2_data, 32'h5100_001f, "paused rs2");
        check_word(w_dbg_data, 32'h5100_0001, "paused debug");
        @(posedge r_clock);
        #1;
        check_word(w_rs1_data, 32'h5100_0001, "paused after edge");

        @(negedge r_clock);
        r_en = 1'b1;
        r_reg_write = 1'b0;
        r_rd = 5'd1;
        r_wdata = 32'hdead_beef;
        #1;
        check_word(w_rs1_data, 32'h5100_0001, "write disabled");
        @(posedge r_clock);
        #1;
        check_word(w_dbg_data, 32'h5100_0001, "disabled after edge");

        @(negedge r_clock);
        r_reg_write = 1'b1;
        r_rd = 5'd31;
        r_wdata = 32'h1234_5678;
        r_rs1 = 5'd1;
        r_rs2 = 5'd31;
        r_dbg_addr = 5'd31;
        #1;
        check_word(w_rs1_data, 32'h5100_0001, "other rs1");
        check_word(w_rs2_data, 32'h1234_5678, "colliding rs2");
        check_word(w_dbg_data, 32'h5100_001f, "debug old value");
        @(posedge r_clock);
        #1;
        check_word(w_dbg_data, 32'h1234_5678, "debug committed value");

        @(negedge r_clock);
        r_reset = 1'b1;
        r_en = 1'b0;
        r_rd = 5'd1;
        r_wdata = 32'hface_cafe;
        r_rs1 = 5'd1;
        r_rs2 = 5'd31;
        r_dbg_addr = 5'd31;
        #1;
        check_word(w_rs1_data, 32'h5100_0001, "reset suppresses bypass");
        check_word(w_dbg_data, 32'h1234_5678, "debug before reset");
        @(posedge r_clock);
        #1;
        for (index = 0; index < 32; index = index + 1) begin
            r_rs1 = index[4:0];
            r_rs2 = index[4:0];
            r_dbg_addr = index[4:0];
            #1;
            check_word(w_rs1_data, 32'd0, "reset rs1");
            check_word(w_rs2_data, 32'd0, "reset rs2");
            check_word(w_dbg_data, 32'd0, "reset debug");
        end

        @(negedge r_clock);
        r_reset = 1'b0;
        r_en = 1'b0;
        r_reg_write = 1'b0;
        r_dbg_addr = 5'd31;
        #1;
        check_word(w_dbg_data, 32'd0, "debug selector no write");
        r_dbg_addr = 5'd1;
        #1;
        check_word(w_dbg_data, 32'd0, "debug selector stable state");

        if (errors != 0)
            $fatal(1, "FAIL tb_regfile: %0d errors in %0d checks", errors, checks);
        else begin
            $display("PASS tb_regfile: %0d checks", checks);
            $finish;
        end
    end
endmodule

`default_nettype wire

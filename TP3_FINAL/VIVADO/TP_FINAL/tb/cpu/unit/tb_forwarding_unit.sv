`timescale 1ns/1ps
`default_nettype none

module tb_forwarding_unit;
    reg r_valid_ex;
    reg r_uses_rs1_ex;
    reg r_uses_rs2_ex;
    reg [4:0] r_rs1_ex;
    reg [4:0] r_rs2_ex;
    reg r_valid_mem;
    reg r_reg_write_mem;
    reg r_mem_read_mem;
    reg [4:0] r_rd_mem;
    reg r_valid_wb;
    reg r_reg_write_wb;
    reg [4:0] r_rd_wb;
    wire [1:0] w_forward_a;
    wire [1:0] w_forward_b;
    integer checks;
    integer errors;
    integer index;

    forwarding_unit dut (
        .i_valid_ex(r_valid_ex),
        .i_uses_rs1_ex(r_uses_rs1_ex),
        .i_uses_rs2_ex(r_uses_rs2_ex),
        .i_rs1_ex(r_rs1_ex),
        .i_rs2_ex(r_rs2_ex),
        .i_valid_mem(r_valid_mem),
        .i_reg_write_mem(r_reg_write_mem),
        .i_mem_read_mem(r_mem_read_mem),
        .i_rd_mem(r_rd_mem),
        .i_valid_wb(r_valid_wb),
        .i_reg_write_wb(r_reg_write_wb),
        .i_rd_wb(r_rd_wb),
        .o_forward_a(w_forward_a),
        .o_forward_b(w_forward_b)
    );

    task automatic check_selectors(input [1:0] expected_a,
                                   input [1:0] expected_b,
                                   input string label);
        begin
            #1;
            checks = checks + 2;
            if (w_forward_a !== expected_a) begin
                errors = errors + 1;
                $display("FAIL tb_forwarding_unit: %s A expected=%b got=%b", label, expected_a, w_forward_a);
            end
            if (w_forward_b !== expected_b) begin
                errors = errors + 1;
                $display("FAIL tb_forwarding_unit: %s B expected=%b got=%b", label, expected_b, w_forward_b);
            end
        end
    endtask

    initial begin
        #10000;
        $fatal(1, "FAIL tb_forwarding_unit: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        r_valid_ex = 1'b1;
        r_uses_rs1_ex = 1'b1;
        r_uses_rs2_ex = 1'b1;
        r_rs1_ex = 5'd5;
        r_rs2_ex = 5'd9;
        r_valid_mem = 1'b0;
        r_reg_write_mem = 1'b0;
        r_mem_read_mem = 1'b0;
        r_rd_mem = 5'd5;
        r_valid_wb = 1'b0;
        r_reg_write_wb = 1'b0;
        r_rd_wb = 5'd9;
        check_selectors(2'b00, 2'b00, "no producer");

        r_valid_mem = 1'b1;
        r_reg_write_mem = 1'b1;
        check_selectors(2'b10, 2'b00, "MEM matches rs1");
        r_rd_mem = 5'd9;
        check_selectors(2'b00, 2'b10, "MEM matches rs2");
        r_rd_mem = 5'd5;
        r_valid_mem = 1'b0;
        r_valid_wb = 1'b1;
        r_reg_write_wb = 1'b1;
        r_rd_wb = 5'd5;
        check_selectors(2'b01, 2'b00, "WB matches rs1");
        r_rd_wb = 5'd9;
        check_selectors(2'b00, 2'b01, "WB matches rs2");

        r_valid_mem = 1'b1;
        r_rd_mem = 5'd5;
        check_selectors(2'b10, 2'b01, "different producers");
        r_rs2_ex = 5'd5;
        r_rd_wb = 5'd5;
        check_selectors(2'b10, 2'b10, "both producers same rd");
        r_mem_read_mem = 1'b1;
        check_selectors(2'b00, 2'b00, "young load blocks old WB");
        r_rd_wb = 5'd9;
        check_selectors(2'b00, 2'b00, "young load alone");
        r_rs2_ex = 5'd9;
        check_selectors(2'b00, 2'b01, "load blocks only matching source");
        r_mem_read_mem = 1'b0;
        r_valid_mem = 1'b0;
        r_rd_wb = 5'd5;
        check_selectors(2'b01, 2'b00, "invalid MEM allows WB");
        r_valid_mem = 1'b1;
        r_reg_write_mem = 1'b0;
        check_selectors(2'b01, 2'b00, "MEM without write allows WB");
        r_reg_write_mem = 1'b1;
        r_valid_wb = 1'b0;
        check_selectors(2'b10, 2'b00, "invalid WB");
        r_valid_wb = 1'b1;
        r_reg_write_wb = 1'b0;
        check_selectors(2'b10, 2'b00, "WB without write");
        r_reg_write_wb = 1'b1;

        r_rs1_ex = 5'd0;
        r_rs2_ex = 5'd0;
        r_rd_mem = 5'd0;
        r_rd_wb = 5'd0;
        check_selectors(2'b00, 2'b00, "x0 never forwarded");
        r_rs1_ex = 5'd5;
        r_rs2_ex = 5'd9;
        r_rd_mem = 5'd5;
        r_rd_wb = 5'd9;
        r_uses_rs1_ex = 1'b0;
        check_selectors(2'b00, 2'b01, "rs1 unused");
        r_uses_rs1_ex = 1'b1;
        r_uses_rs2_ex = 1'b0;
        check_selectors(2'b10, 2'b00, "rs2 unused");
        r_uses_rs2_ex = 1'b1;
        r_valid_ex = 1'b0;
        check_selectors(2'b00, 2'b00, "invalid consumer");
        r_valid_ex = 1'b1;

        for (index = 1; index < 32; index = index + 1) begin
            r_rs1_ex = index[4:0];
            r_rs2_ex = index[4:0];
            r_rd_mem = index[4:0];
            r_rd_wb = index[4:0];
            check_selectors(2'b10, 2'b10, "MEM priority sweep");
            r_mem_read_mem = 1'b1;
            check_selectors(2'b00, 2'b00, "load priority sweep");
            r_valid_mem = 1'b0;
            check_selectors(2'b01, 2'b01, "WB fallback sweep");
            r_valid_mem = 1'b1;
            r_mem_read_mem = 1'b0;
        end

        if (errors != 0)
            $fatal(1, "FAIL tb_forwarding_unit: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_forwarding_unit: %0d checks", checks);
        $finish;
    end
endmodule

`default_nettype wire

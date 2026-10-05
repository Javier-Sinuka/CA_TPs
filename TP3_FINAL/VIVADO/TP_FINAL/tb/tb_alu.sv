`timescale 1ns/1ps
`include "riscv_defs.vh"

module tb_alu;
    reg [31:0] r_operand_a, r_operand_b;
    reg [3:0] r_op;
    wire [31:0] w_result;
    integer r_checks;

    alu dut (
        .i_operand_a(r_operand_a),
        .i_operand_b(r_operand_b),
        .i_op(r_op),
        .o_result(w_result)
    );

    task check_result;
        input [31:0] a, b;
        input [3:0] op;
        input [31:0] expected;
        begin
            r_operand_a = a;
            r_operand_b = b;
            r_op = op;
            #1;
            if (w_result !== expected)
                $fatal(1, "ALU failed: op=%0d a=%h b=%h expected=%h got=%h",
                       op, a, b, expected, w_result);
            r_checks = r_checks + 1;
        end
    endtask

    initial begin
        r_checks = 0;
        check_result(32'd5, 32'd7, `ALU_ADD, 32'd12);
        check_result(32'hffff_ffff, 32'd1, `ALU_ADD, 32'd0);
        check_result(32'h8000_0000, 32'h8000_0000, `ALU_ADD, 32'd0);
        check_result(32'd5, 32'd7, `ALU_SUB, 32'hffff_fffe);
        check_result(32'd0, 32'd1, `ALU_SUB, 32'hffff_ffff);
        check_result(32'd1, 32'd31, `ALU_SLL, 32'h8000_0000);
        check_result(32'd1, 32'd32, `ALU_SLL, 32'd1);
        check_result(32'h8000_0000, 32'd31, `ALU_SRL, 32'd1);
        check_result(32'hffff_ffff, 32'd4, `ALU_SRL, 32'h0fff_ffff);
        check_result(32'h8000_0000, 32'd31, `ALU_SRA, 32'hffff_ffff);
        check_result(32'hffff_ffff, 32'd4, `ALU_SRA, 32'hffff_ffff);
        check_result(32'hf0f0_aa55, 32'h0ff0_0f0f, `ALU_AND, 32'h00f0_0a05);
        check_result(32'hf0f0_aa55, 32'h0ff0_0f0f, `ALU_OR, 32'hfff0_af5f);
        check_result(32'hf0f0_aa55, 32'h0ff0_0f0f, `ALU_XOR, 32'hff00_a55a);
        check_result(32'h8000_0000, 32'd1, `ALU_SLT, 32'd1);
        check_result(32'd1, 32'h8000_0000, `ALU_SLT, 32'd0);
        check_result(32'h8000_0000, 32'd1, `ALU_SLTU, 32'd0);
        check_result(32'd1, 32'h8000_0000, `ALU_SLTU, 32'd1);
        check_result(32'd1, 32'd2, `ALU_SLT, 32'd1);
        check_result(32'd2, 32'd2, `ALU_SLTU, 32'd0);
        check_result(32'd1, 32'd2, 4'd15, 32'd0);
        $display("tb_alu passed: %0d checks", r_checks);
        $finish;
    end
endmodule

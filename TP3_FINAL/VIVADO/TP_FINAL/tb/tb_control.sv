`timescale 1ns/1ps
`include "riscv_defs.vh"

module tb_control;
    reg [31:0] r_instr;
    wire [3:0] w_alu_op;
    wire w_alu_src_b, w_reg_write, w_mem_read, w_mem_write, w_mem_to_reg;
    wire w_branch, w_jump, w_jalr, w_lui, w_halt;
    wire w_uses_rs1, w_uses_rs2, w_valid_instr;
    wire [12:0] w_flags;
    integer r_checks;

    localparam [12:0] F_ALU_SRC_B = 13'd1 << 12;
    localparam [12:0] F_REG_WRITE = 13'd1 << 11;
    localparam [12:0] F_MEM_READ = 13'd1 << 10;
    localparam [12:0] F_MEM_WRITE = 13'd1 << 9;
    localparam [12:0] F_MEM_TO_REG = 13'd1 << 8;
    localparam [12:0] F_BRANCH = 13'd1 << 7;
    localparam [12:0] F_JUMP = 13'd1 << 6;
    localparam [12:0] F_JALR = 13'd1 << 5;
    localparam [12:0] F_LUI = 13'd1 << 4;
    localparam [12:0] F_HALT = 13'd1 << 3;
    localparam [12:0] F_USES_RS1 = 13'd1 << 2;
    localparam [12:0] F_USES_RS2 = 13'd1 << 1;
    localparam [12:0] F_VALID = 13'd1;

    localparam [12:0] F_R = F_REG_WRITE | F_USES_RS1 | F_USES_RS2 | F_VALID;
    localparam [12:0] F_I = F_ALU_SRC_B | F_REG_WRITE | F_USES_RS1 | F_VALID;
    localparam [12:0] F_LOAD = F_I | F_MEM_READ | F_MEM_TO_REG;
    localparam [12:0] F_STORE = F_ALU_SRC_B | F_MEM_WRITE | F_USES_RS1 | F_USES_RS2 | F_VALID;
    localparam [12:0] F_BRANCH_OP = F_BRANCH | F_USES_RS1 | F_USES_RS2 | F_VALID;

    assign w_flags = {
        w_alu_src_b, w_reg_write, w_mem_read, w_mem_write, w_mem_to_reg,
        w_branch, w_jump, w_jalr, w_lui, w_halt, w_uses_rs1,
        w_uses_rs2, w_valid_instr
    };

    control dut (
        .i_instr(r_instr),
        .o_alu_op(w_alu_op),
        .o_alu_src_b(w_alu_src_b),
        .o_reg_write(w_reg_write),
        .o_mem_read(w_mem_read),
        .o_mem_write(w_mem_write),
        .o_mem_to_reg(w_mem_to_reg),
        .o_branch(w_branch),
        .o_jump(w_jump),
        .o_jalr(w_jalr),
        .o_lui(w_lui),
        .o_halt(w_halt),
        .o_uses_rs1(w_uses_rs1),
        .o_uses_rs2(w_uses_rs2),
        .o_valid_instr(w_valid_instr)
    );

    function [31:0] enc_r;
        input [6:0] funct7;
        input [2:0] funct3;
        begin
            enc_r = {funct7, 5'd2, 5'd1, funct3, 5'd3, 7'b0110011};
        end
    endfunction

    function [31:0] enc_i;
        input [11:0] imm;
        input [2:0] funct3;
        input [6:0] opcode;
        begin
            enc_i = {imm, 5'd1, funct3, 5'd3, opcode};
        end
    endfunction

    task check_control;
        input [31:0] instr;
        input [3:0] expected_alu_op;
        input [12:0] expected_flags;
        begin
            r_instr = instr;
            #1;
            if (w_alu_op !== expected_alu_op || w_flags !== expected_flags)
                $fatal(1, "CONTROL failed: instr=%h op=%h/%h flags=%h/%h",
                       instr, w_alu_op, expected_alu_op, w_flags, expected_flags);
            r_checks = r_checks + 1;
        end
    endtask

    initial begin
        r_checks = 0;
        check_control(enc_r(7'b0000000, 3'b000), `ALU_ADD, F_R);
        check_control(enc_r(7'b0100000, 3'b000), `ALU_SUB, F_R);
        check_control(enc_r(7'b0000000, 3'b001), `ALU_SLL, F_R);
        check_control(enc_r(7'b0000000, 3'b010), `ALU_SLT, F_R);
        check_control(enc_r(7'b0000000, 3'b011), `ALU_SLTU, F_R);
        check_control(enc_r(7'b0000000, 3'b100), `ALU_XOR, F_R);
        check_control(enc_r(7'b0000000, 3'b101), `ALU_SRL, F_R);
        check_control(enc_r(7'b0100000, 3'b101), `ALU_SRA, F_R);
        check_control(enc_r(7'b0000000, 3'b110), `ALU_OR, F_R);
        check_control(enc_r(7'b0000000, 3'b111), `ALU_AND, F_R);

        check_control(enc_i(12'hfff, 3'b000, 7'b0010011), `ALU_ADD, F_I);
        check_control(enc_i(12'hfff, 3'b010, 7'b0010011), `ALU_SLT, F_I);
        check_control(enc_i(12'hfff, 3'b011, 7'b0010011), `ALU_SLTU, F_I);
        check_control(enc_i(12'hfff, 3'b100, 7'b0010011), `ALU_XOR, F_I);
        check_control(enc_i(12'hfff, 3'b110, 7'b0010011), `ALU_OR, F_I);
        check_control(enc_i(12'hfff, 3'b111, 7'b0010011), `ALU_AND, F_I);
        check_control(enc_i(12'h002, 3'b001, 7'b0010011), `ALU_SLL, F_I);
        check_control(enc_i(12'h002, 3'b101, 7'b0010011), `ALU_SRL, F_I);
        check_control(enc_i(12'h402, 3'b101, 7'b0010011), `ALU_SRA, F_I);

        check_control(enc_i(12'h004, 3'b000, 7'b0000011), `ALU_ADD, F_LOAD);
        check_control(enc_i(12'h004, 3'b001, 7'b0000011), `ALU_ADD, F_LOAD);
        check_control(enc_i(12'h004, 3'b010, 7'b0000011), `ALU_ADD, F_LOAD);
        check_control(enc_i(12'h004, 3'b100, 7'b0000011), `ALU_ADD, F_LOAD);
        check_control(enc_i(12'h004, 3'b101, 7'b0000011), `ALU_ADD, F_LOAD);

        check_control(32'h0020_8023, `ALU_ADD, F_STORE);
        check_control(32'h0020_9023, `ALU_ADD, F_STORE);
        check_control(32'h0020_a023, `ALU_ADD, F_STORE);
        check_control(32'h0020_8063, `ALU_ADD, F_BRANCH_OP);
        check_control(32'h0020_9063, `ALU_ADD, F_BRANCH_OP);
        check_control(32'h0080_00ef, `ALU_ADD, F_REG_WRITE | F_JUMP | F_VALID);
        check_control(enc_i(12'h004, 3'b000, 7'b1100111), `ALU_ADD,
                      F_I | F_JUMP | F_JALR);
        check_control(32'h1234_50b7, `ALU_ADD,
                      F_ALU_SRC_B | F_REG_WRITE | F_LUI | F_VALID);
        check_control(32'h0000_0073, `ALU_ADD, F_HALT | F_VALID);

        check_control(enc_r(7'b0000001, 3'b000), `ALU_ADD, 13'd0);
        check_control(enc_r(7'b0100000, 3'b111), `ALU_ADD, 13'd0);
        check_control(enc_i(12'h402, 3'b001, 7'b0010011), `ALU_ADD, 13'd0);
        check_control(enc_i(12'h202, 3'b101, 7'b0010011), `ALU_ADD, 13'd0);
        check_control(enc_i(12'h004, 3'b011, 7'b0000011), `ALU_ADD, 13'd0);
        check_control(32'h0020_b023, `ALU_ADD, 13'd0);
        check_control(32'h0020_c063, `ALU_ADD, 13'd0);
        check_control(enc_i(12'h004, 3'b001, 7'b1100111), `ALU_ADD, 13'd0);
        check_control(32'h0010_0073, `ALU_ADD, 13'd0);
        check_control(32'd0, `ALU_ADD, 13'd0);

        $display("tb_control passed: %0d checks", r_checks);
        $finish;
    end
endmodule

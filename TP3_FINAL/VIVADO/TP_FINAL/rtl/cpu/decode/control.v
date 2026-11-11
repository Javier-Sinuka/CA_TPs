`timescale 1ns/1ps
`default_nettype none
`include "riscv_defs.vh"

module control (
    input  wire [31:0] i_instr,
    output reg  [3:0]  o_alu_op,
    output reg         o_alu_src_b,
    output reg         o_reg_write,
    output reg         o_mem_read,
    output reg         o_mem_write,
    output reg         o_mem_to_reg,
    output reg         o_branch,
    output reg         o_jump,
    output reg         o_jalr,
    output reg         o_lui,
    output reg         o_halt,
    output reg         o_uses_rs1,
    output reg         o_uses_rs2,
    output reg         o_valid_instr
);

    wire [6:0] w_opcode = i_instr[6:0];
    wire [2:0] w_funct3 = i_instr[14:12];
    wire [3:0] w_alu_op;
    wire       w_alu_valid;

    alu_control alu_control_inst (
        .i_opcode(w_opcode),
        .i_funct3(w_funct3),
        .i_funct7(i_instr[31:25]),
        .o_alu_op(w_alu_op),
        .o_valid(w_alu_valid)
    );

    always @(*) begin
        o_alu_op = `ALU_ADD;
        o_alu_src_b = 1'b0;
        o_reg_write = 1'b0;
        o_mem_read = 1'b0;
        o_mem_write = 1'b0;
        o_mem_to_reg = 1'b0;
        o_branch = 1'b0;
        o_jump = 1'b0;
        o_jalr = 1'b0;
        o_lui = 1'b0;
        o_halt = 1'b0;
        o_uses_rs1 = 1'b0;
        o_uses_rs2 = 1'b0;
        o_valid_instr = 1'b0;

        case (w_opcode)
            `RISCV_OPCODE_OP: if (w_alu_valid) begin
                o_alu_op = w_alu_op;
                o_reg_write = 1'b1;
                o_uses_rs1 = 1'b1;
                o_uses_rs2 = 1'b1;
                o_valid_instr = 1'b1;
            end
            `RISCV_OPCODE_OP_IMM: if (w_alu_valid) begin
                o_alu_op = w_alu_op;
                o_alu_src_b = 1'b1;
                o_reg_write = 1'b1;
                o_uses_rs1 = 1'b1;
                o_valid_instr = 1'b1;
            end
            `RISCV_OPCODE_LOAD: if (
                w_funct3 == 3'b000 ||
                w_funct3 == 3'b001 ||
                w_funct3 == 3'b010 ||
                w_funct3 == 3'b100 ||
                w_funct3 == 3'b101
            ) begin
                o_alu_src_b = 1'b1;
                o_reg_write = 1'b1;
                o_mem_read = 1'b1;
                o_mem_to_reg = 1'b1;
                o_uses_rs1 = 1'b1;
                o_valid_instr = 1'b1;
            end
            `RISCV_OPCODE_STORE: if (
                w_funct3 == 3'b000 ||
                w_funct3 == 3'b001 ||
                w_funct3 == 3'b010
            ) begin
                o_alu_src_b = 1'b1;
                o_mem_write = 1'b1;
                o_uses_rs1 = 1'b1;
                o_uses_rs2 = 1'b1;
                o_valid_instr = 1'b1;
            end
            `RISCV_OPCODE_BRANCH: if (
                w_funct3 == 3'b000 ||
                w_funct3 == 3'b001
            ) begin
                o_branch = 1'b1;
                o_uses_rs1 = 1'b1;
                o_uses_rs2 = 1'b1;
                o_valid_instr = 1'b1;
            end
            `RISCV_OPCODE_JAL: begin
                o_reg_write = 1'b1;
                o_jump = 1'b1;
                o_valid_instr = 1'b1;
            end
            `RISCV_OPCODE_JALR: if (w_funct3 == 3'b000) begin
                o_alu_src_b = 1'b1;
                o_reg_write = 1'b1;
                o_jump = 1'b1;
                o_jalr = 1'b1;
                o_uses_rs1 = 1'b1;
                o_valid_instr = 1'b1;
            end
            `RISCV_OPCODE_LUI: begin
                o_alu_src_b = 1'b1;
                o_reg_write = 1'b1;
                o_lui = 1'b1;
                o_valid_instr = 1'b1;
            end
            default: begin
            end
        endcase

        if (i_instr == `RISCV_HALT_INSTR) begin
            o_alu_op = `ALU_ADD;
            o_alu_src_b = 1'b0;
            o_reg_write = 1'b0;
            o_mem_read = 1'b0;
            o_mem_write = 1'b0;
            o_mem_to_reg = 1'b0;
            o_branch = 1'b0;
            o_jump = 1'b0;
            o_jalr = 1'b0;
            o_lui = 1'b0;
            o_halt = 1'b1;
            o_uses_rs1 = 1'b0;
            o_uses_rs2 = 1'b0;
            o_valid_instr = 1'b1;
        end
    end

endmodule

`default_nettype wire

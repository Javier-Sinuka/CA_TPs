`timescale 1ns/1ps
`default_nettype none
`include "riscv_defs.vh"

module alu_control (
    input  wire [6:0] i_opcode,
    input  wire [2:0] i_funct3,
    input  wire [6:0] i_funct7,
    output reg  [3:0] o_alu_op,
    output reg        o_valid
);

    always @(*) begin
        o_alu_op = `ALU_ADD;
        o_valid = 1'b0;

        if ((^{i_opcode, i_funct3, i_funct7}) !== 1'bx) begin
            casez ({i_opcode, i_funct3, i_funct7})
                {`RISCV_OPCODE_OP, 3'b000, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_ADD;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP, 3'b000, `RISCV_FUNCT7_ALT}: begin
                    o_alu_op = `ALU_SUB;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP, 3'b001, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_SLL;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP, 3'b010, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_SLT;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP, 3'b011, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_SLTU;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP, 3'b100, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_XOR;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP, 3'b101, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_SRL;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP, 3'b101, `RISCV_FUNCT7_ALT}: begin
                    o_alu_op = `ALU_SRA;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP, 3'b110, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_OR;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP, 3'b111, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_AND;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP_IMM, 3'b000, 7'b???????}: begin
                    o_alu_op = `ALU_ADD;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP_IMM, 3'b010, 7'b???????}: begin
                    o_alu_op = `ALU_SLT;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP_IMM, 3'b011, 7'b???????}: begin
                    o_alu_op = `ALU_SLTU;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP_IMM, 3'b100, 7'b???????}: begin
                    o_alu_op = `ALU_XOR;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP_IMM, 3'b110, 7'b???????}: begin
                    o_alu_op = `ALU_OR;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP_IMM, 3'b111, 7'b???????}: begin
                    o_alu_op = `ALU_AND;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP_IMM, 3'b001, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_SLL;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP_IMM, 3'b101, `RISCV_FUNCT7_BASE}: begin
                    o_alu_op = `ALU_SRL;
                    o_valid = 1'b1;
                end
                {`RISCV_OPCODE_OP_IMM, 3'b101, `RISCV_FUNCT7_ALT}: begin
                    o_alu_op = `ALU_SRA;
                    o_valid = 1'b1;
                end
                default: begin
                end
            endcase
        end
    end

endmodule

`default_nettype wire

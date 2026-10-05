`timescale 1ns/1ps
`default_nettype none
`include "riscv_defs.vh"

module alu (
    input  wire [31:0] i_operand_a,
    input  wire [31:0] i_operand_b,
    input  wire [3:0]  i_op,
    output reg  [31:0] o_result
);

    always @(*) begin
        o_result = 32'd0;

        case (i_op)
            `ALU_ADD:  o_result = i_operand_a + i_operand_b;
            `ALU_SUB:  o_result = i_operand_a - i_operand_b;
            `ALU_SLL:  o_result = i_operand_a << i_operand_b[4:0];
            `ALU_SRL:  o_result = i_operand_a >> i_operand_b[4:0];
            `ALU_SRA:  o_result = $signed(i_operand_a) >>> i_operand_b[4:0];
            `ALU_AND:  o_result = i_operand_a & i_operand_b;
            `ALU_OR:   o_result = i_operand_a | i_operand_b;
            `ALU_XOR:  o_result = i_operand_a ^ i_operand_b;
            `ALU_SLT:  o_result = ($signed(i_operand_a) < $signed(i_operand_b)) ? 32'd1 : 32'd0;
            `ALU_SLTU: o_result = (i_operand_a < i_operand_b) ? 32'd1 : 32'd0;
            default:   o_result = 32'd0;
        endcase
    end

endmodule

`default_nettype wire

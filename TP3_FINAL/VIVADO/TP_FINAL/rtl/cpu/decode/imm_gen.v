`timescale 1ns/1ps
`default_nettype none
`include "riscv_defs.vh"

module imm_gen (
    input  wire [31:0] i_instr,
    output reg  [31:0] o_imm
);

    always @(*) begin
        o_imm = 32'd0;

        case (i_instr[6:0])
            `RISCV_OPCODE_OP_IMM,
            `RISCV_OPCODE_LOAD,
            `RISCV_OPCODE_JALR:
                o_imm = {{20{i_instr[31]}}, i_instr[31:20]};
            `RISCV_OPCODE_STORE:
                o_imm = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]};
            `RISCV_OPCODE_BRANCH:
                o_imm = {{19{i_instr[31]}}, i_instr[31], i_instr[7], i_instr[30:25], i_instr[11:8], 1'b0};
            `RISCV_OPCODE_JAL:
                o_imm = {{11{i_instr[31]}}, i_instr[31], i_instr[19:12], i_instr[20], i_instr[30:21], 1'b0};
            `RISCV_OPCODE_LUI:
                o_imm = {i_instr[31:12], 12'b0};
            default:
                o_imm = 32'd0;
        endcase
    end

endmodule

`default_nettype wire

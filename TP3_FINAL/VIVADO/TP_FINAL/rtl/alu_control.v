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

        case (i_opcode)
            `RISCV_OPCODE_OP: begin
                case (i_funct3)
                    3'b000: begin
                        if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                            o_alu_op = `ALU_ADD;
                            o_valid = 1'b1;
                        end else if (i_funct7 == `RISCV_FUNCT7_ALT) begin
                            o_alu_op = `ALU_SUB;
                            o_valid = 1'b1;
                        end
                    end
                    3'b001: if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                        o_alu_op = `ALU_SLL;
                        o_valid = 1'b1;
                    end
                    3'b010: if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                        o_alu_op = `ALU_SLT;
                        o_valid = 1'b1;
                    end
                    3'b011: if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                        o_alu_op = `ALU_SLTU;
                        o_valid = 1'b1;
                    end
                    3'b100: if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                        o_alu_op = `ALU_XOR;
                        o_valid = 1'b1;
                    end
                    3'b101: begin
                        if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                            o_alu_op = `ALU_SRL;
                            o_valid = 1'b1;
                        end else if (i_funct7 == `RISCV_FUNCT7_ALT) begin
                            o_alu_op = `ALU_SRA;
                            o_valid = 1'b1;
                        end
                    end
                    3'b110: if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                        o_alu_op = `ALU_OR;
                        o_valid = 1'b1;
                    end
                    3'b111: if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                        o_alu_op = `ALU_AND;
                        o_valid = 1'b1;
                    end
                    default: begin
                    end
                endcase
            end
            `RISCV_OPCODE_OP_IMM: begin
                case (i_funct3)
                    3'b000: begin o_alu_op = `ALU_ADD;  o_valid = 1'b1; end
                    3'b010: begin o_alu_op = `ALU_SLT;  o_valid = 1'b1; end
                    3'b011: begin o_alu_op = `ALU_SLTU; o_valid = 1'b1; end
                    3'b100: begin o_alu_op = `ALU_XOR;  o_valid = 1'b1; end
                    3'b110: begin o_alu_op = `ALU_OR;   o_valid = 1'b1; end
                    3'b111: begin o_alu_op = `ALU_AND;  o_valid = 1'b1; end
                    3'b001: if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                        o_alu_op = `ALU_SLL;
                        o_valid = 1'b1;
                    end
                    3'b101: begin
                        if (i_funct7 == `RISCV_FUNCT7_BASE) begin
                            o_alu_op = `ALU_SRL;
                            o_valid = 1'b1;
                        end else if (i_funct7 == `RISCV_FUNCT7_ALT) begin
                            o_alu_op = `ALU_SRA;
                            o_valid = 1'b1;
                        end
                    end
                    default: begin
                    end
                endcase
            end
            default: begin
            end
        endcase
    end

endmodule

`default_nettype wire

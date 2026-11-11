`timescale 1ns/1ps
`default_nettype none

module forwarding_unit (
    input  wire       i_valid_ex,
    input  wire       i_uses_rs1_ex,
    input  wire       i_uses_rs2_ex,
    input  wire [4:0] i_rs1_ex,
    input  wire [4:0] i_rs2_ex,
    input  wire       i_valid_mem,
    input  wire       i_reg_write_mem,
    input  wire       i_mem_read_mem,
    input  wire [4:0] i_rd_mem,
    input  wire       i_valid_wb,
    input  wire       i_reg_write_wb,
    input  wire [4:0] i_rd_wb,
    output reg  [1:0] o_forward_a,
    output reg  [1:0] o_forward_b
);
    wire w_mem_writes = i_valid_mem && i_reg_write_mem && (i_rd_mem != 5'd0);
    wire w_wb_writes = i_valid_wb && i_reg_write_wb && (i_rd_wb != 5'd0);
    wire w_rs1_active = i_valid_ex && i_uses_rs1_ex;
    wire w_rs2_active = i_valid_ex && i_uses_rs2_ex;
    wire w_mem_match_a = w_rs1_active && w_mem_writes && (i_rd_mem == i_rs1_ex);
    wire w_mem_match_b = w_rs2_active && w_mem_writes && (i_rd_mem == i_rs2_ex);
    wire w_wb_match_a = w_rs1_active && w_wb_writes && (i_rd_wb == i_rs1_ex);
    wire w_wb_match_b = w_rs2_active && w_wb_writes && (i_rd_wb == i_rs2_ex);

    always @(*) begin
        casez ({w_mem_match_a, i_mem_read_mem, w_wb_match_a})
            3'b10?: o_forward_a = 2'b10;
            3'b0?1: o_forward_a = 2'b01;
            default: o_forward_a = 2'b00;
        endcase
    end

    always @(*) begin
        casez ({w_mem_match_b, i_mem_read_mem, w_wb_match_b})
            3'b10?: o_forward_b = 2'b10;
            3'b0?1: o_forward_b = 2'b01;
            default: o_forward_b = 2'b00;
        endcase
    end
endmodule

`default_nettype wire

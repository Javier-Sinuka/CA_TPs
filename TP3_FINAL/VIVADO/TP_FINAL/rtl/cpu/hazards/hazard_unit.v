`timescale 1ns/1ps
`default_nettype none

module hazard_unit (
    input  wire       i_valid_ex,
    input  wire       i_mem_read_ex,
    input  wire [4:0] i_rd_ex,
    input  wire       i_valid_id,
    input  wire       i_uses_rs1_id,
    input  wire       i_uses_rs2_id,
    input  wire [4:0] i_rs1_id,
    input  wire [4:0] i_rs2_id,
    output reg        o_stall
);
    wire w_load_pending = i_valid_ex && i_mem_read_ex && (i_rd_ex != 5'd0) && i_valid_id;
    wire w_rs1_match = i_uses_rs1_id && (i_rs1_id == i_rd_ex);
    wire w_rs2_match = i_uses_rs2_id && (i_rs2_id == i_rd_ex);

    always @(*) begin
        o_stall = 1'b0;
        casez ({w_load_pending, w_rs1_match, w_rs2_match})
            3'b11?, 3'b1?1: o_stall = 1'b1;
            default: begin end
        endcase
    end
endmodule

`default_nettype wire

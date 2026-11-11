`timescale 1ns/1ps
`default_nettype none

module execute_stage (
    input  wire         i_clock,
    input  wire         i_reset,
    input  wire         i_en,
    input  wire         i_flush,
    input  wire         i_stall,
    input  wire         i_valid_ex,
    input  wire [31:0]  i_pc_ex,
    input  wire [31:0]  i_rs1_data_ex,
    input  wire [31:0]  i_rs2_data_ex,
    input  wire [31:0]  i_imm_ex,
    input  wire [4:0]   i_rd_ex,
    input  wire [2:0]   i_funct3_ex,
    input  wire [3:0]   i_alu_op_ex,
    input  wire         i_alu_src_b_ex,
    input  wire         i_jump_ex,
    input  wire         i_lui_ex,
    input  wire         i_mem_read_ex,
    input  wire         i_mem_write_ex,
    input  wire         i_mem_to_reg_ex,
    input  wire         i_reg_write_ex,
    input  wire         i_halt_ex,
    output wire [31:0]  o_result_ex,
    output wire         o_valid_mem,
    output wire [31:0]  o_pc_mem,
    output wire [31:0]  o_result_mem,
    output wire [31:0]  o_store_data_mem,
    output wire [4:0]   o_rd_mem,
    output wire [2:0]   o_funct3_mem,
    output wire         o_mem_read_mem,
    output wire         o_mem_write_mem,
    output wire         o_mem_to_reg_mem,
    output wire         o_reg_write_mem,
    output wire         o_halt_mem,
    output wire [31:0]  o_info_mem
);

    wire [31:0] w_alu_operand_b_ex = i_alu_src_b_ex ? i_imm_ex : i_rs2_data_ex;
    wire [31:0] w_alu_result_ex;
    wire [31:0] w_link_ex = i_pc_ex + 32'd4;
    wire [31:0] w_result_ex = i_jump_ex ? w_link_ex :
                               i_lui_ex ? i_imm_ex : w_alu_result_ex;

    alu u_alu (
        .i_operand_a(i_rs1_data_ex),
        .i_operand_b(w_alu_operand_b_ex),
        .i_op(i_alu_op_ex),
        .o_result(w_alu_result_ex)
    );

    ex_mem u_ex_mem (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(i_en),
        .i_flush(i_flush),
        .i_stall(i_stall),
        .i_valid(i_valid_ex),
        .i_pc(i_pc_ex),
        .i_result(w_result_ex),
        .i_store_data(i_rs2_data_ex),
        .i_rd(i_rd_ex),
        .i_funct3(i_funct3_ex),
        .i_mem_read(i_mem_read_ex),
        .i_mem_write(i_mem_write_ex),
        .i_mem_to_reg(i_mem_to_reg_ex),
        .i_reg_write(i_reg_write_ex),
        .i_halt(i_halt_ex),
        .o_valid(o_valid_mem),
        .o_pc(o_pc_mem),
        .o_result(o_result_mem),
        .o_store_data(o_store_data_mem),
        .o_rd(o_rd_mem),
        .o_funct3(o_funct3_mem),
        .o_mem_read(o_mem_read_mem),
        .o_mem_write(o_mem_write_mem),
        .o_mem_to_reg(o_mem_to_reg_mem),
        .o_reg_write(o_reg_write_mem),
        .o_halt(o_halt_mem),
        .o_info(o_info_mem)
    );

    assign o_result_ex = w_result_ex;
endmodule

`default_nettype wire

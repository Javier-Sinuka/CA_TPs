`timescale 1ns/1ps
`default_nettype none

module decode_stage (
    input  wire         i_clock,
    input  wire         i_reset,
    input  wire         i_en,
    input  wire         i_flush,
    input  wire         i_stall,
    input  wire         i_valid_id,
    input  wire [31:0]  i_pc_id,
    input  wire [31:0]  i_instr_id,
    input  wire         i_valid_wb,
    input  wire         i_reg_write_wb,
    input  wire [4:0]   i_rd_wb,
    input  wire [31:0]  i_wdata_wb,
    input  wire [4:0]   i_dbg_reg_addr,
    output wire         o_valid_ex,
    output wire [31:0]  o_pc_ex,
    output wire [31:0]  o_rs1_data_ex,
    output wire [31:0]  o_rs2_data_ex,
    output wire [31:0]  o_imm_ex,
    output wire [4:0]   o_rd_ex,
    output wire [4:0]   o_rs1_ex,
    output wire [4:0]   o_rs2_ex,
    output wire [2:0]   o_funct3_ex,
    output wire [3:0]   o_alu_op_ex,
    output wire         o_alu_src_b_ex,
    output wire         o_mem_read_ex,
    output wire         o_mem_write_ex,
    output wire         o_mem_to_reg_ex,
    output wire         o_reg_write_ex,
    output wire         o_branch_ex,
    output wire         o_jump_ex,
    output wire         o_jalr_ex,
    output wire         o_lui_ex,
    output wire         o_halt_ex,
    output wire         o_uses_rs1_ex,
    output wire         o_uses_rs2_ex,
    output wire [31:0]  o_info_ex,
    output wire [31:0]  o_dbg_reg_data
);

    wire [4:0] w_rs1_id = i_instr_id[19:15];
    wire [4:0] w_rs2_id = i_instr_id[24:20];
    wire [4:0] w_rd_id = i_instr_id[11:7];
    wire [2:0] w_funct3_id = i_instr_id[14:12];
    wire [31:0] w_rs1_data_id;
    wire [31:0] w_rs2_data_id;
    wire [31:0] w_imm_id;
    wire [3:0]   w_alu_op_id;
    wire         w_alu_src_b_id;
    wire         w_reg_write_id;
    wire         w_mem_read_id;
    wire         w_mem_write_id;
    wire         w_mem_to_reg_id;
    wire         w_branch_id;
    wire         w_jump_id;
    wire         w_jalr_id;
    wire         w_lui_id;
    wire         w_halt_id;
    wire         w_uses_rs1_id;
    wire         w_uses_rs2_id;
    wire         w_valid_instr_id;
    wire w_decode_effective_id = i_valid_id && w_valid_instr_id;
    wire w_regfile_we = i_en && !i_reset && i_valid_wb && i_reg_write_wb;

    control u_control (
        .i_instr(i_instr_id),
        .o_alu_op(w_alu_op_id),
        .o_alu_src_b(w_alu_src_b_id),
        .o_reg_write(w_reg_write_id),
        .o_mem_read(w_mem_read_id),
        .o_mem_write(w_mem_write_id),
        .o_mem_to_reg(w_mem_to_reg_id),
        .o_branch(w_branch_id),
        .o_jump(w_jump_id),
        .o_jalr(w_jalr_id),
        .o_lui(w_lui_id),
        .o_halt(w_halt_id),
        .o_uses_rs1(w_uses_rs1_id),
        .o_uses_rs2(w_uses_rs2_id),
        .o_valid_instr(w_valid_instr_id)
    );

    imm_gen u_imm_gen (
        .i_instr(i_instr_id),
        .o_imm(w_imm_id)
    );

    regfile u_regfile (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(i_en),
        .i_reg_write(w_regfile_we),
        .i_rd(i_rd_wb),
        .i_wdata(i_wdata_wb),
        .i_rs1(w_rs1_id),
        .i_rs2(w_rs2_id),
        .o_rs1_data(w_rs1_data_id),
        .o_rs2_data(w_rs2_data_id),
        .i_dbg_addr(i_dbg_reg_addr),
        .o_dbg_data(o_dbg_reg_data)
    );

    id_ex u_id_ex (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(i_en),
        .i_flush(i_flush),
        .i_stall(i_stall),
        .i_valid(i_valid_id),
        .i_pc(i_pc_id),
        .i_rs1_data(w_rs1_data_id),
        .i_rs2_data(w_rs2_data_id),
        .i_imm(w_imm_id),
        .i_rd(w_rd_id),
        .i_rs1(w_rs1_id),
        .i_rs2(w_rs2_id),
        .i_funct3(w_funct3_id),
        .i_alu_op((w_decode_effective_id ? w_alu_op_id : 4'd0)),
        .i_alu_src_b((w_decode_effective_id && w_alu_src_b_id)),
        .i_mem_read((w_decode_effective_id && w_mem_read_id)),
        .i_mem_write((w_decode_effective_id && w_mem_write_id)),
        .i_mem_to_reg((w_decode_effective_id && w_mem_to_reg_id)),
        .i_reg_write((w_decode_effective_id && w_reg_write_id)),
        .i_branch((w_decode_effective_id && w_branch_id)),
        .i_jump((w_decode_effective_id && w_jump_id)),
        .i_jalr((w_decode_effective_id && w_jalr_id)),
        .i_lui((w_decode_effective_id && w_lui_id)),
        .i_halt((w_decode_effective_id && w_halt_id)),
        .i_uses_rs1((w_decode_effective_id && w_uses_rs1_id)),
        .i_uses_rs2((w_decode_effective_id && w_uses_rs2_id)),
        .o_valid(o_valid_ex),
        .o_pc(o_pc_ex),
        .o_rs1_data(o_rs1_data_ex),
        .o_rs2_data(o_rs2_data_ex),
        .o_imm(o_imm_ex),
        .o_rd(o_rd_ex),
        .o_rs1(o_rs1_ex),
        .o_rs2(o_rs2_ex),
        .o_funct3(o_funct3_ex),
        .o_alu_op(o_alu_op_ex),
        .o_alu_src_b(o_alu_src_b_ex),
        .o_mem_read(o_mem_read_ex),
        .o_mem_write(o_mem_write_ex),
        .o_mem_to_reg(o_mem_to_reg_ex),
        .o_reg_write(o_reg_write_ex),
        .o_branch(o_branch_ex),
        .o_jump(o_jump_ex),
        .o_jalr(o_jalr_ex),
        .o_lui(o_lui_ex),
        .o_halt(o_halt_ex),
        .o_uses_rs1(o_uses_rs1_ex),
        .o_uses_rs2(o_uses_rs2_ex),
        .o_info(o_info_ex)
    );
endmodule

`default_nettype wire

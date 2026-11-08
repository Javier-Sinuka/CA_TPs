`timescale 1ns/1ps
`default_nettype none
`include "riscv_defs.vh"

module cpu (
`include "cpu_ports.vh"
);
    reg [31:0] r_pc_if;
    reg [31:0] r_dbg_latch_word;
    reg        r_fetch_stopped;

    wire        w_adv = i_en && !o_halted;
    wire [31:0] w_pc_next_if = r_pc_if + 32'd4;
    wire        w_valid_id;
    wire [31:0] w_pc_id;
    wire [31:0] w_instr_id;
    wire [4:0]  w_rs1_id;
    wire [4:0]  w_rs2_id;
    wire        w_uses_rs1_id;
    wire        w_uses_rs2_id;
    wire        w_load_use_stall;

    wire         w_valid_ex;
    wire [31:0]  w_pc_ex;
    wire [31:0]  w_rs1_data_ex;
    wire [31:0]  w_rs2_data_ex;
    wire [31:0]  w_imm_ex;
    wire [4:0]   w_rd_ex;
    wire [4:0]   w_rs1_ex;
    wire [4:0]   w_rs2_ex;
    wire [2:0]   w_funct3_ex;
    wire [3:0]   w_alu_op_ex;
    wire         w_alu_src_b_ex;
    wire         w_mem_read_ex;
    wire         w_mem_write_ex;
    wire         w_mem_to_reg_ex;
    wire         w_reg_write_ex;
    wire         w_branch_ex;
    wire         w_jump_ex;
    wire         w_jalr_ex;
    wire         w_lui_ex;
    wire         w_halt_ex;
    wire         w_uses_rs1_ex;
    wire         w_uses_rs2_ex;
    wire [31:0]  w_info_ex;
    wire         w_valid_mem;
    wire [31:0]  w_pc_mem;
    wire [31:0]  w_result_mem;
    wire [31:0]  w_store_data_mem;
    wire [4:0]   w_rd_mem;
    wire [2:0]   w_funct3_mem;
    wire         w_mem_read_mem;
    wire         w_mem_write_mem;
    wire         w_mem_to_reg_mem;
    wire         w_reg_write_mem;
    wire         w_halt_mem;
    wire [31:0]  w_info_mem;
    wire [1:0] w_forward_a_ex;
    wire [1:0] w_forward_b_ex;
    wire [31:0] w_rs1_fwd_ex;
    wire [31:0] w_rs2_fwd_ex;
    wire [31:0] w_result_ex;
    reg         r_branch_taken_ex;
    wire        w_operands_equal_ex = w_rs1_fwd_ex == w_rs2_fwd_ex;
    wire [31:0] w_jalr_sum_ex = w_rs1_fwd_ex + w_imm_ex;
    wire [31:0] w_target_ex = w_jalr_ex
        ? {w_jalr_sum_ex[31:1], 1'b0}
        : w_pc_ex + w_imm_ex;
    wire        w_take_ex = w_valid_ex && (w_jump_ex || (w_branch_ex && r_branch_taken_ex));
    wire        w_halt_id = w_instr_id == `RISCV_HALT_INSTR;
    wire        w_halt_accept_id = !i_reset && w_adv && w_valid_id && w_halt_id
                                  && !w_take_ex && !w_load_use_stall;
    wire        w_stop_fetch = !w_take_ex && (r_fetch_stopped || w_halt_accept_id);

    wire         w_valid_wb;
    wire [31:0]  w_pc_wb;
    wire [31:0]  w_result_wb;
    wire [31:0]  w_load_data_wb;
    wire [4:0]   w_rd_wb;
    wire         w_mem_to_reg_wb;
    wire         w_reg_write_wb;
    wire         w_halt_wb;
    wire [31:0]  w_info_wb;
    wire [31:0] w_wb_data;
    wire w_regfile_we;
    wire w_dmem_we;

    function [31:0] select_forward;
        input [1:0] i_select;
        input [31:0] i_captured;
        input [31:0] i_result_mem;
        input [31:0] i_wb_data;
        begin
            casez (i_select)
                2'b10: select_forward = i_result_mem;
                2'b01: select_forward = i_wb_data;
                default: select_forward = i_captured;
            endcase
        end
    endfunction

    assign w_rs1_fwd_ex = select_forward(w_forward_a_ex, w_rs1_data_ex, w_result_mem, w_wb_data);
    assign w_rs2_fwd_ex = select_forward(w_forward_b_ex, w_rs2_data_ex, w_result_mem, w_wb_data);

    always @(*) begin
        r_branch_taken_ex = 1'b0;
        casez (w_funct3_ex)
            3'b000: r_branch_taken_ex = w_operands_equal_ex;
            3'b001: r_branch_taken_ex = !w_operands_equal_ex;
            default: begin end
        endcase
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_pc_if <= 32'd0;
        else if (w_adv) begin
            if (w_take_ex)
                r_pc_if <= w_target_ex;
            else if (!w_load_use_stall && !w_stop_fetch)
                r_pc_if <= w_pc_next_if;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_fetch_stopped <= 1'b0;
        else if (w_adv) begin
            if (w_take_ex)
                r_fetch_stopped <= 1'b0;
            else if (w_halt_accept_id)
                r_fetch_stopped <= 1'b1;
        end
    end

    if_id u_if_id (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(w_adv),
        .i_flush(w_take_ex || w_stop_fetch),
        .i_stall(w_load_use_stall),
        .i_valid(1'b1),
        .i_pc(r_pc_if),
        .i_instr(i_imem_data),
        .o_valid(w_valid_id),
        .o_pc(w_pc_id),
        .o_instr(w_instr_id)
    );

    decode_stage u_decode (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(w_adv),
        .i_flush(w_take_ex || w_load_use_stall || r_fetch_stopped),
        .i_stall(1'b0),
        .i_valid_id(w_valid_id),
        .i_pc_id(w_pc_id),
        .i_instr_id(w_instr_id),
        .i_valid_wb(w_valid_wb),
        .i_reg_write_wb(w_regfile_we),
        .i_rd_wb(w_rd_wb),
        .i_wdata_wb(w_wb_data),
        .i_dbg_reg_addr(i_dbg_reg_addr),
        .o_rs1_id(w_rs1_id),
        .o_rs2_id(w_rs2_id),
        .o_uses_rs1_id(w_uses_rs1_id),
        .o_uses_rs2_id(w_uses_rs2_id),
        .o_valid_ex(w_valid_ex),
        .o_pc_ex(w_pc_ex),
        .o_rs1_data_ex(w_rs1_data_ex),
        .o_rs2_data_ex(w_rs2_data_ex),
        .o_imm_ex(w_imm_ex),
        .o_rd_ex(w_rd_ex),
        .o_rs1_ex(w_rs1_ex),
        .o_rs2_ex(w_rs2_ex),
        .o_funct3_ex(w_funct3_ex),
        .o_alu_op_ex(w_alu_op_ex),
        .o_alu_src_b_ex(w_alu_src_b_ex),
        .o_mem_read_ex(w_mem_read_ex),
        .o_mem_write_ex(w_mem_write_ex),
        .o_mem_to_reg_ex(w_mem_to_reg_ex),
        .o_reg_write_ex(w_reg_write_ex),
        .o_branch_ex(w_branch_ex),
        .o_jump_ex(w_jump_ex),
        .o_jalr_ex(w_jalr_ex),
        .o_lui_ex(w_lui_ex),
        .o_halt_ex(w_halt_ex),
        .o_uses_rs1_ex(w_uses_rs1_ex),
        .o_uses_rs2_ex(w_uses_rs2_ex),
        .o_info_ex(w_info_ex),
        .o_dbg_reg_data(o_dbg_reg_data)
    );

    hazard_unit u_hazard (
        .i_valid_ex(w_valid_ex),
        .i_mem_read_ex(w_mem_read_ex),
        .i_rd_ex(w_rd_ex),
        .i_valid_id(w_valid_id),
        .i_uses_rs1_id(w_uses_rs1_id),
        .i_uses_rs2_id(w_uses_rs2_id),
        .i_rs1_id(w_rs1_id),
        .i_rs2_id(w_rs2_id),
        .o_stall(w_load_use_stall)
    );

    forwarding_unit u_forwarding (
        .i_valid_ex(w_valid_ex),
        .i_uses_rs1_ex(w_uses_rs1_ex),
        .i_uses_rs2_ex(w_uses_rs2_ex),
        .i_rs1_ex(w_rs1_ex),
        .i_rs2_ex(w_rs2_ex),
        .i_valid_mem(w_valid_mem),
        .i_reg_write_mem(w_reg_write_mem),
        .i_mem_read_mem(w_mem_read_mem),
        .i_rd_mem(w_rd_mem),
        .i_valid_wb(w_valid_wb),
        .i_reg_write_wb(w_reg_write_wb),
        .i_rd_wb(w_rd_wb),
        .o_forward_a(w_forward_a_ex),
        .o_forward_b(w_forward_b_ex)
    );

    execute_stage u_execute (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(w_adv),
        .i_flush(1'b0),
        .i_stall(1'b0),
        .i_valid_ex(w_valid_ex),
        .i_pc_ex(w_pc_ex),
        .i_rs1_data_ex(w_rs1_fwd_ex),
        .i_rs2_data_ex(w_rs2_fwd_ex),
        .i_imm_ex(w_imm_ex),
        .i_rd_ex(w_rd_ex),
        .i_funct3_ex(w_funct3_ex),
        .i_alu_op_ex(w_alu_op_ex),
        .i_alu_src_b_ex(w_alu_src_b_ex),
        .i_jump_ex(w_jump_ex),
        .i_lui_ex(w_lui_ex),
        .i_mem_read_ex(w_mem_read_ex),
        .i_mem_write_ex(w_mem_write_ex),
        .i_mem_to_reg_ex(w_mem_to_reg_ex),
        .i_reg_write_ex(w_reg_write_ex),
        .i_halt_ex(w_halt_ex),
        .o_result_ex(w_result_ex),
        .o_valid_mem(w_valid_mem),
        .o_pc_mem(w_pc_mem),
        .o_result_mem(w_result_mem),
        .o_store_data_mem(w_store_data_mem),
        .o_rd_mem(w_rd_mem),
        .o_funct3_mem(w_funct3_mem),
        .o_mem_read_mem(w_mem_read_mem),
        .o_mem_write_mem(w_mem_write_mem),
        .o_mem_to_reg_mem(w_mem_to_reg_mem),
        .o_reg_write_mem(w_reg_write_mem),
        .o_halt_mem(w_halt_mem),
        .o_info_mem(w_info_mem)
    );

    memory_stage u_memory (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(w_adv),
        .i_valid_mem(w_valid_mem),
        .i_pc_mem(w_pc_mem),
        .i_result_mem(w_result_mem),
        .i_store_data_mem(w_store_data_mem),
        .i_rd_mem(w_rd_mem),
        .i_funct3_mem(w_funct3_mem),
        .i_mem_read_mem(w_mem_read_mem),
        .i_mem_write_mem(w_mem_write_mem),
        .i_mem_to_reg_mem(w_mem_to_reg_mem),
        .i_reg_write_mem(w_reg_write_mem),
        .i_halt_mem(w_halt_mem),
        .i_dbg_mem_addr(i_dbg_mem_addr),
        .o_valid_wb(w_valid_wb),
        .o_pc_wb(w_pc_wb),
        .o_result_wb(w_result_wb),
        .o_load_data_wb(w_load_data_wb),
        .o_rd_wb(w_rd_wb),
        .o_mem_to_reg_wb(w_mem_to_reg_wb),
        .o_reg_write_wb(w_reg_write_wb),
        .o_halt_wb(w_halt_wb),
        .o_info_wb(w_info_wb),
        .o_wb_data(w_wb_data),
        .o_regfile_we(w_regfile_we),
        .o_dmem_we(w_dmem_we),
        .o_dbg_mem_data(o_dbg_mem_data),
        .o_dbg_mem_dirty(o_dbg_mem_dirty)
    );

    always @(*) begin
        r_dbg_latch_word = 32'd0;
        if ((^i_dbg_latch_sel) !== 1'bx) begin
            casez (i_dbg_latch_sel)
                4'd0: r_dbg_latch_word = w_pc_id;
                4'd1: r_dbg_latch_word = w_instr_id;
                4'd2: r_dbg_latch_word = w_pc_ex;
                4'd3: r_dbg_latch_word = w_rs1_data_ex;
                4'd4: r_dbg_latch_word = w_rs2_data_ex;
                4'd5: r_dbg_latch_word = w_imm_ex;
                4'd6: r_dbg_latch_word = w_info_ex;
                4'd7: r_dbg_latch_word = w_pc_mem;
                4'd8: r_dbg_latch_word = w_result_mem;
                4'd9: r_dbg_latch_word = w_store_data_mem;
                4'd10: r_dbg_latch_word = w_info_mem;
                4'd11: r_dbg_latch_word = w_pc_wb;
                4'd12: r_dbg_latch_word = w_result_wb;
                4'd13: r_dbg_latch_word = w_load_data_wb;
                4'd14: r_dbg_latch_word = w_info_wb;
                4'd15: r_dbg_latch_word = {28'd0, w_valid_wb, w_valid_mem, w_valid_ex, w_valid_id};
                default: begin end
            endcase
        end
    end

    assign o_imem_addr = r_pc_if;
    assign o_dbg_pc = r_pc_if;
    assign o_dbg_latch_word = r_dbg_latch_word;
    assign o_halted = w_valid_wb && w_halt_wb;
endmodule

`default_nettype wire

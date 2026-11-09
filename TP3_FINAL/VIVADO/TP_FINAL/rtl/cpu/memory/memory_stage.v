`timescale 1ns/1ps
`default_nettype none

module memory_stage (
    input  wire         i_clock,
    input  wire         i_reset,
    input  wire         i_en,
    input  wire         i_valid_mem,
    input  wire [31:0]  i_pc_mem,
    input  wire [31:0]  i_result_mem,
    input  wire [31:0]  i_store_data_mem,
    input  wire [4:0]   i_rd_mem,
    input  wire [2:0]   i_funct3_mem,
    input  wire         i_mem_read_mem,
    input  wire         i_mem_write_mem,
    input  wire         i_mem_to_reg_mem,
    input  wire         i_reg_write_mem,
    input  wire         i_halt_mem,
    input  wire [7:0]   i_dbg_mem_addr,
    output wire         o_valid_wb,
    output wire [31:0]  o_pc_wb,
    output wire [31:0]  o_result_wb,
    output wire [31:0]  o_load_data_wb,
    output wire [4:0]   o_rd_wb,
    output wire         o_mem_to_reg_wb,
    output wire         o_reg_write_wb,
    output wire         o_halt_wb,
    output wire [31:0]  o_info_wb,
    output wire [31:0]  o_wb_data,
    output wire         o_regfile_we,
    output wire         o_dmem_we,
    output wire [31:0]  o_dbg_mem_data,
    output wire         o_dbg_mem_dirty
);

    wire [31:0] w_dmem_load_data;
    wire [31:0] w_load_data_mem = (i_valid_mem && i_mem_read_mem) ? w_dmem_load_data : 32'd0;
    wire w_dmem_we = i_en && !i_reset && i_valid_mem && i_mem_write_mem;
    wire w_regfile_we = i_en && !i_reset && o_valid_wb && o_reg_write_wb && (o_rd_wb != 5'd0);

    dmem u_dmem (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(i_en),
        .i_we(w_dmem_we),
        .i_addr(i_result_mem),
        .i_store_data(i_store_data_mem),
        .i_funct3(i_funct3_mem),
        .o_load_data(w_dmem_load_data),
        .i_dbg_addr(i_dbg_mem_addr),
        .o_dbg_data(o_dbg_mem_data),
        .o_dbg_dirty(o_dbg_mem_dirty)
    );

    mem_wb u_mem_wb (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(i_en),
        .i_flush(1'b0),
        .i_stall(1'b0),
        .i_valid(i_valid_mem),
        .i_pc(i_pc_mem),
        .i_result(i_result_mem),
        .i_load_data(w_load_data_mem),
        .i_rd(i_rd_mem),
        .i_mem_to_reg(i_mem_to_reg_mem),
        .i_reg_write(i_reg_write_mem),
        .i_halt(i_halt_mem),
        .o_valid(o_valid_wb),
        .o_pc(o_pc_wb),
        .o_result(o_result_wb),
        .o_load_data(o_load_data_wb),
        .o_rd(o_rd_wb),
        .o_mem_to_reg(o_mem_to_reg_wb),
        .o_reg_write(o_reg_write_wb),
        .o_halt(o_halt_wb),
        .o_info(o_info_wb)
    );

    assign o_wb_data = o_mem_to_reg_wb ? o_load_data_wb : o_result_wb;
    assign o_regfile_we = w_regfile_we;
    assign o_dmem_we = w_dmem_we;
endmodule

`default_nettype wire

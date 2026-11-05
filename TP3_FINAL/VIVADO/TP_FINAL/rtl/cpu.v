`timescale 1ns/1ps
`default_nettype none

module cpu (
`include "cpu_ports.vh"
);
    reg [31:0] r_pc_if;
    reg [31:0] r_dbg_latch_word;

    wire        w_adv = i_en && !o_halted;
    wire [31:0] w_pc_next_if = r_pc_if + 32'd4;
    wire        w_valid_id;
    wire [31:0] w_pc_id;
    wire [31:0] w_instr_id;

    always @(posedge i_clock) begin
        if (i_reset)
            r_pc_if <= 32'd0;
        else if (w_adv)
            r_pc_if <= w_pc_next_if;
    end

    if_id u_if_id (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_en(w_adv),
        .i_flush(1'b0),
        .i_stall(1'b0),
        .i_valid(1'b1),
        .i_pc(r_pc_if),
        .i_instr(i_imem_data),
        .o_valid(w_valid_id),
        .o_pc(w_pc_id),
        .o_instr(w_instr_id)
    );

    always @(*) begin
        r_dbg_latch_word = 32'd0;
        if ((^i_dbg_latch_sel) !== 1'bx) begin
            casez (i_dbg_latch_sel)
                4'd0: r_dbg_latch_word = w_pc_id;
                4'd1: r_dbg_latch_word = w_instr_id;
                4'd15: r_dbg_latch_word = {31'd0, w_valid_id};
                default: begin end
            endcase
        end
    end

    assign o_imem_addr = r_pc_if;
    assign o_dbg_pc = r_pc_if;
    assign o_dbg_latch_word = r_dbg_latch_word;
    assign o_halted = 1'b0;
    assign o_dbg_reg_data = 32'd0;
    assign o_dbg_mem_data = 32'd0;
    assign o_dbg_mem_dirty = 1'b0;
endmodule

`default_nettype wire

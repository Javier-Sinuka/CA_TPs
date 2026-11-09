`timescale 1ns/1ps
`default_nettype none

// CPU de mentira con la interfaz real (interfaz_cpu.md §8). Su estado depende
// solo de r_cycles, así sw/host/stub_model.py lo predice exactamente.
module cpu_stub #(
    parameter HALT_AT = 20          // 0 = nunca se detiene
)(
`include "cpu_ports.vh"
);
    reg [31:0] r_cycles;

    wire w_adv = i_en && !o_halted;

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_cycles <= 32'd0;
        end else if (w_adv) begin
            r_cycles <= r_cycles + 32'd1;
        end
    end

    assign o_halted         = (HALT_AT != 0) && (r_cycles == HALT_AT);
    assign o_dbg_pc         = r_cycles << 2;
    assign o_imem_addr      = r_cycles << 2;
    assign o_dbg_reg_data   = (i_dbg_reg_addr == 5'd0) ? 32'd0
                                                       : {r_cycles[23:0], 3'b000, i_dbg_reg_addr};
    assign o_dbg_latch_word = {8'h1A, 4'h0, i_dbg_latch_sel, r_cycles[15:0]};

    wire w_dirty_idx = (i_dbg_mem_addr == 8'd4) || (i_dbg_mem_addr == 8'd16) ||
                       (i_dbg_mem_addr == 8'd63);
    assign o_dbg_mem_dirty = (r_cycles != 32'd0) && w_dirty_idx;
    assign o_dbg_mem_data  = o_dbg_mem_dirty ? {8'hD0, 16'h0000, i_dbg_mem_addr} : 32'd0;

    // i_imem_data se ignora a propósito: el stub no ejecuta instrucciones.
endmodule

`default_nettype wire

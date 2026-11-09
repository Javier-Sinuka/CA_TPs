`timescale 1ns/1ps
// Este TB NO debe compilar: DIV = 1. Lo usa el paso 2 de B-02 a mano; no va en TBS.
module tb_baud_div1;
    reg r_clock = 1'b0, r_reset = 1'b1;
    wire w_tick;
    baud_gen #(.CLOCK_FREQ(16_000_000), .BAUD_RATE(1_000_000)) u_dut (
        .i_reset(r_reset), .i_clock(r_clock), .o_baud_tick(w_tick));
endmodule

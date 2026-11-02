`timescale 1ns/1ps
`default_nettype none

// Alternativa al Clock Wizard (D-13): MMCM instanciado a mano, mismo nombre y puertos que el IP.
// VCO = 100 MHz × 10 = 1000 MHz; salida = 1000 MHz / CLKOUT0_DIVIDE.
// build_bit.tcl define CLKOUT0_DIVIDE = 1000 / MHZ (20.000 para 50 MHz, 10.000 para 100 MHz).
`ifndef CLKOUT0_DIVIDE
`define CLKOUT0_DIVIDE 20.000
`endif

module clk_wiz_0 (
    input  wire clk_in1,
    output wire clk_out1,
    output wire locked
);
    wire w_clkfb;
    wire w_clkout0;

    MMCME2_BASE #(
        .CLKIN1_PERIOD(10.0),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.0),
        .CLKOUT0_DIVIDE_F(`CLKOUT0_DIVIDE)
    ) u_mmcm (
        .CLKIN1(clk_in1),
        .CLKFBIN(w_clkfb),
        .CLKFBOUT(w_clkfb),
        .CLKFBOUTB(),
        .CLKOUT0(w_clkout0),
        .CLKOUT0B(),
        .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(locked),
        .PWRDWN(1'b0),
        .RST(1'b0)
    );

    BUFG u_bufg (
        .I(w_clkout0),
        .O(clk_out1)
    );
endmodule

`default_nettype wire

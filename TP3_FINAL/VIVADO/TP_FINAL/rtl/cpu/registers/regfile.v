`timescale 1ns/1ps
`default_nettype none

module regfile (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_en,
    input  wire        i_reg_write,
    input  wire [4:0]  i_rd,
    input  wire [31:0] i_wdata,
    input  wire [4:0]  i_rs1,
    input  wire [4:0]  i_rs2,
    output wire [31:0] o_rs1_data,
    output wire [31:0] o_rs2_data,
    input  wire [4:0]  i_dbg_addr,
    output wire [31:0] o_dbg_data
);
    reg [31:0] r_regs [1:31];
    wire w_we = i_en && i_reg_write && (i_rd != 5'd0) && !i_reset;

    genvar g_reg;
    generate
        for (g_reg = 1; g_reg < 32; g_reg = g_reg + 1) begin : g_register
            always @(posedge i_clock) begin
                if (i_reset)
                    r_regs[g_reg] <= 32'd0;
                else if (w_we && (i_rd == g_reg))
                    r_regs[g_reg] <= i_wdata;
            end
        end
    endgenerate

    assign o_rs1_data = (i_rs1 == 5'd0) ? 32'd0 :
                        (w_we && (i_rd == i_rs1)) ? i_wdata : r_regs[i_rs1];
    assign o_rs2_data = (i_rs2 == 5'd0) ? 32'd0 :
                        (w_we && (i_rd == i_rs2)) ? i_wdata : r_regs[i_rs2];
    assign o_dbg_data = (i_dbg_addr == 5'd0) ? 32'd0 : r_regs[i_dbg_addr];
endmodule

`default_nettype wire

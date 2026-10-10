`timescale 1ns/1ps
`default_nettype none

module regfile (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_write_en,
    input  wire [4:0]  i_write_addr,
    input  wire [31:0] i_write_data,
    input  wire [4:0]  i_read_addr_a,
    input  wire [4:0]  i_read_addr_b,
    input  wire [4:0]  i_dbg_addr,
    output wire [31:0] o_read_data_a,
    output wire [31:0] o_read_data_b,
    output wire [31:0] o_dbg_data
);

    reg [31:0] r_regs [0:31];
    integer r_index;

    always @(posedge i_clk) begin
        if (i_rst) begin
            for (r_index = 0; r_index < 32; r_index = r_index + 1)
                r_regs[r_index] <= 32'd0;
        end else if (i_write_en && i_write_addr != 5'd0) begin
            r_regs[i_write_addr] <= i_write_data;
        end
    end

    assign o_read_data_a = (i_read_addr_a == 5'd0) ? 32'd0 :
                           (i_write_en && !i_rst && i_write_addr != 5'd0 && i_write_addr == i_read_addr_a) ? i_write_data :
                           r_regs[i_read_addr_a];
    assign o_read_data_b = (i_read_addr_b == 5'd0) ? 32'd0 :
                           (i_write_en && !i_rst && i_write_addr != 5'd0 && i_write_addr == i_read_addr_b) ? i_write_data :
                           r_regs[i_read_addr_b];
    assign o_dbg_data = (i_dbg_addr == 5'd0) ? 32'd0 : r_regs[i_dbg_addr];

endmodule

`default_nettype wire

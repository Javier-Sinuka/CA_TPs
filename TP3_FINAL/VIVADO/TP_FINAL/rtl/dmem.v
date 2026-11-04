`timescale 1ns/1ps
`default_nettype none

module dmem (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_en,
    input  wire        i_we,
    input  wire [31:0] i_addr,
    input  wire [31:0] i_store_data,
    input  wire [2:0]  i_funct3,
    output wire [31:0] o_load_data,
    input  wire [7:0]  i_dbg_addr,
    output wire [31:0] o_dbg_data,
    output wire        o_dbg_dirty
);
    reg [31:0] r_mem [0:255];
    reg [255:0] r_dirty;
    reg [31:0] r_store_mask;
    reg [31:0] r_store_shifted;
    reg        r_store_valid;
    reg [31:0] r_load_data;

    wire [7:0] w_idx = i_addr[9:2];
    wire [4:0] w_byte_shift = {i_addr[1:0], 3'b000};
    wire [4:0] w_half_shift = {i_addr[1], 4'b0000};
    wire [31:0] w_old = r_dirty[w_idx] ? r_mem[w_idx] : 32'd0;
    wire [7:0] w_byte = w_old[w_byte_shift +: 8];
    wire [15:0] w_half = w_old[w_half_shift +: 16];
    wire [31:0] w_new = (w_old & ~r_store_mask) |
                        (r_store_shifted & r_store_mask);
    wire w_we = i_en && i_we && !i_reset && r_store_valid;

    always @(*) begin
        r_store_mask = 32'd0;
        r_store_shifted = 32'd0;
        r_store_valid = 1'b0;
        casez ({i_funct3, i_addr[1:0]})
            5'b000_??: begin
                r_store_mask = 32'h0000_00ff << w_byte_shift;
                r_store_shifted = {24'd0, i_store_data[7:0]} << w_byte_shift;
                r_store_valid = 1'b1;
            end
            5'b001_??: begin
                r_store_mask = 32'h0000_ffff << w_half_shift;
                r_store_shifted = {16'd0, i_store_data[15:0]} << w_half_shift;
                r_store_valid = 1'b1;
            end
            5'b010_??: begin
                r_store_mask = 32'hffff_ffff;
                r_store_shifted = i_store_data;
                r_store_valid = 1'b1;
            end
            default: begin end
        endcase
    end

    always @(*) begin
        r_load_data = 32'd0;
        casez ({i_funct3, i_addr[1:0]})
            5'b000_??: r_load_data = {{24{w_byte[7]}}, w_byte};
            5'b001_??: r_load_data = {{16{w_half[15]}}, w_half};
            5'b010_??: r_load_data = w_old;
            5'b100_??: r_load_data = {24'd0, w_byte};
            5'b101_??: r_load_data = {16'd0, w_half};
            default: begin end
        endcase
    end

    always @(posedge i_clock) begin
        if (w_we)
            r_mem[w_idx] <= w_new;
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_dirty <= 256'd0;
        else if (w_we)
            r_dirty[w_idx] <= 1'b1;
    end

    assign o_load_data = r_load_data;
    assign o_dbg_dirty = r_dirty[i_dbg_addr];
    assign o_dbg_data = r_dirty[i_dbg_addr] ? r_mem[i_dbg_addr] : 32'd0;
endmodule

`default_nettype wire

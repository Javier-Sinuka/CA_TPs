`timescale 1ns/1ps
`default_nettype none

module dmem #(
    parameter integer WORDS = 256
) (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire        i_run_start,
    input  wire [31:0] i_cpu_addr,
    input  wire [31:0] i_cpu_write_data,
    input  wire [2:0]  i_cpu_funct3,
    input  wire        i_cpu_read_en,
    input  wire        i_cpu_write_en,
    output reg  [31:0] o_cpu_read_data,
    output wire        o_cpu_error,
    input  wire [31:0] i_dbg_addr,
    input  wire        i_dbg_write_en,
    input  wire [31:0] i_dbg_write_data,
    output wire [31:0] o_dbg_data,
    output wire        o_dbg_touched,
    output wire        o_dbg_dirty,
    output wire        o_dbg_error
);

    reg [7:0] r_mem0 [0:WORDS-1];
    reg [7:0] r_mem1 [0:WORDS-1];
    reg [7:0] r_mem2 [0:WORDS-1];
    reg [7:0] r_mem3 [0:WORDS-1];
    reg [WORDS-1:0] r_touched;
    reg [WORDS-1:0] r_dirty;
    reg [1:0] r_size;
    reg       r_type_valid;
    reg [3:0] r_byte_en;
    localparam integer INDEX_WIDTH = (WORDS > 1) ? $clog2(WORDS) : 1;

    wire [31:0] w_cpu_word_addr = {2'b00, i_cpu_addr[31:2]};
    wire [31:0] w_dbg_word_addr = {2'b00, i_dbg_addr[31:2]};
    wire [INDEX_WIDTH-1:0] w_cpu_index = i_cpu_addr[INDEX_WIDTH+1:2];
    wire [INDEX_WIDTH-1:0] w_dbg_index = i_dbg_addr[INDEX_WIDTH+1:2];
    wire w_cpu_active = i_cpu_read_en || i_cpu_write_en;
    wire w_cpu_range = w_cpu_word_addr < WORDS;
    wire w_dbg_range = w_dbg_word_addr < WORDS;
    wire w_aligned = (r_size == 2'd0) ||
                     (r_size == 2'd1 && i_cpu_addr[0] == 1'b0) ||
                     (r_size == 2'd2 && i_cpu_addr[1:0] == 2'b00);
    wire w_cpu_valid = (i_cpu_read_en ^ i_cpu_write_en) && r_type_valid &&
                       w_cpu_range && w_aligned && !i_dbg_write_en;
    wire [31:0] w_store_data = i_cpu_write_data << (i_cpu_addr[1:0] * 8);
    wire [31:0] w_cpu_word = w_cpu_valid && i_cpu_read_en ?
                              {r_mem3[w_cpu_index], r_mem2[w_cpu_index],
                               r_mem1[w_cpu_index], r_mem0[w_cpu_index]} : 32'd0;
    wire [7:0] w_byte_data = w_cpu_word[(i_cpu_addr[1:0] * 8) +: 8];
    wire [15:0] w_half_data = i_cpu_addr[1] ? w_cpu_word[31:16] : w_cpu_word[15:0];

    assign o_cpu_error = w_cpu_active && !w_cpu_valid;
    assign o_dbg_error = !w_dbg_range || i_dbg_addr[1:0] != 2'b00;
    assign o_dbg_data = o_dbg_error ? 32'd0 :
                        {r_mem3[w_dbg_index], r_mem2[w_dbg_index],
                         r_mem1[w_dbg_index], r_mem0[w_dbg_index]};
    assign o_dbg_touched = o_dbg_error ? 1'b0 : r_touched[w_dbg_index];
    assign o_dbg_dirty = o_dbg_error ? 1'b0 : r_dirty[w_dbg_index];

    always @(*) begin
        r_size = 2'd0;
        r_type_valid = 1'b0;

        if (i_cpu_read_en && !i_cpu_write_en) begin
            case (i_cpu_funct3)
                3'b000, 3'b100: begin r_size = 2'd0; r_type_valid = 1'b1; end
                3'b001, 3'b101: begin r_size = 2'd1; r_type_valid = 1'b1; end
                3'b010:         begin r_size = 2'd2; r_type_valid = 1'b1; end
                default: begin end
            endcase
        end else if (i_cpu_write_en && !i_cpu_read_en) begin
            case (i_cpu_funct3)
                3'b000: begin r_size = 2'd0; r_type_valid = 1'b1; end
                3'b001: begin r_size = 2'd1; r_type_valid = 1'b1; end
                3'b010: begin r_size = 2'd2; r_type_valid = 1'b1; end
                default: begin end
            endcase
        end
    end

    always @(*) begin
        r_byte_en = 4'b0000;

        if (w_cpu_valid && i_cpu_write_en) begin
            case (r_size)
                2'd0: r_byte_en = 4'b0001 << i_cpu_addr[1:0];
                2'd1: r_byte_en = 4'b0011 << i_cpu_addr[1:0];
                2'd2: r_byte_en = 4'b1111;
                default: begin end
            endcase
        end
    end

    always @(*) begin
        o_cpu_read_data = 32'd0;

        if (w_cpu_valid && i_cpu_read_en) begin
            case (i_cpu_funct3)
                3'b000: o_cpu_read_data = {{24{w_byte_data[7]}}, w_byte_data};
                3'b001: o_cpu_read_data = {{16{w_half_data[15]}}, w_half_data};
                3'b010: o_cpu_read_data = w_cpu_word;
                3'b100: o_cpu_read_data = {24'd0, w_byte_data};
                3'b101: o_cpu_read_data = {16'd0, w_half_data};
                default: begin end
            endcase
        end
    end

    always @(posedge i_clk) begin
        if (i_dbg_write_en && !o_dbg_error)
            r_mem0[w_dbg_index] <= i_dbg_write_data[7:0];
        else if (r_byte_en[0])
            r_mem0[w_cpu_index] <= w_store_data[7:0];
    end

    always @(posedge i_clk) begin
        if (i_dbg_write_en && !o_dbg_error)
            r_mem1[w_dbg_index] <= i_dbg_write_data[15:8];
        else if (r_byte_en[1])
            r_mem1[w_cpu_index] <= w_store_data[15:8];
    end

    always @(posedge i_clk) begin
        if (i_dbg_write_en && !o_dbg_error)
            r_mem2[w_dbg_index] <= i_dbg_write_data[23:16];
        else if (r_byte_en[2])
            r_mem2[w_cpu_index] <= w_store_data[23:16];
    end

    always @(posedge i_clk) begin
        if (i_dbg_write_en && !o_dbg_error)
            r_mem3[w_dbg_index] <= i_dbg_write_data[31:24];
        else if (r_byte_en[3])
            r_mem3[w_cpu_index] <= w_store_data[31:24];
    end

    always @(posedge i_clk) begin
        if (i_rst || i_run_start) begin
            r_touched <= {WORDS{1'b0}};
        end else if (w_cpu_valid)
            r_touched[w_cpu_index] <= 1'b1;
    end

    always @(posedge i_clk) begin
        if (i_rst || i_run_start) begin
            r_dirty <= {WORDS{1'b0}};
        end else if (w_cpu_valid && i_cpu_write_en)
            r_dirty[w_cpu_index] <= 1'b1;
    end

endmodule

`default_nettype wire

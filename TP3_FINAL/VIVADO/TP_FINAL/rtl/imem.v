`timescale 1ns/1ps
`default_nettype none

module imem #(
    parameter integer WORDS = 256
) (
    input  wire        i_clk,
    input  wire        i_rst,
    input  wire [31:0] i_fetch_addr,
    output wire [31:0] o_fetch_data,
    output wire        o_fetch_error,
    input  wire        i_load_start,
    input  wire        i_load_write,
    input  wire [31:0] i_load_addr,
    input  wire [31:0] i_load_data,
    input  wire        i_load_commit,
    output reg         o_program_valid,
    output reg         o_load_error,
    output reg  [31:0] o_program_words
);

    reg [31:0] r_mem [0:WORDS-1];
    reg        r_loading;
    localparam integer INDEX_WIDTH = (WORDS > 1) ? $clog2(WORDS) : 1;

    wire [31:0] w_fetch_word_addr = {2'b00, i_fetch_addr[31:2]};
    wire [31:0] w_load_word_addr = {2'b00, i_load_addr[31:2]};
    wire [INDEX_WIDTH-1:0] w_fetch_index = i_fetch_addr[INDEX_WIDTH+1:2];
    wire [INDEX_WIDTH-1:0] w_load_index = i_load_addr[INDEX_WIDTH+1:2];
    wire w_fetch_range = (w_fetch_word_addr < WORDS);
    wire w_fetch_loaded = (w_fetch_word_addr < o_program_words);
    wire w_load_range = (w_load_word_addr < WORDS);
    wire w_load_expected = (w_load_word_addr == o_program_words);
    wire w_load_valid = r_loading && !o_load_error &&
                        i_load_addr[1:0] == 2'b00 && w_load_range && w_load_expected;

    assign o_fetch_error = !o_program_valid || i_fetch_addr[1:0] != 2'b00 ||
                           !w_fetch_range || !w_fetch_loaded;
    assign o_fetch_data = o_fetch_error ? 32'd0 : r_mem[w_fetch_index];

    always @(posedge i_clk) begin
        if (i_load_write && !i_rst && !i_load_start && !i_load_commit && w_load_valid)
            r_mem[w_load_index] <= i_load_data;
    end

    always @(posedge i_clk) begin
        if (i_rst)
            r_loading <= 1'b0;
        else if (i_load_start)
            r_loading <= 1'b1;
        else if (i_load_commit)
            r_loading <= 1'b0;
    end

    always @(posedge i_clk) begin
        if (i_rst || i_load_start)
            o_program_valid <= 1'b0;
        else if (i_load_commit)
            o_program_valid <= r_loading && !o_load_error && !i_load_write && o_program_words != 32'd0;
    end

    always @(posedge i_clk) begin
        if (i_rst || i_load_start)
            o_load_error <= 1'b0;
        else if ((i_load_write && (!w_load_valid || i_load_commit)) ||
                 (i_load_commit && (!r_loading || o_program_words == 32'd0)))
            o_load_error <= 1'b1;
    end

    always @(posedge i_clk) begin
        if (i_rst || i_load_start)
            o_program_words <= 32'd0;
        else if (i_load_write && !i_load_commit && w_load_valid)
            o_program_words <= o_program_words + 32'd1;
    end

endmodule

`default_nettype wire

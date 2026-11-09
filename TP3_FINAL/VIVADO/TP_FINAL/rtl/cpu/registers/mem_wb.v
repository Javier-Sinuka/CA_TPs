`timescale 1ns/1ps
`default_nettype none

module mem_wb (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_en,
    input  wire        i_flush,
    input  wire        i_stall,
    input  wire        i_valid,
    input  wire [31:0] i_pc,
    input  wire [31:0] i_result,
    input  wire [31:0] i_load_data,
    input  wire [4:0] i_rd,
    input  wire        i_mem_to_reg,
    input  wire        i_reg_write,
    input  wire        i_halt,
    output wire        o_valid,
    output wire [31:0] o_pc,
    output wire [31:0] o_result,
    output wire [31:0] o_load_data,
    output wire [4:0] o_rd,
    output wire        o_mem_to_reg,
    output wire        o_reg_write,
    output wire        o_halt,
    output wire [31:0] o_info
);

    reg r_valid;
    reg [31:0] r_pc;
    reg [31:0] r_result;
    reg [31:0] r_load_data;
    reg [4:0] r_rd;
    reg r_mem_to_reg;
    reg r_reg_write;
    reg r_halt;

    assign o_valid = r_valid;
    assign o_pc = r_pc;
    assign o_result = r_result;
    assign o_load_data = r_load_data;
    assign o_rd = r_rd;
    assign o_mem_to_reg = r_mem_to_reg;
    assign o_reg_write = r_reg_write;
    assign o_halt = r_halt;
    assign o_info = {
        r_halt, 1'd0, 1'd0, 1'd0, 1'd0, r_reg_write, r_mem_to_reg, 1'd0, 1'd0, 1'd0, 4'd0, 3'd0, 5'd0, 5'd0, r_rd
    };

    always @(posedge i_clock) begin
        if (i_reset)
            r_valid <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_valid <= 1'd0;
            else if (!i_stall)
                r_valid <= i_valid;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_pc <= 32'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_pc <= i_pc;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_result <= 32'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_result <= i_result;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_load_data <= 32'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_load_data <= i_load_data;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_rd <= 5'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_rd <= i_rd;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_mem_to_reg <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_mem_to_reg <= 1'd0;
            else if (!i_stall)
                r_mem_to_reg <= i_valid ? i_mem_to_reg : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_reg_write <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_reg_write <= 1'd0;
            else if (!i_stall)
                r_reg_write <= i_valid ? i_reg_write : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_halt <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_halt <= 1'd0;
            else if (!i_stall)
                r_halt <= i_valid ? i_halt : 1'd0;
        end
    end

endmodule

`default_nettype wire

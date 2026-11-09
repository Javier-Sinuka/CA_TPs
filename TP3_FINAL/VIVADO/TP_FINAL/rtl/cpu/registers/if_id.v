`timescale 1ns/1ps
`default_nettype none

module if_id (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_en,
    input  wire        i_flush,
    input  wire        i_stall,
    input  wire        i_valid,
    input  wire [31:0] i_pc,
    input  wire [31:0] i_instr,
    output wire        o_valid,
    output wire [31:0] o_pc,
    output wire [31:0] o_instr
);

    reg r_valid;
    reg [31:0] r_pc;
    reg [31:0] r_instr;

    assign o_valid = r_valid;
    assign o_pc = r_pc;
    assign o_instr = r_instr;

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
            r_instr <= 32'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_instr <= i_instr;
        end
    end

endmodule

`default_nettype wire

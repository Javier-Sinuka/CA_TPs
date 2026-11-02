`timescale 1ns/1ps
`default_nettype none

// Memoria de instrucciones: 256 palabras, lectura asíncrona, escritura desde la
// Debug Unit. Arranca llena de HALT (interfaz_cpu.md §5, D-20).
module imem (
    input  wire        i_clock,
    input  wire [7:0]  i_raddr,
    output wire [31:0] o_rdata,
    input  wire        i_we,
    input  wire [7:0]  i_waddr,
    input  wire [31:0] i_wdata
);
    localparam [31:0] HALT_WORD = 32'h0000_0073;

    reg [31:0] r_mem [0:255];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            r_mem[i] = HALT_WORD;
        end
    end

    always @(posedge i_clock) begin
        if (i_we) begin
            r_mem[i_waddr] <= i_wdata;
        end
    end

    assign o_rdata = r_mem[i_raddr];
endmodule

`default_nettype wire

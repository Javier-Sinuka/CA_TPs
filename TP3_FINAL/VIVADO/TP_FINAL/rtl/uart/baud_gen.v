`timescale 1ns/1ps
`default_nettype none

module baud_gen #(
    parameter integer CLOCK_FREQ = 50_000_000,
    parameter integer BAUD_RATE  = 115_200
)(
    input  wire i_reset,
    input  wire i_clock,
    output reg  o_baud_tick
);
    // uart_rx y uart_tx cuentan 16 ticks por bit: no cambiar sin cambiarlos a ellos.
    localparam integer OVERSAMPLE = 16;
    // Divisor redondeado al entero más cercano (D-06).
    localparam integer DIV        = (CLOCK_FREQ + (BAUD_RATE * OVERSAMPLE) / 2) / (BAUD_RATE * OVERSAMPLE);
    localparam integer CNTR_MAX   = DIV - 1;
    localparam integer CNTR_WIDTH = (DIV < 2) ? 1 : $clog2(DIV);

    // Un divisor menor a 2 no da un tick de un ciclo separado de otro: se rechaza en elaboración
    // instanciando un módulo que no existe (falla igual en Icarus y en Vivado).
    generate
        if (DIV < 2) begin : g_div_check
            BAUD_GEN_ERROR_DIVISOR_MENOR_A_2 u_error ();
        end
    endgenerate

    reg [CNTR_WIDTH-1:0] r_counter;

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_counter <= {CNTR_WIDTH{1'b0}};
        end else if (r_counter == CNTR_MAX[CNTR_WIDTH-1:0]) begin
            r_counter <= {CNTR_WIDTH{1'b0}};
        end else begin
            r_counter <= r_counter + 1'b1;
        end
    end

    // El tick sale registrado: aparece 1 ciclo después de r_counter == CNTR_MAX.
    // Primer tick: en el flanco número DIV después de soltar el reset.
    always @(posedge i_clock) begin
        if (i_reset) begin
            o_baud_tick <= 1'b0;
        end else begin
            o_baud_tick <= (r_counter == CNTR_MAX[CNTR_WIDTH-1:0]);
        end
    end
endmodule

`default_nettype wire

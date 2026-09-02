`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/01/2026 11:05:23 AM
// Design Name: 
// Module Name: tb_ALU
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module Test_Bench_ALU();

// Parámetros
    parameter NB_OP = 6;
    parameter NB_DATA = 8;

    // Entradas (simuladas) 
    reg signed [NB_DATA-1:0] i_data_a;
    reg signed [NB_DATA-1:0] i_data_b;
    reg  [NB_OP-1:0] i_op;

    // Salida
    wire signed [NB_DATA-1:0] o_data;

    // Instanciamos el módulo ALU
    ALU #(.NB_OP(NB_OP), .NB_DATA(NB_DATA)) uut (
        .i_data_a(i_data_a),
        .i_data_b(i_data_b),
        .i_op(i_op),
        .o_data(o_data)
    );

    
    initial begin
        // Iniciamos la simulación
        $display("Iniciando Testbench de ALU...");
        for(integer i = 0;i < 8; i = i + 1 )
        begin
        // Test 1: Suma 
        i_data_a = {NB_DATA{1'b0}}; 
        i_data_b = {NB_DATA{1'b0}}; 
        i_data_a = $random % 6; // Números entre 0 y 5
        i_data_b = $random % 6; // Números entre 0 y 5

        i_op = 6'b100000;   // Suma 
        #10;
        $display("Suma: %d + %d = %d", i_data_a, i_data_b, o_data);

        // Test 2: Resta
        i_op = 6'b100010;   // Operación de resta
        #10;
        $display("Resta: %d - %d = %d", i_data_a, i_data_b, o_data);

        // Test 3: AND lógico
        i_op = 6'b100100;   // Operación AND
        #10;
        $display("AND: %b & %b = %b", i_data_a, i_data_b, o_data);

        // Test 4: OR lógico
        i_op = 6'b100101;   // Operación OR
        #10;
        $display("OR: %b | %b = %b", i_data_a, i_data_b, o_data);

        // Test 5: XOR lógico
        i_op = 6'b100110;   // Operación XOR
        #10;
        $display("XOR: %b ^ %b = %b", i_data_a, i_data_b, o_data);

        // Test 6: Shift aritmético a la derecha
        i_op = 6'b000011;   // Operación shift aritmético a la derecha
        #10;
        $display("Shift Aritmético Derecha: %b >>> %d = %b", i_data_a, i_data_b, o_data);

        // Test 7: Shift lógico a la derecha
        i_op = 6'b000010;   // Operación shift lógico a la derecha
        #10;
        $display("Shift Lógico Derecha: %b >> %d = %b", i_data_a, i_data_b, o_data);

        // Test 8: NOR lógico
        i_op = 6'b100111;   // Operación NOR
        #10;
        $display("NOR: ~(%b | %b) = %b", i_data_a, i_data_b, o_data);

        
    end
end

endmodule

// ALU combinacional parametrizable.
// No contiene registros ni señales de reloj.
module ALU #(
    parameter NB_OP = 6,
    parameter NB_DATA = 8
)(
    input wire signed [NB_DATA-1:0] i_data_a,
	input wire signed [NB_DATA-1:0] i_data_b,
	input wire[NB_OP-1:0] i_op,
	output reg signed [NB_DATA-1:0] o_data
);


    // Codigos de operacion definidos en la consigna.
    localparam [5:0] OP_ADD = 6'b100000;
    localparam [5:0] OP_SUB = 6'b100010;
    localparam [5:0] OP_AND = 6'b100100;
    localparam [5:0] OP_OR  = 6'b100101;
    localparam [5:0] OP_XOR = 6'b100110;
    localparam [5:0] OP_SRA = 6'b000011;
    localparam [5:0] OP_SRL = 6'b000010;
    localparam [5:0] OP_NOR = 6'b100111;

    // Logica puramente combinacional.
    // El valor por defecto define una salida conocida para codigos no validos
    // y evita inferir latches al completar las operaciones en los siguientes pasos.
    always @(*) begin
        o_data = {NB_DATA{1'b0}};

        case (i_op)
            OP_ADD: o_data = i_data_a + i_data_b;
            OP_SUB: o_data = i_data_a - i_data_b;
            OP_AND: o_data = i_data_a & i_data_b;
            OP_OR:  o_data = i_data_a | i_data_b;
            OP_XOR: o_data = i_data_a ^ i_data_b;
            OP_NOR: o_data = ~(i_data_a | i_data_b);
            OP_SRL: o_data = i_data_a >> i_data_b;
            OP_SRA: o_data = $signed(i_data_a) >>> i_data_b;
            default: o_data = {NB_DATA{1'b0}};
        endcase
    end

endmodule

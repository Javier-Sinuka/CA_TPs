// ALU combinacional parametrizable.
// No contiene registros ni señales de reloj.
module ALU #(
    parameter DATA_WIDTH = 8
) (
    input  wire [DATA_WIDTH-1:0] A,
    input  wire [DATA_WIDTH-1:0] B,
    input  wire [5:0]            Op,
    output reg  [DATA_WIDTH-1:0] Result
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
        Result = {DATA_WIDTH{1'b0}};

        case (Op)
            OP_ADD: Result = A + B;
            OP_SUB: Result = A - B;
            OP_AND: Result = A & B;
            OP_OR:  Result = A | B;
            OP_XOR: Result = A ^ B;
            OP_NOR: Result = ~(A | B);
            OP_SRL: Result = A >> B;
            OP_SRA: Result = $signed(A) >>> B;
            default: Result = {DATA_WIDTH{1'b0}};
        endcase
    end

endmodule

module ALU #(
    parameter OP_WIDTH   = 6,
    parameter DATA_WIDTH = 8
) (
    input  wire signed [DATA_WIDTH-1:0] i_operand_a,
    input  wire signed [DATA_WIDTH-1:0] i_operand_b,
    input  wire        [OP_WIDTH-1:0]   i_op,
    output reg  signed [DATA_WIDTH-1:0] o_result
);

    // Operation codes
    localparam [5:0] OP_ADD = 6'b100000;
    localparam [5:0] OP_SUB = 6'b100010;
    localparam [5:0] OP_AND = 6'b100100;
    localparam [5:0] OP_OR  = 6'b100101;
    localparam [5:0] OP_XOR = 6'b100110;
    localparam [5:0] OP_SRA = 6'b000011;
    localparam [5:0] OP_SRL = 6'b000010;
    localparam [5:0] OP_NOR = 6'b100111;

    // Only the lower bits of the shift amount are used
    localparam SHIFT_WIDTH = $clog2(DATA_WIDTH);

    // Combinational logic for the ALU operations
    always @(*) begin
        o_result = {DATA_WIDTH{1'b0}};

        case (i_op)
            OP_ADD: o_result = i_operand_a + i_operand_b;
            OP_SUB: o_result = i_operand_a - i_operand_b;
            OP_AND: o_result = i_operand_a & i_operand_b;
            OP_OR:  o_result = i_operand_a | i_operand_b;
            OP_XOR: o_result = i_operand_a ^ i_operand_b;
            OP_NOR: o_result = ~(i_operand_a | i_operand_b);
            OP_SRL: o_result = i_operand_a >>  i_operand_b[SHIFT_WIDTH-1:0];
            OP_SRA: o_result = i_operand_a >>> i_operand_b[SHIFT_WIDTH-1:0];
        endcase
    end

endmodule

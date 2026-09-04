module ALU_top #(
    parameter DATA_WIDTH = 8,
    parameter OP_WIDTH   = 6
) (
    input  wire                    i_load_a,
    input  wire                    i_load_b,
    input  wire                    i_load_op,
    input  wire                    i_clock,
    input  wire                    i_reset,
    input  wire [DATA_WIDTH-1:0]   i_bus,

    output wire [DATA_WIDTH-1:0]   o_leds,
    output wire                    o_reset_led
);

    reg [DATA_WIDTH-1:0] r_operand_a;
    reg [DATA_WIDTH-1:0] r_operand_b;
    reg [OP_WIDTH-1:0]   r_op;

    ALU #(
        .OP_WIDTH  (OP_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) alu (
        .i_operand_a(r_operand_a),
        .i_operand_b(r_operand_b),
        .i_op       (r_op),
        .o_result   (o_leds)
    );

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_operand_a <= {DATA_WIDTH{1'b0}};
            r_operand_b <= {DATA_WIDTH{1'b0}};
            r_op        <= {OP_WIDTH{1'b0}};
        end
        else if (i_load_a)
            r_operand_a <= i_bus[DATA_WIDTH-1:0];
        else if (i_load_b)
            r_operand_b <= i_bus[DATA_WIDTH-1:0];
        else if (i_load_op)
            r_op <= i_bus[OP_WIDTH-1:0];
    end

    assign o_reset_led = i_reset;

endmodule

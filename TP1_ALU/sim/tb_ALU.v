module tb_ALU();

    // Parameters
    parameter OP_WIDTH   = 6;
    parameter DATA_WIDTH = 8;

    // Operation codes
    localparam [5:0] OP_ADD = 6'b100000;
    localparam [5:0] OP_SUB = 6'b100010;
    localparam [5:0] OP_AND = 6'b100100;
    localparam [5:0] OP_OR  = 6'b100101;
    localparam [5:0] OP_XOR = 6'b100110;
    localparam [5:0] OP_SRA = 6'b000011;
    localparam [5:0] OP_SRL = 6'b000010;
    localparam [5:0] OP_NOR = 6'b100111;

    localparam integer OP_NAME_WIDTH = 8 * 4;
    localparam integer NUM_TESTS     = 50;

    // Only the lower bits are used for shift amount
    localparam SHIFT_WIDTH = $clog2(DATA_WIDTH);

    // DUT inputs
    reg signed [DATA_WIDTH-1:0] i_operand_a;
    reg signed [DATA_WIDTH-1:0] i_operand_b;
    reg        [OP_WIDTH-1:0]   i_op;

    // DUT output
    wire signed [DATA_WIDTH-1:0] o_result;

    // Expected result and counters for automatic checking
    reg signed [DATA_WIDTH-1:0] expected_result;
    integer pass_count;
    integer fail_count;
    integer i;

    // ALU DUT
    ALU #(
        .OP_WIDTH  (OP_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .i_operand_a(i_operand_a),
        .i_operand_b(i_operand_b),
        .i_op       (i_op),
        .o_result   (o_result)
    );

    task automatic check_result;
        input [OP_WIDTH-1:0] op;
        input [OP_NAME_WIDTH-1:0] op_name;
        begin
            i_op = op;
            #10;

            case (op)
                OP_ADD: expected_result = i_operand_a + i_operand_b;
                OP_SUB: expected_result = i_operand_a - i_operand_b;
                OP_AND: expected_result = i_operand_a & i_operand_b;
                OP_OR:  expected_result = i_operand_a | i_operand_b;
                OP_XOR: expected_result = i_operand_a ^ i_operand_b;
                OP_NOR: expected_result = ~(i_operand_a | i_operand_b);
                OP_SRL: expected_result = i_operand_a >>  i_operand_b[SHIFT_WIDTH-1:0];
                OP_SRA: expected_result = i_operand_a >>> i_operand_b[SHIFT_WIDTH-1:0];
                default: expected_result = {DATA_WIDTH{1'b0}};
            endcase

            if (o_result === expected_result) begin
                pass_count = pass_count + 1;
                $display("PASS %-4s | A=%0d B=%0d OP=%b RESULT=%0d",
                         op_name, i_operand_a, i_operand_b, i_op, o_result);
            end
            else begin
                fail_count = fail_count + 1;
                $display("FAIL %-4s | A=%0d B=%0d OP=%b EXPECTED=%0d GOT=%0d",
                         op_name, i_operand_a, i_operand_b, i_op,
                         expected_result, o_result);
            end
        end
    endtask

    initial begin
        pass_count  = 0;
        fail_count  = 0;
        i_operand_a = {DATA_WIDTH{1'b0}};
        i_operand_b = {DATA_WIDTH{1'b0}};
        i_op        = {OP_WIDTH{1'b0}};

        $display("Starting ALU testbench...");

        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            i_operand_a = $random;
            i_operand_b = $random;

            check_result(OP_ADD, "ADD");
            check_result(OP_SUB, "SUB");
            check_result(OP_AND, "AND");
            check_result(OP_OR,  "OR");
            check_result(OP_XOR, "XOR");
            check_result(OP_SRA, "SRA");
            check_result(OP_SRL, "SRL");
            check_result(OP_NOR, "NOR");
        end

        $display("----------------------------------------------");
        $display("Test summary: PASS=%0d FAIL=%0d TOTAL=%0d",
                 pass_count, fail_count, pass_count + fail_count);

        if (fail_count == 0)
            $display("All tests PASSED.");
        else
            $display("Some tests FAILED.");

        $finish;
    end

endmodule

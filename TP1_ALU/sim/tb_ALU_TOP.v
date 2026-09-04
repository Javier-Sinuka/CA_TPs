module tb_ALU_top;

    // Parameters
    parameter DATA_WIDTH = 8;
    parameter OP_WIDTH   = 6;

    // Operation codes
    localparam [5:0] OP_ADD = 6'b100000;
    localparam [5:0] OP_SUB = 6'b100010;
    localparam [5:0] OP_AND = 6'b100100;
    localparam [5:0] OP_OR  = 6'b100101;
    localparam [5:0] OP_XOR = 6'b100110;
    localparam [5:0] OP_SRA = 6'b000011;
    localparam [5:0] OP_SRL = 6'b000010;
    localparam [5:0] OP_NOR = 6'b100111;

    localparam integer SHIFT_WIDTH   = $clog2(DATA_WIDTH);
    localparam integer OP_NAME_WIDTH = 8 * 4;
    localparam integer NUM_TESTS     = 50;

    // DUT inputs
    reg                    i_load_a;
    reg                    i_load_b;
    reg                    i_load_op;
    reg                    i_clock;
    reg                    i_reset;
    reg [DATA_WIDTH-1:0]   i_bus;

    // DUT outputs
    wire [DATA_WIDTH-1:0]  o_leds;
    wire                   o_reset_led;

    // Checker data
    reg signed [DATA_WIDTH-1:0] tb_operand_a;
    reg signed [DATA_WIDTH-1:0] tb_operand_b;
    reg        [OP_WIDTH-1:0]   tb_op;
    reg signed [DATA_WIDTH-1:0] expected_result;
    integer pass_count;
    integer fail_count;
    integer i;

    // Instantiate DUT
    ALU_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .OP_WIDTH  (OP_WIDTH)
    ) dut (
        .i_load_a   (i_load_a),
        .i_load_b   (i_load_b),
        .i_load_op  (i_load_op),
        .i_clock    (i_clock),
        .i_reset    (i_reset),
        .i_bus      (i_bus),
        .o_leds     (o_leds),
        .o_reset_led(o_reset_led)
    );

    // 10 ns clock
    always #5 i_clock = ~i_clock;

    task automatic pulse_load_a;
        input [DATA_WIDTH-1:0] value;
        begin
            tb_operand_a = value;
            i_bus = value;
            i_load_a = 1'b1;
            @(posedge i_clock);
            #1 i_load_a = 1'b0;
        end
    endtask

    task automatic pulse_load_b;
        input [DATA_WIDTH-1:0] value;
        begin
            tb_operand_b = value;
            i_bus = value;
            i_load_b = 1'b1;
            @(posedge i_clock);
            #1 i_load_b = 1'b0;
        end
    endtask

    task automatic pulse_load_op;
        input [OP_WIDTH-1:0] value;
        begin
            tb_op = value;
            i_bus = {{(DATA_WIDTH-OP_WIDTH){1'b0}}, value};
            i_load_op = 1'b1;
            @(posedge i_clock);
            #1 i_load_op = 1'b0;
        end
    endtask

    task automatic check_result;
        input [OP_WIDTH-1:0] op;
        input [OP_NAME_WIDTH-1:0] op_name;
        begin
            pulse_load_op(op);
            #1;

            case (op)
                OP_ADD: expected_result = tb_operand_a + tb_operand_b;
                OP_SUB: expected_result = tb_operand_a - tb_operand_b;
                OP_AND: expected_result = tb_operand_a & tb_operand_b;
                OP_OR:  expected_result = tb_operand_a | tb_operand_b;
                OP_XOR: expected_result = tb_operand_a ^ tb_operand_b;
                OP_NOR: expected_result = ~(tb_operand_a | tb_operand_b);
                OP_SRL: expected_result = tb_operand_a >>  tb_operand_b[SHIFT_WIDTH-1:0];
                OP_SRA: expected_result = tb_operand_a >>> tb_operand_b[SHIFT_WIDTH-1:0];
                default: expected_result = {DATA_WIDTH{1'b0}};
            endcase

            if ($signed(o_leds) === expected_result) begin
                pass_count = pass_count + 1;
                $display("PASS %-4s | A=%0d B=%0d RESULT=%0d",
                         op_name, tb_operand_a, tb_operand_b, $signed(o_leds));
            end
            else begin
                fail_count = fail_count + 1;
                $display("FAIL %-4s | A=%0d B=%0d EXPECTED=%0d GOT=%0d",
                         op_name, tb_operand_a, tb_operand_b,
                         expected_result, $signed(o_leds));
            end
        end
    endtask

    initial begin
        // Initialize inputs
        i_load_a  = 1'b0;
        i_load_b  = 1'b0;
        i_load_op = 1'b0;
        i_clock   = 1'b0;
        i_reset   = 1'b0;
        i_bus     = {DATA_WIDTH{1'b0}};
        tb_operand_a = {DATA_WIDTH{1'b0}};
        tb_operand_b = {DATA_WIDTH{1'b0}};
        tb_op        = {OP_WIDTH{1'b0}};
        pass_count   = 0;
        fail_count   = 0;

        $display("Starting ALU_top testbench...");
        $monitor("T=%0t | A=%0d B=%0d OP=%b LED=%0d RESET_LED=%b",
                 $time, tb_operand_a, tb_operand_b, tb_op,
                 $signed(o_leds), o_reset_led);

        // Apply reset
        i_reset = 1'b1;
        @(posedge i_clock);
        #1 i_reset = 1'b0;
        tb_operand_a = {DATA_WIDTH{1'b0}};
        tb_operand_b = {DATA_WIDTH{1'b0}};
        tb_op        = {OP_WIDTH{1'b0}};

        // Randomized tests with full DATA_WIDTH range
        for (i = 0; i < NUM_TESTS; i = i + 1) begin
            pulse_load_a($random);
            pulse_load_b($random);

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

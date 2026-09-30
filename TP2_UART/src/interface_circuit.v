module interface_circuit (
    input wire i_clock,
    input wire i_reset,
    input wire i_rx_valid,
    input wire [7:0] i_rx_data,
    input wire i_rx_error,
    input wire i_tx_busy,
    output wire o_tx_start,
    output wire [7:0] o_tx_data,
    output wire o_error
);
    reg [1:0] r_state;
    reg [1:0] r_next_state;
    reg signed [7:0] r_operand_a;
    reg signed [7:0] r_operand_b;
    reg [5:0] r_op;

    wire [7:0] w_r_data;
    wire w_rx_empty;
    wire w_rx_error;
    wire w_rd;
    wire w_wr;
    wire w_tx_full;
    wire signed [7:0] w_result;

    localparam READ_A = 2'd0;
    localparam READ_B = 2'd1;
    localparam READ_OP = 2'd2;
    localparam WRITE_RESULT = 2'd3;

    // Binary command: operand A, operand B, opcode. Response: one result byte.
    assign w_rd = !i_reset && !w_rx_error && !w_rx_empty &&
                  ((r_state == READ_A) || (r_state == READ_B) ||
                   (r_state == READ_OP));
    assign w_wr = !i_reset && !w_rx_error && !w_tx_full &&
                  (r_state == WRITE_RESULT);
    assign o_error = w_rx_error;

    interface_rx u_interface_rx (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_valid(i_rx_valid),
        .i_data(i_rx_data),
        .i_error(i_rx_error),
        .i_rd(w_rd),
        .o_r_data(w_r_data),
        .o_rx_empty(w_rx_empty),
        .o_error(w_rx_error)
    );

    ALU #(
        .OP_WIDTH(6),
        .DATA_WIDTH(8)
    ) u_alu (
        .i_operand_a(r_operand_a),
        .i_operand_b(r_operand_b),
        .i_op(r_op),
        .o_result(w_result)
    );

    interface_tx u_interface_tx (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_wr(w_wr),
        .i_w_data(w_result),
        .i_busy(i_tx_busy),
        .o_tx_full(w_tx_full),
        .o_start(o_tx_start),
        .o_data(o_tx_data)
    );

    always @(*) begin
        r_next_state = r_state;
        case (r_state)
            READ_A: begin
                if (w_rd) begin
                    r_next_state = READ_B;
                end
            end
            READ_B: begin
                if (w_rd) begin
                    r_next_state = READ_OP;
                end
            end
            READ_OP: begin
                if (w_rd) begin
                    r_next_state = WRITE_RESULT;
                end
            end
            WRITE_RESULT: begin
                // The ALU has a full clock cycle to settle after loading r_op.
                // Keep its inputs unchanged until the TX buffer accepts the result.
                if (w_wr) begin
                    r_next_state = READ_A;
                end
            end
            default: begin
                r_next_state = READ_A;
            end
        endcase
    end

    // State register.
    always @(posedge i_clock) begin
        if (i_reset || w_rx_error) begin
            r_state <= READ_A;
        end else begin
            r_state <= r_next_state;
        end
    end

    // Operand A register.
    always @(posedge i_clock) begin
        if (i_reset || w_rx_error) begin
            r_operand_a <= 8'b0;
        end else if (w_rd && r_state == READ_A) begin
            r_operand_a <= w_r_data;
        end
    end

    // Operand B register.
    always @(posedge i_clock) begin
        if (i_reset || w_rx_error) begin
            r_operand_b <= 8'b0;
        end else if (w_rd && r_state == READ_B) begin
            r_operand_b <= w_r_data;
        end
    end

    // Operation register.
    always @(posedge i_clock) begin
        if (i_reset || w_rx_error) begin
            r_op <= 6'b0;
        end else if (w_rd && r_state == READ_OP) begin
            r_op <= w_r_data[5:0];
        end
    end
endmodule

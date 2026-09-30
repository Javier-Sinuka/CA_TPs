module interface_tx (
    input wire i_clock,
    input wire i_reset,
    input wire i_wr,
    input wire [7:0] i_w_data,
    input wire i_busy,
    output wire o_tx_full,
    output wire o_start,
    output reg [7:0] o_data
);
    reg [1:0] r_state;
    reg [1:0] r_next_state;

    localparam IDLE = 2'd0;
    localparam WAIT_TX = 2'd1;
    localparam WAIT_BUSY = 2'd2;
    localparam WAIT_DONE = 2'd3;

    // Reserve the buffer until uart_tx acknowledges and finishes the frame.
    assign o_tx_full = i_reset || (r_state != IDLE);
    assign o_start = !i_reset && (r_state == WAIT_TX) && !i_busy;

    always @(*) begin
        r_next_state = r_state;
        case (r_state)
            IDLE: begin
                if (i_wr) begin
                    r_next_state = WAIT_TX;
                end
            end
            WAIT_TX: begin
                if (!i_busy) begin
                    r_next_state = WAIT_BUSY;
                end
            end
            WAIT_BUSY: begin
                // Waiting for busy to rise prevents duplicate start pulses.
                if (i_busy) begin
                    r_next_state = WAIT_DONE;
                end
            end
            WAIT_DONE: begin
                if (!i_busy) begin
                    r_next_state = IDLE;
                end
            end
            default: begin
                r_next_state = IDLE;
            end
        endcase
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_state <= IDLE;
        end else begin
            r_state <= r_next_state;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            o_data <= 8'b0;
        end else if (r_state == IDLE && i_wr) begin
            // Keep the result stable while waiting for TX and throughout sending.
            o_data <= i_w_data;
        end
    end
endmodule

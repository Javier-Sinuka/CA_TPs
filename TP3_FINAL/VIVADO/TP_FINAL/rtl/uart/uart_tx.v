module uart_tx (
    input wire i_clock,
    input wire i_baud_tick,
    input wire i_reset,
    input wire i_start,
    input wire [7:0] i_data,
    output reg o_busy,
    output reg o_tx
);
    reg [1:0] r_state;
    reg [1:0] r_next_state;
    reg [3:0] r_tick_counter;
    reg [2:0] r_bit_counter;
    reg [7:0] r_shift;

    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    // IDLE -> START: i_start == 1
    // START -> DATA : i_baud_tick == 1 && r_tick_counter == 15
    // DATA -> STOP  : i_baud_tick == 1 && r_tick_counter == 15 && r_bit_counter == 7
    // STOP -> IDLE  : i_baud_tick == 1 && r_tick_counter == 15

    always @(*) begin
        r_next_state = r_state;
        case (r_state)
            IDLE: begin
                if (i_start) begin
                    r_next_state = START;
                end
            end
            START: begin
                if (i_baud_tick && r_tick_counter == 15) begin
                    r_next_state = DATA;
                end
            end
            DATA: begin
                if (i_baud_tick && r_tick_counter == 15 && r_bit_counter == 7) begin
                    r_next_state = STOP;
                end
            end
            STOP: begin
                if (i_baud_tick && r_tick_counter == 15) begin
                    r_next_state = IDLE;
                end
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
            o_tx <= 1'b1;
        end else begin
            case (r_next_state)
                IDLE: begin o_tx <= 1'b1; end
                START: begin o_tx <= 1'b0; end
                DATA: begin o_tx <= r_shift[0]; end
                STOP: begin o_tx <= 1'b1; end
            endcase
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            o_busy <= 1'b0;
        end else begin
            o_busy <= (r_next_state != IDLE);
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_shift <= 8'b0;
        end else if (r_state == IDLE && i_start) begin
            r_shift <= i_data;
        end else if (r_state == DATA && i_baud_tick && r_tick_counter == 15) begin
            r_shift <= r_shift >> 1;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_tick_counter <= 4'b0;
        end else if (r_next_state == IDLE || (i_baud_tick && r_tick_counter == 15)) begin
            r_tick_counter <= 4'b0;
        end else if (i_baud_tick) begin
            r_tick_counter <= r_tick_counter + 1'b1;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_bit_counter <= 3'b0;
        end else if (i_baud_tick && r_tick_counter == 15 && r_bit_counter == 7) begin
            r_bit_counter <= 3'b0;
        end else if (i_baud_tick && r_tick_counter == 15 && r_state == DATA) begin
            r_bit_counter <= r_bit_counter + 1'b1;
        end
    end
endmodule

module uart_rx (
    input wire i_clock,
    input wire i_baud_tick,
    input wire i_reset,
    input wire i_rx,
    output reg o_valid,
    output reg [7:0] o_data,
    output reg o_error
);
    reg [1:0] r_state;
    reg [1:0] r_next_state;
    reg [3:0] r_tick_counter;
    reg [2:0] r_bit_counter;
    reg [7:0] r_shift;

    reg [1:0] r_rx_sync;
    wire w_rx = r_rx_sync[1];

    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;
    localparam SAMPLE = 4'd7;

    // IDLE -> START: w_rx == 0
    // START -> IDLE : i_baud_tick && r_tick_counter == SAMPLE && w_rx == 1
    // START -> DATA : i_baud_tick && r_tick_counter == 15
    // DATA -> STOP  : i_baud_tick && r_tick_counter == 15 && r_bit_counter == 7
    // STOP -> IDLE  : i_baud_tick && r_tick_counter == 15

    always @(*) begin
        r_next_state = r_state;
        case (r_state)
            IDLE: begin
                if (w_rx == 1'b0) begin
                    r_next_state = START;
                end
            end
            START: begin
                if (i_baud_tick && r_tick_counter == SAMPLE && w_rx == 1'b1) begin
                    r_next_state = IDLE;
                end else if (i_baud_tick && r_tick_counter == 15) begin
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
            r_rx_sync <= 2'b11;
        end else begin
            r_rx_sync <= {r_rx_sync[0], i_rx};
        end
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

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_shift <= 8'b0;
        end else if (r_state == DATA && i_baud_tick && r_tick_counter == SAMPLE) begin
            r_shift <= {w_rx, r_shift[7:1]};
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            o_data <= 8'b0;
        end else if (r_state == STOP && i_baud_tick && r_tick_counter == 15) begin
            o_data <= r_shift;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            o_valid <= 1'b0;
        end else begin
            o_valid <= (r_state == STOP && i_baud_tick && r_tick_counter == 15);
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            o_error <= 1'b0;
        end else begin
            o_error <= (r_state == STOP && i_baud_tick && r_tick_counter == 15 && w_rx == 1'b0);
        end
    end
endmodule

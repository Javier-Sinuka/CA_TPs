`timescale 1ns/1ps
`default_nettype none

module uart_rx (
    input  wire       i_clock,
    input  wire       i_baud_tick,
    input  wire       i_reset,
    input  wire       i_rx,
    output reg        o_valid,
    output reg  [7:0] o_data,
    output reg        o_error
);
    reg [2:0] r_state;
    reg [2:0] r_next_state;
    reg [3:0] r_tick_counter;
    reg [2:0] r_bit_counter;
    reg [7:0] r_shift;

    // Sincronizador de la entrada asíncrona: 2 FF juntos en el mismo slice.
    (* ASYNC_REG = "TRUE" *) reg [1:0] r_rx_sync;
    wire w_rx = r_rx_sync[1];

    localparam IDLE      = 3'd0;
    localparam START     = 3'd1;
    localparam DATA      = 3'd2;
    localparam STOP      = 3'd3;
    localparam WAIT_IDLE = 3'd4;
    localparam SAMPLE    = 4'd7;

    // El conteo de ticks arranca en el flanco de start, así que el tick SAMPLE de cada bit cae en su centro.
    // El stop se evalúa en su centro (≈ 9,5 bits del flanco), no en su final: con tramas seguidas, el
    // final del stop es el borde del start siguiente (H-1, D-07).
    // IDLE      -> START     : w_rx == 0
    // START     -> IDLE      : tick SAMPLE con w_rx == 1 (inicio falso)
    // START     -> DATA      : tick 15
    // DATA      -> STOP      : tick 15 del bit 7
    // STOP      -> IDLE      : tick SAMPLE con w_rx == 1 (byte bueno: o_valid)
    // STOP      -> WAIT_IDLE : tick SAMPLE con w_rx == 0 (framing: o_error, sin o_valid, D-08)
    // WAIT_IDLE -> IDLE      : w_rx == 1 (no tomar el resto de un stop en 0 como un start nuevo)

    wire w_stop_sample = (r_state == STOP) && i_baud_tick && (r_tick_counter == SAMPLE);

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
                if (w_stop_sample) begin
                    r_next_state = w_rx ? IDLE : WAIT_IDLE;
                end
            end
            WAIT_IDLE: begin
                if (w_rx == 1'b1) begin
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
        end else if (r_next_state == IDLE || r_next_state == WAIT_IDLE
                     || (i_baud_tick && r_tick_counter == 15)) begin
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
        end else if (w_stop_sample) begin
            o_data <= r_shift;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            o_valid <= 1'b0;
        end else begin
            o_valid <= w_stop_sample && (w_rx == 1'b1);
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            o_error <= 1'b0;
        end else begin
            o_error <= w_stop_sample && (w_rx == 1'b0);
        end
    end
endmodule

`default_nettype wire

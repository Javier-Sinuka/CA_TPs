module interface_rx (
    input wire i_clock,
    input wire i_reset,
    input wire i_valid,
    input wire [7:0] i_data,
    input wire i_error,
    input wire i_rd,
    output reg [7:0] o_r_data,
    output reg o_rx_empty,
    output reg o_error
);
    wire w_accept;
    wire w_overflow;

    assign w_accept = i_valid && !i_error && (o_rx_empty || i_rd);
    assign w_overflow = i_valid && !i_error && !o_rx_empty && !i_rd;

    // One-byte receive buffer. The consumer reads the current byte when
    // i_rd && !o_rx_empty at a rising clock edge.

    // Received data register.
    always @(posedge i_clock) begin
        if (i_reset) begin
            o_r_data <= 8'b0;
        end else if (w_accept) begin
            // A simultaneous read consumes the old byte and stores the new one.
            o_r_data <= i_data;
        end
    end

    // Empty status register.
    always @(posedge i_clock) begin
        if (i_reset) begin
            o_rx_empty <= 1'b1;
        end else if ((i_valid && i_error) || w_overflow) begin
            // Discard a byte with framing error and flush after an overflow.
            o_rx_empty <= 1'b1;
        end else if (w_accept) begin
            o_rx_empty <= 1'b0;
        end else if (i_rd) begin
            o_rx_empty <= 1'b1;
        end
    end

    // Error pulse register.
    always @(posedge i_clock) begin
        if (i_reset) begin
            o_error <= 1'b0;
        end else begin
            o_error <= (i_valid && i_error) || w_overflow;
        end
    end
endmodule

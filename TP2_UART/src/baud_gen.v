module baud_gen #(
    parameter CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 9600,
    parameter OVERSAMPLE = 16
)(
    input wire i_reset,
    input wire i_clock,
    output reg o_baud_tick
);
    localparam CNTR_MAX = CLOCK_FREQ / (BAUD_RATE * OVERSAMPLE) - 1;
    localparam CNTR_WIDTH = $clog2(CNTR_MAX + 1);

    reg [CNTR_WIDTH-1:0] r_counter;

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_counter <= 0;
        end else begin
            if (r_counter == CNTR_MAX) begin
                r_counter <= 0;
            end else begin
                r_counter <= r_counter + 1;
            end
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            o_baud_tick <= 0;
        end else begin
            if (r_counter == CNTR_MAX) begin
                o_baud_tick <= 1;
            end else begin
                o_baud_tick <= 0;
            end
        end
    end
endmodule

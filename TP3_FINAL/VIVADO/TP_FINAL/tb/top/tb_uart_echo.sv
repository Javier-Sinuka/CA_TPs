`timescale 1ns/1ps

// Reemplazo del Clock Wizard solo para simulación: reloj directo y locked en 1.
module clk_wiz_0 (
    input  wire clk_in1,
    output wire clk_out1,
    output wire locked
);
    assign clk_out1 = clk_in1;
    assign locked   = 1'b1;
endmodule

// 64 bytes seguidos por RX deben volver iguales por TX, sin overrun ni framing.
module tb_uart_echo;
    localparam integer CLOCK_FREQ = 100_000_000;
    localparam integer BAUD_RATE  = 3_125_000;   // CLOCK_FREQ / 32: DIV = 2
    localparam real    BIT_NS     = 1.0e9 / BAUD_RATE;
    localparam integer N          = 64;

    reg        r_clk = 1'b0;
    reg        r_btn = 1'b0;
    wire [3:0] w_led;
    reg  bfm_rx = 1'b1;
    wire bfm_tx;
`include "uart_bfm.svh"

    always #5 r_clk = ~r_clk;

    top_uart_echo #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_dut (
        .i_clk100(r_clk),
        .i_btn_reset(r_btn),
        .i_rx(bfm_rx),
        .o_tx(bfm_tx),
        .o_led(w_led)
    );

    integer errors = 0;
    integer checks = 0;
    integer ks, kr;
    reg [7:0] got;
    reg       ok;

    function automatic [7:0] pat(input integer m);
        pat = (m * 73 + 11) % 256;
    endfunction

    initial begin
        #(40.0 * N * BIT_NS);
        $fatal(1, "FAIL tb_uart_echo: watchdog");
    end

    initial begin
        bfm_bit_ns     = BIT_NS;
        bfm_timeout_ns = 30.0 * BIT_NS;
        repeat (20) @(negedge r_clk);
        fork
            for (ks = 0; ks < N; ks = ks + 1) bfm_send_byte(pat(ks));
            for (kr = 0; kr < N; kr = kr + 1) begin
                bfm_recv_byte(got, ok);
                checks = checks + 1;
                if (!ok || got !== pat(kr)) begin
                    errors = errors + 1;
                    $display("FAIL eco %0d: esperado %02h, recibido %02h ok=%0d", kr, pat(kr), got, ok);
                end
            end
        join
        @(negedge r_clk);
        checks = checks + 1;
        if (w_led !== 4'b1000) begin   // locked, sin overrun, sin framing, 64 bytes => toggle en 0
            errors = errors + 1;
            $display("FAIL LEDs: %b, esperado 1000", w_led);
        end
        if (errors != 0) $fatal(1, "FAIL tb_uart_echo: %0d errores", errors);
        $display("PASS tb_uart_echo: %0d chequeos", checks);
        $finish;
    end
endmodule

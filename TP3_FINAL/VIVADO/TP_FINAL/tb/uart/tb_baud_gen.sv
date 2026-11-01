`timescale 1ns/1ps

// Mide el período del tick de baud_gen para varias frecuencias de reloj.
// Cada instancia de baud_check tiene su propio reloj y su propio DUT.
module baud_check #(
    parameter integer CLOCK_FREQ = 50_000_000,
    parameter integer BAUD_RATE  = 115_200,
    parameter integer EXP_DIV    = 27,
    parameter integer N_PERIODS  = 20
)();
    localparam real HALF_NS = 1.0e9 / CLOCK_FREQ / 2.0;
    reg  r_clock = 1'b0;
    reg  r_reset = 1'b1;
    wire w_tick;
    integer errors = 0;
    integer checks = 0;
    reg     done = 1'b0;
    integer cycle, last, periods, first;
    real    err_pct;

    always #(HALF_NS) r_clock = ~r_clock;

    baud_gen #(.CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(BAUD_RATE)) u_dut (
        .i_reset(r_reset), .i_clock(r_clock), .o_baud_tick(w_tick));

    initial begin
        cycle = 0; last = -1; periods = 0; first = -1;
        repeat (4) @(posedge r_clock);
        @(negedge r_clock);
        r_reset = 1'b0;
        // cycle = cantidad de flancos de subida desde que se soltó el reset.
        while (periods < N_PERIODS) begin
            @(posedge r_clock);
            cycle = cycle + 1;
            @(negedge r_clock);          // leer lejos del flanco (convenciones §5)
            if (w_tick) begin
                if (first < 0) begin
                    first = cycle;
                    checks = checks + 1;
                    if (first != EXP_DIV) begin
                        errors = errors + 1;
                        $display("FAIL FIRST_TICK CLK=%0d: ciclo %0d, esperado %0d", CLOCK_FREQ, first, EXP_DIV);
                    end
                end else begin
                    periods = periods + 1;
                    checks = checks + 1;
                    if (cycle - last != EXP_DIV) begin
                        errors = errors + 1;
                        $display("FAIL PERIOD CLK=%0d: %0d ciclos, esperado %0d", CLOCK_FREQ, cycle - last, EXP_DIV);
                    end
                end
                last = cycle;
                // El tick dura exactamente 1 ciclo.
                @(posedge r_clock);
                cycle = cycle + 1;
                @(negedge r_clock);
                checks = checks + 1;
                if (w_tick) begin
                    errors = errors + 1;
                    $display("FAIL PULSE_WIDTH CLK=%0d: tick de más de 1 ciclo", CLOCK_FREQ);
                end
            end
        end
        err_pct = (CLOCK_FREQ / (EXP_DIV * 16.0) - BAUD_RATE) * 100.0 / BAUD_RATE;
        checks = checks + 1;
        if (err_pct > 2.0 || err_pct < -2.0) begin
            errors = errors + 1;
            $display("FAIL ERROR CLK=%0d: error de baudios %0.3f %%", CLOCK_FREQ, err_pct);
        end
        $display("CLK=%0d BAUD=%0d DIV=%0d err=%0.3f%%", CLOCK_FREQ, BAUD_RATE, EXP_DIV, err_pct);
        done = 1'b1;
    end
endmodule

module tb_baud_gen;
    // DIV esperado = round(CLOCK_FREQ / (BAUD_RATE * 16)), calculado a mano (no con la fórmula del RTL).
    baud_check #(.CLOCK_FREQ( 50_000_000), .BAUD_RATE(115_200), .EXP_DIV( 27)) c50  ();
    baud_check #(.CLOCK_FREQ( 75_000_000), .BAUD_RATE(115_200), .EXP_DIV( 41)) c75  ();
    baud_check #(.CLOCK_FREQ(100_000_000), .BAUD_RATE(115_200), .EXP_DIV( 54)) c100 ();
    baud_check #(.CLOCK_FREQ(125_000_000), .BAUD_RATE(115_200), .EXP_DIV( 68)) c125 ();
    baud_check #(.CLOCK_FREQ(100_000_000), .BAUD_RATE(  9_600), .EXP_DIV(651)) c9600();

    integer errors, checks;

    initial begin
        #(50_000_000);   // watchdog: 50 ms simulados (lo esperado es < 3 ms)
        $fatal(1, "FAIL tb_baud_gen: watchdog");
    end

    initial begin
        wait (c50.done && c75.done && c100.done && c125.done && c9600.done);
        errors = c50.errors + c75.errors + c100.errors + c125.errors + c9600.errors;
        checks = c50.checks + c75.checks + c100.checks + c125.checks + c9600.checks;
        if (errors != 0) $fatal(1, "FAIL tb_baud_gen: %0d errores", errors);
        $display("PASS tb_baud_gen: %0d chequeos", checks);
        $finish;
    end
endmodule

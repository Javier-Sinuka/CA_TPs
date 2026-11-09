`timescale 1ns/1ps

// TB automático de uart_if (B-04). Casos 1-11 de planning/issues/M0-uart/B-04-testbench-uart.md.
// Las entradas del DUT se manejan con <= en negedge; las salidas se leen en negedge.
module tb_uart;
    parameter integer CLOCK_FREQ = 50_000_000;
    parameter integer BAUD_RATE  = 115_200;
    localparam real CLK_HALF_NS = 1.0e9 / CLOCK_FREQ / 2.0;
    localparam real BIT_NS      = 1.0e9 / BAUD_RATE;

    reg        i_clock    = 1'b0;
    reg        i_reset    = 1'b1;
    reg        i_tx_start = 1'b0;
    reg  [7:0] i_tx_data  = 8'h00;
    wire       o_tx_busy;
    wire       o_rx_valid;
    wire [7:0] o_rx_data;
    wire       o_rx_frame_err;

    reg  bfm_rx = 1'b1;
    wire bfm_tx;
`include "uart_bfm.svh"

    always #(CLK_HALF_NS) i_clock = ~i_clock;

    uart_if #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_dut (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_rx(bfm_rx),
        .o_tx(bfm_tx),
        .i_tx_start(i_tx_start),
        .i_tx_data(i_tx_data),
        .o_tx_busy(o_tx_busy),
        .o_rx_valid(o_rx_valid),
        .o_rx_data(o_rx_data),
        .o_rx_frame_err(o_rx_frame_err)
    );

    integer errors = 0;
    integer checks = 0;

    task automatic fail(input string msg);
        begin
            errors = errors + 1;
            $display("FAIL %0s", msg);
        end
    endtask

    task automatic check(input bit cond, input string msg);
        begin
            checks = checks + 1;
            if (!cond) fail(msg);
        end
    endtask

    // ---- Monitor de RX y caso 10 (aserciones en cada ciclo) ----
    reg [7:0] rx_buf [0:1023];
    integer rx_count      = 0;
    integer ferr_count    = 0;
    reg     prev_rx_valid = 1'b0;
    reg     prev_busy     = 1'b0;

    // En el negedge N, i_tx_start/i_reset valen lo que valían en el posedge anterior (se manejan con <=),
    // y prev_busy es o_tx_busy de antes de ese posedge: así se sabe si ahí se aceptó un byte.
    always @(negedge i_clock) begin
        if (!i_reset) begin
            if (o_rx_valid) begin
                rx_buf[rx_count % 1024] = o_rx_data;
                rx_count = rx_count + 1;
            end
            if (o_rx_frame_err) ferr_count = ferr_count + 1;
            if (o_rx_valid && prev_rx_valid) fail("C10: o_rx_valid de más de 1 ciclo");
            if (o_rx_valid && o_rx_frame_err) fail("C10: o_rx_valid y o_rx_frame_err en el mismo ciclo");
            if (o_tx_busy !== (u_dut.u_tx.r_state != 2'd0)) fail("C10: o_tx_busy distinto de (TX fuera de IDLE)");
            if (i_tx_start && !prev_busy && o_tx_busy !== 1'b1) fail("C10: o_tx_busy no subió tras aceptar un byte");
        end
        prev_rx_valid = o_rx_valid;
        prev_busy     = o_tx_busy;
    end

    // ---- Ayudas de TX ----
    // Espera reposo, presenta el byte un ciclo (handshake valid/ready) y vuelve.
    task tx_send(input [7:0] b);
        begin
            @(negedge i_clock);
            while (o_tx_busy) @(negedge i_clock);
            i_tx_data  <= b;
            i_tx_start <= 1'b1;
            @(negedge i_clock);
            i_tx_start <= 1'b0;
        end
    endtask

    task tx_check(input [7:0] b, input string tag);
        reg [7:0] r;
        reg       rok;
        begin
            fork
                tx_send(b);
                bfm_recv_byte(r, rok);
            join
            check(rok && r == b, $sformatf("%0s: enviado %02h, recibido %02h, ok=%0d", tag, b, r, rok));
        end
    endtask

    // Verifica que no salga ningún byte por TX durante t_ns.
    task tx_none(input real t_ns, input string tag);
        reg [7:0] r;
        reg       rok;
        begin
            bfm_timeout_ns = t_ns;
            bfm_recv_byte(r, rok);
            bfm_timeout_ns = 20.0 * BIT_NS;
            check(!rok, $sformatf("%0s: salió un byte de más (%02h)", tag, r));
        end
    endtask

    // ---- Ayudas de RX ----
    // Envía n bytes (m*k + 5) % 256 con el emisor desviado ppm y gap_ns entre bytes, y verifica que lleguen todos.
    task rx_burst(input integer n, input integer k, input integer ppm, input real gap_ns, input string tag);
        integer m, base, ferr0, shown;
        reg [7:0] expv;
        begin
            bfm_bit_ns = BIT_NS * (1.0 + ppm / 1.0e6);
            bfm_gap_ns = gap_ns;
            base  = rx_count;
            ferr0 = ferr_count;
            for (m = 0; m < n; m = m + 1) bfm_send_byte((m * k + 5) % 256);
            #(3.0 * BIT_NS);
            bfm_bit_ns = BIT_NS;
            bfm_gap_ns = 0.0;
            check(rx_count - base == n, $sformatf("%0s: recibidos %0d de %0d", tag, rx_count - base, n));
            check(ferr_count == ferr0, $sformatf("%0s: %0d errores de framing", tag, ferr_count - ferr0));
            shown = 0;
            for (m = 0; m < n && m < rx_count - base; m = m + 1) begin
                expv = (m * k + 5) % 256;
                checks = checks + 1;
                if (rx_buf[(base + m) % 1024] !== expv) begin
                    if (shown < 5) fail($sformatf("%0s: byte %0d esperado %02h, recibido %02h", tag, m, expv, rx_buf[(base + m) % 1024]));
                    else errors = errors + 1;
                    shown = shown + 1;
                end
            end
        end
    endtask

    // Trama con stop en 0 y después la línea en reposo 2 bits.
    task send_bad_stop(input [7:0] b);
        integer m;
        begin
            bfm_rx = 1'b0;
            #(BIT_NS);
            for (m = 0; m < 8; m = m + 1) begin
                bfm_rx = b[m];
                #(BIT_NS);
            end
            bfm_rx = 1'b0;
            #(BIT_NS);
            bfm_rx = 1'b1;
            #(2.0 * BIT_NS);
        end
    endtask

    // ---- Watchdog: el doble de lo esperado (~11 000 bits) ----
    initial begin
        #(25000.0 * BIT_NS);
        $fatal(1, "FAIL tb_uart: watchdog");
    end

    integer i, j, base, ferr0, acc;
    integer ppm_list [0:6];
    reg [7:0] got;
    reg       ok;

    initial begin
        bfm_bit_ns     = BIT_NS;
        bfm_gap_ns     = 0.0;
        bfm_timeout_ns = 20.0 * BIT_NS;
        ppm_list[0] = -20000; ppm_list[1] = -10000; ppm_list[2] = -5000; ppm_list[3] = 0;
        ppm_list[4] =   5000; ppm_list[5] =  10000; ppm_list[6] = 20000;
        $display("tb_uart: CLOCK_FREQ=%0d BAUD_RATE=%0d BIT_NS=%0.1f", CLOCK_FREQ, BAUD_RATE, BIT_NS);
        repeat (10) @(negedge i_clock);
        i_reset <= 1'b0;
        #(2.0 * BIT_NS);

        $display("CASO 1: los 256 valores por RX y por TX");
        rx_burst(256, 1, 0, BIT_NS, "C1 RX");
        for (i = 0; i < 256; i = i + 1) tx_check(i, "C1 TX");
        #(2.0 * BIT_NS);

        $display("CASO 2: 64 bytes seguidos, emisor ideal");
        rx_burst(64, 37, 0, 0.0, "C2");

        $display("CASO 3: 64 bytes seguidos con el emisor desviado");
        for (j = 0; j < 7; j = j + 1)
            rx_burst(64, 37, ppm_list[j], 0.0, $sformatf("C3 %0d ppm", ppm_list[j]));

        $display("CASO 4: glitch de 1/4 de bit en reposo");
        base = rx_count; ferr0 = ferr_count;
        bfm_rx = 1'b0;
        #(BIT_NS / 4.0);
        bfm_rx = 1'b1;
        #(2.0 * BIT_NS);
        check(rx_count == base && ferr_count == ferr0, "C4: el glitch produjo un pulso de RX");
        rx_burst(1, 37, 0, 0.0, "C4 siguiente");

        $display("CASO 5: reset en mitad de trama (RX y TX)");
        base = rx_count; ferr0 = ferr_count;
        fork
            bfm_send_byte(8'hFF);   // datos en 1: tras el reset la línea queda en 1 y no hay start falso
            begin
                #(4.5 * BIT_NS);
                @(negedge i_clock); i_reset <= 1'b1;
                repeat (2) @(negedge i_clock);
                i_reset <= 1'b0;
            end
        join
        #(2.0 * BIT_NS);
        check(rx_count == base && ferr_count == ferr0, "C5 RX: pulso espurio después del reset");
        rx_burst(1, 37, 0, 0.0, "C5 RX siguiente");
        fork
            tx_send(8'h00);
            begin
                #(3.5 * BIT_NS);
                @(negedge i_clock); i_reset <= 1'b1;
                @(negedge i_clock);
                check(bfm_tx === 1'b1 && o_tx_busy === 1'b0, "C5 TX: con reset la línea no volvió a reposo");
                i_reset <= 1'b0;
            end
        join
        #(2.0 * BIT_NS);
        tx_check(8'hA5, "C5 TX siguiente");

        $display("CASO 7: stop en 0");
        base = rx_count; ferr0 = ferr_count;
        send_bad_stop(8'h5C);
        check(ferr_count - ferr0 == 1, $sformatf("C7: %0d pulsos de o_rx_frame_err, esperado 1", ferr_count - ferr0));
        check(rx_count == base, "C7: hubo o_rx_valid con stop en 0");
        rx_burst(1, 37, 0, 0.0, "C7 siguiente");

        $display("CASO 8: i_tx_start con o_tx_busy = 1");
        fork
            begin
                tx_send(8'h12);
                #(3.0 * BIT_NS);
                @(negedge i_clock);
                i_tx_data  <= 8'h34;
                i_tx_start <= 1'b1;
                @(negedge i_clock);
                i_tx_start <= 1'b0;
            end
            begin
                bfm_recv_byte(got, ok);
                check(ok && got == 8'h12, $sformatf("C8: recibido %02h ok=%0d, esperado 12", got, ok));
                tx_none(3.0 * BIT_NS, "C8");
            end
        join

        $display("CASO 9: i_tx_start sostenido durante 3 aceptaciones");
        fork
            begin
                @(negedge i_clock);
                i_tx_data  <= 8'h6B;
                i_tx_start <= 1'b1;
                acc = 0;
                // En cada negedge con start en 1 y busy en 0, el posedge siguiente acepta un byte.
                // Al contar la 3.ª se avanza un negedge (ya pasó esa aceptación) y se baja start:
                // ahí busy vale 1, así que no hay una 4.ª.
                while (acc < 3) begin
                    if (!o_tx_busy) acc = acc + 1;
                    @(negedge i_clock);
                end
                i_tx_start <= 1'b0;
            end
            begin
                for (j = 0; j < 3; j = j + 1) begin
                    bfm_recv_byte(got, ok);
                    check(ok && got == 8'h6B, $sformatf("C9: byte %0d = %02h ok=%0d, esperado 6B", j, got, ok));
                end
                tx_none(3.0 * BIT_NS, "C9");
            end
        join

        $display("CASO 11: cambio de i_tx_data después de la aceptación");
        fork
            begin
                tx_send(8'hC3);
                i_tx_data <= 8'h3C;
            end
            begin
                bfm_recv_byte(got, ok);
                check(ok && got == 8'hC3, $sformatf("C11: recibido %02h ok=%0d, esperado C3", got, ok));
            end
        join
        #(2.0 * BIT_NS);

        if (errors != 0) $fatal(1, "FAIL tb_uart: %0d errores", errors);
        $display("PASS tb_uart: %0d chequeos", checks);
        $finish;
    end
endmodule

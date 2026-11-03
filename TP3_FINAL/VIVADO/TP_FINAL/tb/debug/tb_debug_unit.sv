`timescale 1ns/1ps

// Debug Unit con cpu_stub: casos de B-10 (V, X, comando desconocido, A en reposo,
// comandos seguidos y overrun). B-11 a B-16 agregan casos detrás de estos.
module tb_debug_unit;
    parameter integer HALT_AT = 20;                 // el runner pasa 20 o 0
    localparam integer CLOCK_FREQ = 50_000_000;
    localparam integer BAUD_RATE  = CLOCK_FREQ / 32;   // 1 562 500 → 640 ns por bit

    reg clk = 1'b0;
    always #10 clk = ~clk;
    reg rst = 1'b1;

    reg  bfm_rx = 1'b1;
    wire bfm_tx;
    wire [7:0] leds;

    integer errors = 0, checks = 0;

    system #(.CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(BAUD_RATE), .BYTE_TIMEOUT(20_000),
             .RUN_TIMEOUT(1_000), .HALT_AT(HALT_AT))
        dut (.i_clock(clk), .i_reset(rst), .i_rx(bfm_rx), .o_tx(bfm_tx), .o_leds(leds));

    `include "uart_bfm.svh"
    `include "tb_debug_helpers.svh"

    // Monitores (se leen en negedge, convenciones.md §5)
    integer en_cycles = 0, rst_cycles = 0;
    always @(negedge clk) begin
        if (dut.u_debug.o_cpu_en)  en_cycles  = en_cycles + 1;
        if (dut.u_debug.o_cpu_rst) rst_cycles = rst_cycles + 1;
    end

    // imem solo se escribe con cpu_rst = 1 (B-13)
    always @(negedge clk) begin
        if (dut.u_debug.o_imem_we && !dut.u_debug.o_cpu_rst) begin
            errors = errors + 1;
            $display("FAIL L: escritura de imem con cpu_rst = 0");
        end
    end

    task automatic check_eq(input integer got, input integer exp, input string caso);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL %s: exp=%0d got=%0d", caso, exp, got);
            end
        end
    endtask

    initial begin #(200_000_000); $fatal(1, "FAIL tb_debug_unit: watchdog"); end

    integer rst0, en0, k;
    integer c, x1, sum, m;
    reg [7:0] r_abort_dump [0:233];

    // Programa de prueba de L (B-13)
    reg [31:0] prog [0:255];
    reg [31:0] snap [0:255];
    integer seed = 32'h0000_0B13;

    task automatic gen_prog(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) prog[i] = $random(seed);
        end
    endtask

    // imem == prog[0..n-1] y HALT en el resto; un chequeo por palabra
    task automatic check_imem(input integer n, input string caso);
        integer i;
        reg [31:0] exp_w;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                exp_w = (i < n) ? prog[i] : 32'h0000_0073;
                checks = checks + 1;
                if (dut.u_imem.r_mem[i] !== exp_w) begin
                    errors = errors + 1;
                    $display("FAIL %s: imem[%0d] exp=%08h got=%08h", caso, i, exp_w,
                             dut.u_imem.r_mem[i]);
                end
            end
        end
    endtask

    // L en dos fases: 4C NL NH -> K; 4*n bytes little-endian -> K
    task automatic send_load(input integer n, input string caso);
        integer i;
        real saved_to;
        begin
            q_clear; q_push(8'h4C); q_push(n[7:0]); q_push(n[15:8]); exp_push(8'h4B);
            transact(n_exp); check_exp({caso, ": fase N"});
            q_clear;
            for (i = 0; i < n; i = i + 1) begin
                q_push(prog[i][7:0]);  q_push(prog[i][15:8]);
                q_push(prog[i][23:16]); q_push(prog[i][31:24]);
            end
            exp_push(8'h4B);
            // el receptor espera el K mientras el host sigue enviando: el timeout
            // tiene que cubrir los 4*n bytes (N=256 son 6,5 ms, mas que los 2 ms base)
            saved_to = bfm_timeout_ns;
            bfm_timeout_ns = saved_to + n * 40.0 * bfm_bit_ns;
            transact(n_exp); check_exp({caso, ": fase datos"});
            bfm_timeout_ns = saved_to;
        end
    endtask

    initial begin
        bfm_bit_ns     = 640.0;
        bfm_gap_ns     = 0.0;
        bfm_timeout_ns = 2_000_000.0;
        repeat (10) @(negedge clk);
        rst = 1'b0;
        repeat (10) @(negedge clk);

        if (HALT_AT == 20) begin
            // --- casos de B-10 ---
            q_clear; q_push(8'h56);
            exp_push(8'h56); exp_push(8'h01); exp_push(8'h00);
            exp_push(8'h01); exp_push(8'h00); exp_push(8'h01);
            transact(n_exp); check_exp("V");

            rst0 = rst_cycles; en0 = en_cycles;
            q_clear; q_push(8'h58); exp_push(8'h4B);
            transact(n_exp); check_exp("X");
            check_eq(rst_cycles - rst0, 1, "X: o_cpu_rst dura 1 ciclo");
            check_eq(en_cycles - en0, 0, "X: o_cpu_en no se mueve");

            q_clear; q_push(8'h7A); exp_push(8'h45); exp_push(8'h01);
            transact(n_exp); check_exp("desconocido");

            q_clear; q_push(8'h41);
            send_all;
            expect_silence(20_000.0, "A en reposo");
            q_clear; q_push(8'h56);
            exp_push(8'h56); exp_push(8'h01); exp_push(8'h00);
            exp_push(8'h01); exp_push(8'h00); exp_push(8'h01);
            transact(n_exp); check_exp("V después de A");

            rst0 = rst_cycles;
            q_clear; q_push(8'h58); q_push(8'h58); exp_push(8'h4B); exp_push(8'h4B);
            transact(n_exp); check_exp("X X seguidos");
            check_eq(rst_cycles - rst0, 2, "X X: o_cpu_rst dos pulsos");

            q_clear; q_push(8'h56); q_push(8'h56);
            repeat (2) begin
                exp_push(8'h56); exp_push(8'h01); exp_push(8'h00);
                exp_push(8'h01); exp_push(8'h00); exp_push(8'h01);
            end
            transact(n_exp); check_exp("V V seguidos");

            q_clear; q_push(8'h56); q_push(8'h56); q_push(8'h56);
            repeat (2) begin
                exp_push(8'h56); exp_push(8'h01); exp_push(8'h00);
                exp_push(8'h01); exp_push(8'h00); exp_push(8'h01);
            end
            transact(n_exp); check_exp("V V V seguidos");
            expect_silence(20_000.0, "V V V: sin tercera respuesta");
            @(negedge clk);
            check_eq(leds[2], 1, "V V V: LED de overrun");

            // --- casos de B-14 (el CPU sigue con 0 ciclos) ---
            en0 = en_cycles;
            q_clear; q_push(8'h44);
            n_exp = 0; exp_vec("dump_c0_h20.hex", 210);
            transact(n_exp); check_exp("D");
            check_eq(en_cycles - en0, 0, "D: o_cpu_en no se mueve");

            q_clear; q_push(8'h44); q_push(8'h44);
            n_exp = 0; exp_vec("dump_c0_h20.hex", 210); exp_vec("dump_c0_h20.hex", 210);
            transact(n_exp); check_exp("D D seguidos");

            rst0 = rst_cycles;
            q_clear; q_push(8'h44); q_push(8'h58);
            n_exp = 0; exp_vec("dump_c0_h20.hex", 210); exp_push(8'h4B);
            transact(n_exp); check_exp("D X seguidos");
            check_eq(rst_cycles - rst0, 1, "D X: la X paso por el pendiente");

            // --- casos de B-11 (parte de 0 ciclos) ---
            for (k = 1; k <= 10; k = k + 1) begin
                en0 = en_cycles;
                q_clear; q_push(8'h53);
                n_exp = 0; exp_vec($sformatf("dump_c%0d_h20.hex", k), 234);
                transact(n_exp); check_exp($sformatf("S %0d", k));
                check_eq(en_cycles - en0, 1, $sformatf("S %0d: un flanco habilitado", k));
            end
            for (k = 11; k <= 19; k = k + 1) begin
                en0 = en_cycles;
                q_clear; q_push(8'h53);
                transact(234);
                check_eq(en_cycles - en0, 1, $sformatf("S %0d: un flanco habilitado", k));
            end
            en0 = en_cycles;
            q_clear; q_push(8'h53);
            n_exp = 0; exp_vec("dump_c20_h20.hex", 234);
            transact(n_exp); check_exp("S 20");
            check_eq(en_cycles - en0, 1, "S 20: un flanco habilitado");

            en0 = en_cycles;
            q_clear; q_push(8'h53);
            n_exp = 0; exp_vec("dump_c20_h20.hex", 234);
            transact(n_exp); check_exp("S con halted");
            check_eq(en_cycles - en0, 1, "S con halted: el pulso existe");

            // --- casos de B-12 (parte h20; el CPU esta en halted) ---
            en0 = en_cycles;
            q_clear; q_push(8'h52);
            n_exp = 0; exp_vec("dump_c20_h20.hex", 234);
            transact(n_exp); check_exp("R con halted");
            check_eq(en_cycles - en0, 0, "R con halted: cpu_en no se mueve");

            q_clear; q_push(8'h58); exp_push(8'h4B);
            transact(n_exp); check_exp("X");

            en0 = en_cycles;
            q_clear; q_push(8'h52);
            n_exp = 0; exp_vec("dump_c20_h20.hex", 234);
            transact(n_exp); check_exp("R hasta HALT");
            check_eq(en_cycles - en0, 21, "R hasta HALT: 21 ciclos con cpu_en");

            // --- casos de B-13 (el CPU esta en halted con 20 ciclos) ---
            en0 = en_cycles;
            prog[0] = 32'h0050_0093; prog[1] = 32'h0000_0073;
            send_load(2, "L N=2 ejemplo");
            check_imem(2, "L N=2 ejemplo");
            check_eq(en_cycles - en0, 0, "L N=2: cpu_en no se mueve");

            q_clear; q_push(8'h44);
            n_exp = 0; exp_vec("dump_c0_h20.hex", 210);
            transact(n_exp); check_exp("D tras L");

            gen_prog(1);
            send_load(1, "L N=1"); check_imem(1, "L N=1");

            gen_prog(37);
            send_load(37, "L N=37"); check_imem(37, "L N=37");

            gen_prog(256);
            send_load(256, "L N=256"); check_imem(256, "L N=256");

            q_clear; q_push(8'h4C); q_push(8'h00); q_push(8'h00);
            exp_push(8'h4B); exp_push(8'h4B);
            transact(n_exp); check_exp("L N=0");
            check_imem(0, "L N=0");

            // N=257: se rechaza y imem no cambia
            gen_prog(256);
            send_load(256, "L previo a N=257");
            for (m = 0; m < 256; m = m + 1) snap[m] = dut.u_imem.r_mem[m];
            q_clear; q_push(8'h4C); q_push(8'h01); q_push(8'h01);
            exp_push(8'h45); exp_push(8'h02);
            transact(n_exp); check_exp("L N=257");
            for (m = 0; m < 256; m = m + 1) begin
                checks = checks + 1;
                if (dut.u_imem.r_mem[m] !== snap[m]) begin
                    errors = errors + 1;
                    $display("FAIL L N=257: imem[%0d] cambio", m);
                end
            end
            check_eq(dut.u_debug.o_cpu_rst, 0, "L N=257: cpu_rst vuelve a 0");

            // cortes: respuesta 45 03 y el comando siguiente se atiende bien
            q_clear; q_push(8'h4C); q_push(8'h01); q_push(8'h00); exp_push(8'h4B);
            transact(n_exp); check_exp("L corte en datos: fase N");
            q_clear; q_push(8'h93); q_push(8'h00); exp_push(8'h45); exp_push(8'h03);
            transact(n_exp); check_exp("L corte en datos");
            q_clear; q_push(8'h56);
            exp_push(8'h56); exp_push(8'h01); exp_push(8'h00);
            exp_push(8'h01); exp_push(8'h00); exp_push(8'h01);
            transact(n_exp); check_exp("V tras corte en datos");

            q_clear; q_push(8'h4C); q_push(8'h01); exp_push(8'h45); exp_push(8'h03);
            transact(n_exp); check_exp("L corte en N");
            q_clear; q_push(8'h56);
            exp_push(8'h56); exp_push(8'h01); exp_push(8'h00);
            exp_push(8'h01); exp_push(8'h00); exp_push(8'h01);
            transact(n_exp); check_exp("V tras corte en N");
        end else begin
            // --- casos de B-14 (parte h0) ---
            q_clear; q_push(8'h44);
            n_exp = 0; exp_vec("dump_c0_h0.hex", 210);
            transact(n_exp); check_exp("D h0");

            // --- casos de B-12 (parte h0; sin HALT) ---
            en0 = en_cycles;
            q_clear; q_push(8'h52);
            n_exp = 0; exp_vec("dump_c1000_h0_t.hex", 234);
            transact(n_exp); check_exp("R timeout");
            check_eq(en_cycles - en0, 1000, "R timeout: 1000 ciclos con cpu_en");

            q_clear; q_push(8'h58); exp_push(8'h4B);
            transact(n_exp); check_exp("X");

            q_clear; q_push(8'h52); q_push(8'h56);
            n_exp = 0; exp_vec("dump_c1000_h0_t.hex", 234);
            transact(n_exp); check_exp("R con otro byte");
            expect_silence(20_000.0, "R con otro byte: la V se descarto");

            q_clear; q_push(8'h58); exp_push(8'h4B);
            transact(n_exp); check_exp("X");

            en0 = en_cycles;
            q_clear; q_push(8'h52); q_push(8'h41);
            transact(234);
            for (m = 0; m < 234; m = m + 1) r_abort_dump[m] = q_rx[m];
            c   = q_rx[5] | (q_rx[6] << 8) | (q_rx[7] << 16) | (q_rx[8] << 24);
            x1  = q_rx[17] | (q_rx[18] << 8) | (q_rx[19] << 16) | (q_rx[20] << 24);
            sum = 0;
            for (m = 1; m <= 232; m = m + 1) sum = sum + q_rx[m];
            check_eq(q_rx[0], 8'hA5, "R con A: cabecera");
            check_eq({q_rx[4], q_rx[3], q_rx[2], q_rx[1]}, 32'h0000_0104, "R con A: W0 (aborted, version 1)");
            check_eq((c > 0) && (c < 1000), 1, "R con A: 0 < c < 1000");
            check_eq(en_cycles - en0, c, "R con A: en_cycles == c");
            check_eq(x1, (c << 8) | 1, "R con A: x1 == (c << 8) | 1");
            check_eq({q_rx[208], q_rx[207], q_rx[206], q_rx[205]}, 3, "R con A: M");
            check_eq(sum % 256, q_rx[233], "R con A: checksum");

            q_clear; q_push(8'h44);
            n_exp = 0;
            for (m = 0; m < 234; m = m + 1) exp_push(r_abort_dump[m]);
            transact(n_exp); check_exp("D tras A");

            q_clear; q_push(8'h41);
            send_all;
            expect_silence(20_000.0, "A suelto");
        end

        if (errors != 0) $fatal(1, "FAIL tb_debug_unit: %0d errores (HALT_AT=%0d)", errors, HALT_AT);
        $display("PASS tb_debug_unit: %0d chequeos (HALT_AT=%0d)", checks, HALT_AT);
        $finish;
    end
endmodule

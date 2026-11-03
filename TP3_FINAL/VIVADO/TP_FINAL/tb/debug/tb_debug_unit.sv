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

    integer rst0, en0;

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
        end else begin
            // --- casos de B-14 (parte h0) ---
            q_clear; q_push(8'h44);
            n_exp = 0; exp_vec("dump_c0_h0.hex", 210);
            transact(n_exp); check_exp("D h0");
            // casos de B-12 (parte h0)
        end

        if (errors != 0) $fatal(1, "FAIL tb_debug_unit: %0d errores (HALT_AT=%0d)", errors, HALT_AT);
        $display("PASS tb_debug_unit: %0d chequeos (HALT_AT=%0d)", checks, HALT_AT);
        $finish;
    end
endmodule

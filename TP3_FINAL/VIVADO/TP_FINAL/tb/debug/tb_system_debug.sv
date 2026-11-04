`timescale 1ns/1ps

// Guion de la Fase 10 contra system (UART + Debug Unit + stub + imem), manejado solo
// por la linea serie. Deja un log de bytes en TP3_FINAL/build/tb_system_debug.bytes.log
// (formato en B-16; lo reutilizan B-23 y B-28).
module tb_system_debug;
    localparam integer HALT_AT    = 20;
    localparam integer CLOCK_FREQ = 50_000_000;
    localparam integer BAUD_RATE  = CLOCK_FREQ / 32;   // 1 562 500 -> 640 ns por bit

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

    initial begin #(100_000_000); $fatal(1, "FAIL tb_system_debug: watchdog"); end

    integer en0, k;

    initial begin
        log_fd = $fopen("TP3_FINAL/build/tb_system_debug.bytes.log", "w");
        $fwrite(log_fd, "# tb_system_debug v1\n");

        bfm_bit_ns     = 640.0;
        bfm_gap_ns     = 0.0;
        bfm_timeout_ns = 2_000_000.0;
        repeat (10) @(negedge clk);
        rst = 1'b0;
        repeat (10) @(negedge clk);

        // 1. V
        log_step("V");
        q_clear; q_push(8'h56);
        exp_push(8'h56); exp_push(8'h01); exp_push(8'h00);
        exp_push(8'h01); exp_push(8'h00); exp_push(8'h01);
        transact(n_exp); check_exp("V");

        // 2. L A: 37 palabras 0xA0000000 + i
        log_step("L A");
        for (k = 0; k < 37; k = k + 1) prog[k] = 32'hA000_0000 + k;
        send_load(37, "L A");
        check_imem(37, "L A");

        // 3. S 1 ... S 5
        for (k = 1; k <= 5; k = k + 1) begin
            log_step($sformatf("S %0d", k));
            en0 = en_cycles;
            q_clear; q_push(8'h53);
            n_exp = 0; exp_vec($sformatf("dump_c%0d_h20.hex", k), 234);
            transact(n_exp); check_exp($sformatf("S %0d", k));
            check_eq(en_cycles - en0, 1, $sformatf("S %0d: un flanco habilitado", k));
        end

        // 4. R
        log_step("R");
        q_clear; q_push(8'h52);
        n_exp = 0; exp_vec("dump_c20_h20.hex", 234);
        transact(n_exp); check_exp("R");

        // 5. D
        log_step("D");
        q_clear; q_push(8'h44);
        n_exp = 0; exp_vec("dump_c20_h20.hex", 234);
        transact(n_exp); check_exp("D");

        // 6. X
        log_step("X");
        q_clear; q_push(8'h58); exp_push(8'h4B);
        transact(n_exp); check_exp("X");

        // 7. L B: {addi x1,x0,5 ; HALT}
        log_step("L B");
        prog[0] = 32'h0050_0093; prog[1] = 32'h0000_0073;
        send_load(2, "L B");
        check_imem(2, "L B");

        // 8. R B
        log_step("R B");
        q_clear; q_push(8'h52);
        n_exp = 0; exp_vec("dump_c20_h20.hex", 234);
        transact(n_exp); check_exp("R B");

        // 9. invalido
        log_step("invalido");
        q_clear; q_push(8'h7A); exp_push(8'h45); exp_push(8'h01);
        transact(n_exp); check_exp("invalido");

        // 10. D final
        log_step("D final");
        q_clear; q_push(8'h44);
        n_exp = 0; exp_vec("dump_c20_h20.hex", 234);
        transact(n_exp); check_exp("D final");

        $fclose(log_fd);
        log_fd = 0;
        if (errors != 0) $fatal(1, "FAIL tb_system_debug: %0d errores", errors);
        $display("PASS tb_system_debug: %0d chequeos", checks);
        $finish;
    end
endmodule

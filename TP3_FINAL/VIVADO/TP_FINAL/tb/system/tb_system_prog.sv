`timescale 1ns/1ps

// Carga un programa de TP3_FINAL/programs por la linea serie simulada (V, L), ejecuta R y
// guarda el dump recibido (un byte por linea, en hexadecimal) en un archivo. Simula `system`.
//
// Plusargs (rutas relativas a la raiz del repo):
//   +prog=<ruta .hex>   default TP3_FINAL/programs/suma.hex
//   +out=<ruta>         default TP3_FINAL/build/tb_system_prog.dump.hex
//
// Con CPU_STUB (entrada tb_system_prog_stub de tools/tbs.py) verifica ademas halted = 1,
// W1 = HALT_AT y M = 3. Sin CPU_STUB no verifica el contenido: lo compara B-27 contra el
// .expected.json.
//
// Paso de la Fase 10 (CPU real): llenar CPU_FILES en tools/tbs.py con los archivos del CPU
// (cpu.v y submodulos). Nada mas cambia: system.v instancia `cpu` cuando CPU_STUB no esta definido.
module tb_system_prog;
    localparam integer CLOCK_FREQ   = 50_000_000;
    localparam integer BAUD_RATE    = 1_562_500;     // 640 ns por bit
    localparam integer BYTE_TIMEOUT = 20_000;
    localparam integer RUN_TIMEOUT  = 20_000;
    localparam integer HALT_AT      = 20;
    localparam integer IMEM_WORDS   = 256;

    reg clk = 1'b0;
    always #10 clk = ~clk;
    reg rst = 1'b1;

    reg  bfm_rx = 1'b1;
    wire bfm_tx;
    wire [7:0] leds;

    integer errors = 0, checks = 0;

    system #(.CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(BAUD_RATE), .BYTE_TIMEOUT(BYTE_TIMEOUT),
             .RUN_TIMEOUT(RUN_TIMEOUT), .HALT_AT(HALT_AT))
        dut (.i_clock(clk), .i_reset(rst), .i_rx(bfm_rx), .o_tx(bfm_tx), .o_leds(leds));

    `include "uart_bfm.svh"

    initial begin #(50_000_000); $fatal(1, "FAIL tb_system_prog: watchdog"); end

    string prog_path, out_path;
    reg [31:0] words [0:IMEM_WORDS-1];
    reg [7:0]  rxb [0:4095];     // dump completo, con la cabecera en la posicion 0
    integer n, m, len, i, fd;
    reg [31:0] w;
    reg [7:0]  sum;
    reg [7:0]  b;
    reg        ok;

    task check_eq(input [31:0] got, input [31:0] exp, input string what);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL tb_system_prog: %0s esperado=%0h obtenido=%0h", what, exp, got);
            end
        end
    endtask

    task recv_chk(output [7:0] r, input string what);
        reg ok_r;
        begin
            bfm_recv_byte(r, ok_r);
            if (!ok_r) $fatal(1, "FAIL tb_system_prog: %0s: sin respuesta o stop invalido", what);
        end
    endtask

    task expect_byte(input [7:0] exp, input string what);
        reg [7:0] r;
        begin
            recv_chk(r, what);
            check_eq(r, exp, what);
        end
    endtask

    task send_word(input [31:0] x);
        begin
            bfm_send_byte(x[7:0]);
            bfm_send_byte(x[15:8]);
            bfm_send_byte(x[23:16]);
            bfm_send_byte(x[31:24]);
        end
    endtask

    initial begin
        if (!$value$plusargs("prog=%s", prog_path)) prog_path = "TP3_FINAL/programs/suma.hex";
        if (!$value$plusargs("out=%s", out_path))   out_path  = "TP3_FINAL/build/tb_system_prog.dump.hex";

        bfm_bit_ns     = 1.0e9 / BAUD_RATE;
        bfm_gap_ns     = 0.0;
        bfm_timeout_ns = 2.0e6;

        repeat (10) @(negedge clk);
        rst = 1'b0;
        repeat (10) @(negedge clk);

        // Programa: las palabras hasta la primera que quedo sin leer
        for (i = 0; i < IMEM_WORDS; i = i + 1) words[i] = 32'hxxxxxxxx;
        $readmemh(prog_path, words);
        n = IMEM_WORDS;
        for (i = IMEM_WORDS - 1; i >= 0; i = i - 1) if (^words[i] === 1'bx) n = i;
        if (n == 0) $fatal(1, "FAIL tb_system_prog: programa vacio o inexistente (%0s)", prog_path);

        // V
        bfm_send_byte(8'h56);
        expect_byte(8'h56, "V cabecera");
        expect_byte(8'h01, "V version");
        expect_byte(8'h00, "V IMEM_WORDS bajo");
        expect_byte(8'h01, "V IMEM_WORDS alto");
        expect_byte(8'h00, "V DMEM_WORDS bajo");
        expect_byte(8'h01, "V DMEM_WORDS alto");

        // L
        bfm_send_byte(8'h4C);
        bfm_send_byte(n[7:0]);
        bfm_send_byte(n[15:8]);
        expect_byte(8'h4B, "L primer K");
        for (i = 0; i < n; i = i + 1) send_word(words[i]);
        expect_byte(8'h4B, "L K final");

        // imem por jerarquia: el programa y HALT en el resto
        for (i = 0; i < IMEM_WORDS; i = i + 1) begin
            w = (i < n) ? words[i] : 32'h0000_0073;
            check_eq(dut.u_imem.r_mem[i], w, $sformatf("imem[%0d]", i));
        end

        // R: cabecera + W0..W51, despues M pares y el checksum
        bfm_send_byte(8'h52);
        for (i = 0; i <= 208; i = i + 1) begin
            recv_chk(b, $sformatf("R byte %0d", i));
            rxb[i] = b;
        end
        check_eq(rxb[0], 8'hA5, "R cabecera");
        m = {rxb[208], rxb[207], rxb[206], rxb[205]};
        if (m > 256) $fatal(1, "FAIL tb_system_prog: M=%0d fuera de rango", m);
        len = 210 + 8 * m;
        for (i = 209; i < len; i = i + 1) begin
            recv_chk(b, $sformatf("R byte %0d", i));
            rxb[i] = b;
        end

        // no llegan bytes de mas
        bfm_timeout_ns = 50_000.0;
        bfm_recv_byte(b, ok);
        check_eq(ok, 1'b0, "bytes de mas despues del checksum");

        // checksum: suma de W0 hasta el ultimo par, sin la cabecera ni el propio checksum
        sum = 8'h00;
        for (i = 1; i < len - 1; i = i + 1) sum = sum + rxb[i];
        check_eq(rxb[len - 1], sum, "checksum");

        // salida: un byte por linea
        fd = $fopen(out_path, "w");
        if (fd == 0) $fatal(1, "FAIL tb_system_prog: no se pudo abrir %0s", out_path);
        for (i = 0; i < len; i = i + 1) $fdisplay(fd, "%02x", rxb[i]);
        $fclose(fd);

`ifdef CPU_STUB
        check_eq(rxb[1][0], 1'b1, "stub: halted");
        check_eq({rxb[8], rxb[7], rxb[6], rxb[5]}, HALT_AT, "stub: W1 ciclos");
        check_eq(m, 3, "stub: M");
`endif

        if (errors != 0) $fatal(1, "FAIL tb_system_prog: %0d errores", errors);
        $display("PASS tb_system_prog: %0d chequeos, %0d palabras, %0d bytes de dump", checks, n, len);
        $finish;
    end
endmodule

// Tareas comunes de los TB de la Debug Unit (B-10). Se incluye DENTRO del módulo
// TB, después de uart_bfm.svh. El TB debe declarar errors, checks y la instancia dut
// (con u_imem, para check_imem).

`define VEC_DIR "TP3_FINAL/VIVADO/TP_FINAL/tb/debug/vectors/"

reg  [7:0] q_tx  [0:2047];   // bytes a enviar
integer    n_tx = 0;
reg  [7:0] q_rx  [0:4095];   // bytes recibidos
integer    n_rx = 0;
reg  [7:0] q_exp [0:4095];   // bytes esperados
integer    n_exp = 0;
integer    log_fd = 0;       // B-16 lo abre; 0 = no se loguea

task automatic q_clear;
    begin
        n_tx  = 0;
        n_exp = 0;
    end
endtask

task automatic q_push(input [7:0] b);
    begin
        q_tx[n_tx] = b;
        n_tx = n_tx + 1;
    end
endtask

task automatic exp_push(input [7:0] b);
    begin
        q_exp[n_exp] = b;
        n_exp = n_exp + 1;
    end
endtask

task automatic log_step(input string name);
    begin
        if (log_fd != 0) $fwrite(log_fd, "# %s\n", name);
    end
endtask

// Envía q_tx[0..n_tx-1] sin pausa; con log_fd escribe "> xx" por byte
task automatic send_all;
    integer i;
    begin
        for (i = 0; i < n_tx; i = i + 1) begin
            if (log_fd != 0) $fwrite(log_fd, "> %02x\n", q_tx[i]);
            bfm_send_byte(q_tx[i]);
        end
    end
endtask

// Recibe n bytes en q_rx; corta en el primero que no llega. Loguea "< xx".
task automatic recv_n(input integer n);
    integer i;
    reg [7:0] b;
    reg       ok;
    reg       stop;
    begin
        n_rx = 0;
        stop = 1'b0;
        for (i = 0; i < n && !stop; i = i + 1) begin
            bfm_recv_byte(b, ok);
            if (!ok) begin
                errors = errors + 1;
                $display("FAIL recv: byte %0d de %0d no llegó", i, n);
                stop = 1'b1;
            end else begin
                q_rx[n_rx] = b;
                n_rx = n_rx + 1;
                if (log_fd != 0) $fwrite(log_fd, "< %02x\n", b);
            end
        end
    end
endtask

// Envía y recibe a la vez: el receptor tiene que estar escuchando desde el principio
task automatic transact(input integer n);
    begin
        fork
            send_all;
            recv_n(n);
        join
    end
endtask

// Compara q_rx[0..n_exp-1] con q_exp, un chequeo por byte
task automatic check_exp(input string caso);
    integer i;
    begin
        if (n_rx != n_exp) begin
            errors = errors + 1;
            $display("FAIL %s: llegaron %0d bytes, se esperaban %0d", caso, n_rx, n_exp);
        end
        for (i = 0; i < n_exp && i < n_rx; i = i + 1) begin
            checks = checks + 1;
            if (q_rx[i] !== q_exp[i]) begin
                errors = errors + 1;
                $display("FAIL %s: byte %0d exp=%02h got=%02h", caso, i, q_exp[i], q_rx[i]);
            end
        end
    end
endtask

// Agrega n bytes del vector fname al final de lo esperado
// (Icarus avisa "not enough words" porque el archivo no llena el arreglo: es esperado)
task automatic exp_vec(input string fname, input integer n);
    begin
        $readmemh($sformatf("%s%s", `VEC_DIR, fname), q_exp, n_exp);
        n_exp = n_exp + n;
    end
endtask

task automatic check_vec(input string fname, input integer n, input string caso);
    begin
        n_exp = 0;
        exp_vec(fname, n);
        check_exp(caso);
    end
endtask

// Espera t_ns y verifica que no empezó ningún byte en bfm_tx
task automatic expect_silence(input real t_ns, input string caso);
    real      saved;
    reg [7:0] b;
    reg       ok;
    begin
        saved = bfm_timeout_ns;
        bfm_timeout_ns = t_ns;
        bfm_recv_byte(b, ok);
        bfm_timeout_ns = saved;
        checks = checks + 1;
        if (ok) begin
            errors = errors + 1;
            $display("FAIL %s: llegó el byte %02h y se esperaba silencio", caso, b);
        end
    end
endtask

// ---- Comunes a tb_debug_unit y tb_system_debug (B-13, B-16) ----

task automatic check_eq(input integer got, input integer exp, input string caso);
    begin
        checks = checks + 1;
        if (got !== exp) begin
            errors = errors + 1;
            $display("FAIL %s: exp=%0d got=%0d", caso, exp, got);
        end
    end
endtask

reg [31:0] prog [0:255];     // programa que envía send_load y que verifica check_imem

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

// Tareas comunes de los TB de la Debug Unit (B-10). Se incluye DENTRO del módulo
// TB, después de uart_bfm.svh. El TB debe declarar errors, checks y la instancia dut.

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

// uart_bfm.svh: modelo de la PC en la línea serie (8N1, LSB primero).
// Se incluye DENTRO de un módulo de TB que declara antes del include:
//     reg  bfm_rx = 1'b1;   // conectado a i_rx del DUT
//     wire bfm_tx;          // conectado a o_tx del DUT
// El TB fija bfm_bit_ns (y si hace falta bfm_gap_ns y bfm_timeout_ns) antes de usar las tareas.
// Los tiempos son reales, en las unidades del `timescale del TB (ns), y no dependen del DUT.

real bfm_bit_ns;
real bfm_gap_ns     = 0.0;
real bfm_timeout_ns = 1.0e9;

// Envía un byte por bfm_rx y después deja la línea en reposo bfm_gap_ns.
task automatic bfm_send_byte(input [7:0] b);
    integer i;
    begin
        bfm_rx = 1'b0;
        #(bfm_bit_ns);
        for (i = 0; i < 8; i = i + 1) begin
            bfm_rx = b[i];
            #(bfm_bit_ns);
        end
        bfm_rx = 1'b1;
        #(bfm_bit_ns);
        if (bfm_gap_ns > 0.0) #(bfm_gap_ns);
    end
endtask

// Espera un start en bfm_tx (a lo sumo bfm_timeout_ns) y decodifica un byte muestreando a mitad de bit.
// ok = 0 si no llegó el start o si el stop vino en 0. Vuelve a mitad del stop bit.
// Se llama con la línea en reposo: detecta el nivel bajo con resolución de 1 ns.
task automatic bfm_recv_byte(output [7:0] b, output reg ok);
    integer i;
    real waited;
    begin
        b = 8'h00;
        ok = 1'b0;
        waited = 0.0;
        while (bfm_tx !== 1'b0 && waited < bfm_timeout_ns) begin
            #(1.0);
            waited = waited + 1.0;
        end
        if (bfm_tx === 1'b0) begin
            #(bfm_bit_ns / 2.0);
            if (bfm_tx === 1'b0) begin
                for (i = 0; i < 8; i = i + 1) begin
                    #(bfm_bit_ns);
                    b[i] = bfm_tx;
                end
                #(bfm_bit_ns);
                ok = (bfm_tx === 1'b1);
            end
        end
    end
endtask

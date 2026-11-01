# B-10 · Debug Unit: FSM base, `system.v` y comandos `V`, `X`, errores

`M` · etiquetas `debug-unit` · milestone M2 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo
`debug_unit.v` con el esqueleto completo (registros, motor de TX valid/ready, byte pendiente, contador de ciclos) que atiende `V`, `X`, comandos desconocidos y dos comandos seguidos; `system.v` armado; TB `tb_debug_unit` con la infraestructura que usan B-11 a B-16.

## Antes de empezar
- Leer: `protocolo.md` (completo), `interfaz_cpu.md` §6 y §7, `convenciones.md` §4 y §5, `decisiones.md` D-14 y D-22.
- Precondiciones: B-03 (`rtl/uart/uart_if.v`), B-04 (`tb/common/uart_bfm.svh`, `tools/run.py`), B-09 (`cpu_stub.v`, `imem.v`, vectores).
- Puertos de `uart_if` que se asumen (B-03 + D-08 + D-14): `i_clock, i_reset, i_rx, o_tx, i_tx_start, i_tx_data[7:0], o_tx_busy, o_rx_valid, o_rx_data[7:0], o_rx_frame_err`, parámetros `CLOCK_FREQ`, `BAUD_RATE`. Si `uart_if.v` tiene otros nombres, **detenerse y avisar**.
- API de la BFM que se asume (B-04): el TB declara `reg bfm_rx = 1'b1; wire bfm_tx;` antes del `` `include "uart_bfm.svh" ``; la BFM declara `real bfm_bit_ns, bfm_gap_ns, bfm_timeout_ns;`, `task automatic bfm_send_byte(input [7:0] b);` y `task automatic bfm_recv_byte(output [7:0] b, output reg ok);` (`ok = 0` si no llegó start antes de `bfm_timeout_ns` o el stop vino en 0).
- Rama: `b/B-10-fsm-base`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/debug_unit.v` | Paso 1 |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/system.v` | Paso 2 |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_debug_helpers.svh` | Paso 3 |
| crear | `TP3_FINAL/VIVADO/TP_FINAL/tb/debug/tb_debug_unit.sv` | Paso 4 |
| modificar | `TP3_FINAL/tools/tbs.py` | Paso 5 |

## Diseño de la FSM (completo; B-10 implementa solo lo marcado)

Estados (`r_state`, 4 bits). `o_state = r_state`, así los LEDs muestran el número.

| Cód. | Estado | Qué hace | Issue |
| --- | --- | --- | --- |
| 0 | `S_IDLE` | Toma un comando (pendiente o recién llegado) y despacha | B-10 |
| 1 | `S_RESP` | Envía `r_resp_len` bytes de `r_resp` (byte 0 en `[7:0]`) y va a `r_ret_state` | B-10 |
| 2 | `S_STEP` | `cpu_en` estuvo 1 un flanco; lo baja y arranca el dump | B-11 |
| 3 | `S_RUN` | `cpu_en` = 1 hasta halted / `A` / timeout | B-12 |
| 4 | `S_LOAD_N` | Recibe `NL`, `NH` | B-13 |
| 5 | `S_LOAD_DATA` | Recibe `N` palabras y las escribe en imem | B-13 |
| 6 | `S_LOAD_FILL` | Escribe HALT en `imem[N..255]` | B-13 |
| 7 | `S_DUMP_COUNT` | Primera pasada: cuenta palabras sucias (256 ciclos) | B-14 |
| 8 | `S_DUMP_HDR` | Envía `0xA5` | B-14 |
| 9 | `S_DUMP_WORD` | Carga la palabra fija `r_widx` en `r_word` | B-14 |
| 10 | `S_DUMP_BYTES` | Envía los 4 bytes de `r_word` y suma checksum | B-14 |
| 11 | `S_DUMP_SEEK` | Busca la siguiente palabra sucia | B-14 |
| 12 | `S_DUMP_CSUM` | Envía el checksum y vuelve a reposo | B-14 |

Motor de TX (todos los estados que envían usan este patrón; nunca otro):

```verilog
// w_tx_accept = r_tx_valid & ~i_tx_busy  (el byte entra a uart_tx en este flanco)
if (!r_tx_valid) begin
    r_tx_valid <= 1'b1;
    r_tx_data  <= <byte a enviar>;
end else if (w_tx_accept) begin
    r_tx_valid <= 1'b0;
    <avanzar: siguiente byte o siguiente estado>
end
```

Byte pendiente (protocolo.md §2): un estado "consume" bytes si es `S_RUN`, `S_LOAD_N`, `S_LOAD_DATA`, o `S_IDLE` sin pendiente. En cualquier otro caso un byte recibido que no sea `A` va al pendiente si está libre (o si en ese mismo ciclo `S_IDLE` lo está consumiendo); si está ocupado se descarta y `o_overrun` pulsa 1 ciclo. `A` fuera de `S_RUN` siempre se descarta.

Contador de ciclos (`r_cycles`, W1 del dump): bloque propio; se pone en 0 con `i_reset` u `o_cpu_rst`, y suma 1 en cada flanco con `r_cpu_en && !i_cpu_halted` (D-25).

`o_cpu_rst = r_cpu_rst_pulse | r_load_active`: el pulso de 1 ciclo lo usa `X`; `r_load_active` lo sostiene durante toda la carga (B-13).

## Pasos
1. `rtl/debug/debug_unit.v` — escribir exactamente esto. Las marcas `// B-1x:` quedan como comentario; las completan los issues siguientes.

```verilog
`timescale 1ns/1ps
`default_nettype none

// Debug Unit: atiende el protocolo UART v1 (protocolo.md) y controla el CPU por
// clock enable. Formato del dump en dump.md.
module debug_unit #(
    parameter BYTE_TIMEOUT = 5_000_000,
    parameter RUN_TIMEOUT  = 150_000_000
)(
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_rx_valid,
    input  wire [7:0]  i_rx_data,
    output wire        o_tx_start,
    output wire [7:0]  o_tx_data,
    input  wire        i_tx_busy,
    output wire        o_cpu_rst,
    output wire        o_cpu_en,
    input  wire        i_cpu_halted,
    output wire [4:0]  o_dbg_reg_addr,
    input  wire [31:0] i_dbg_reg_data,
    output wire [3:0]  o_dbg_latch_sel,
    input  wire [31:0] i_dbg_latch_word,
    output wire [7:0]  o_dbg_mem_addr,
    input  wire [31:0] i_dbg_mem_data,
    input  wire        i_dbg_mem_dirty,
    input  wire [31:0] i_dbg_pc,
    output wire        o_imem_we,
    output wire [7:0]  o_imem_waddr,
    output wire [31:0] o_imem_wdata,
    output wire [3:0]  o_state,
    output wire        o_overrun
);
    localparam [7:0] CMD_VERSION = 8'h56, CMD_RESET = 8'h58, CMD_LOAD  = 8'h4C,
                     CMD_STEP    = 8'h53, CMD_RUN   = 8'h52, CMD_ABORT = 8'h41,
                     CMD_DUMP    = 8'h44;
    localparam [7:0] RESP_OK = 8'h4B, RESP_ERR = 8'h45, DUMP_HEADER = 8'hA5;
    localparam [7:0] ERR_UNKNOWN = 8'h01, ERR_N_RANGE = 8'h02, ERR_TIMEOUT = 8'h03;
    localparam [31:0] HALT_WORD = 32'h0000_0073;

    localparam [3:0] S_IDLE       = 4'd0,  S_RESP       = 4'd1,  S_STEP       = 4'd2,
                     S_RUN        = 4'd3,  S_LOAD_N     = 4'd4,  S_LOAD_DATA  = 4'd5,
                     S_LOAD_FILL  = 4'd6,  S_DUMP_COUNT = 4'd7,  S_DUMP_HDR   = 4'd8,
                     S_DUMP_WORD  = 4'd9,  S_DUMP_BYTES = 4'd10, S_DUMP_SEEK  = 4'd11,
                     S_DUMP_CSUM  = 4'd12;

    reg [3:0]  r_state;
    reg [3:0]  r_ret_state;      // a dónde vuelve S_RESP
    // TX
    reg        r_tx_valid;
    reg [7:0]  r_tx_data;
    // respuesta corta: byte 0 en [7:0]
    reg [47:0] r_resp;
    reg [2:0]  r_resp_len;
    // byte pendiente
    reg        r_pend_valid;
    reg [7:0]  r_pend_data;
    reg        r_overrun;
    // control del CPU
    reg        r_cpu_en;
    reg        r_cpu_rst_pulse;
    reg        r_load_active;
    reg [31:0] r_cycles;
    reg        r_timeout;
    reg        r_aborted;
    reg [31:0] r_run_cnt;
    // carga
    reg [15:0] r_n;
    reg        r_n_high;         // 0: espera NL, 1: espera NH
    reg [8:0]  r_lidx;           // palabra de imem que se escribe (0..256)
    reg [1:0]  r_lbyte;          // byte dentro de la palabra
    reg [23:0] r_wbuf;           // bytes 0..2 de la palabra en curso
    reg [31:0] r_to_cnt;         // timeout entre bytes
    reg        r_imem_we;
    reg [7:0]  r_imem_waddr;
    reg [31:0] r_imem_wdata;
    // dump
    reg [5:0]  r_widx;           // palabra fija 0..51
    reg [8:0]  r_maddr;          // palabra de dmem 0..256
    reg [8:0]  r_mcount;         // M
    reg [31:0] r_word;
    reg [1:0]  r_bidx;
    reg [1:0]  r_wkind;          // 0: fija, 1: dirección de un par, 2: dato de un par
    reg [7:0]  r_csum;

    wire       w_tx_accept = r_tx_valid & ~i_tx_busy;
    wire       w_cmd_valid = r_pend_valid | i_rx_valid;
    wire [7:0] w_cmd       = r_pend_valid ? r_pend_data : i_rx_data;
    wire       w_consumes  = (r_state == S_RUN) || (r_state == S_LOAD_N) ||
                             (r_state == S_LOAD_DATA) ||
                             (r_state == S_IDLE && !r_pend_valid);

    // Palabra fija W0..W51 del dump (dump.md §1). Combinacional.
    wire [5:0] w_reg_idx   = r_widx - 6'd3;
    wire [5:0] w_latch_idx = r_widx - 6'd35;
    reg  [31:0] w_fixed_word;
    always @(*) begin
        w_fixed_word = 32'd0;
        if (r_widx == 6'd0)
            w_fixed_word = {16'd0, 8'h01, 5'd0, r_aborted, r_timeout, i_cpu_halted};
        else if (r_widx == 6'd1)
            w_fixed_word = r_cycles;
        else if (r_widx == 6'd2)
            w_fixed_word = i_dbg_pc;
        else if (r_widx <= 6'd34)
            w_fixed_word = i_dbg_reg_data;
        else if (r_widx <= 6'd50)
            w_fixed_word = i_dbg_latch_word;
        else
            w_fixed_word = {23'd0, r_mcount};
    end

    // Ciclos ejecutados desde el último reset del CPU (D-25)
    always @(posedge i_clock) begin
        if (i_reset || o_cpu_rst) begin
            r_cycles <= 32'd0;
        end else if (r_cpu_en && !i_cpu_halted) begin
            r_cycles <= r_cycles + 32'd1;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_state         <= S_IDLE;
            r_ret_state     <= S_IDLE;
            r_tx_valid      <= 1'b0;
            r_tx_data       <= 8'd0;
            r_resp          <= 48'd0;
            r_resp_len      <= 3'd0;
            r_pend_valid    <= 1'b0;
            r_pend_data     <= 8'd0;
            r_overrun       <= 1'b0;
            r_cpu_en        <= 1'b0;
            r_cpu_rst_pulse <= 1'b0;
            r_load_active   <= 1'b0;
            r_timeout       <= 1'b0;
            r_aborted       <= 1'b0;
            r_run_cnt       <= 32'd0;
            r_n             <= 16'd0;
            r_n_high        <= 1'b0;
            r_lidx          <= 9'd0;
            r_lbyte         <= 2'd0;
            r_wbuf          <= 24'd0;
            r_to_cnt        <= 32'd0;
            r_imem_we       <= 1'b0;
            r_imem_waddr    <= 8'd0;
            r_imem_wdata    <= 32'd0;
            r_widx          <= 6'd0;
            r_maddr         <= 9'd0;
            r_mcount        <= 9'd0;
            r_word          <= 32'd0;
            r_bidx          <= 2'd0;
            r_wkind         <= 2'd0;
            r_csum          <= 8'd0;
        end else begin
            // pulsos de un ciclo
            r_overrun       <= 1'b0;
            r_cpu_rst_pulse <= 1'b0;
            r_imem_we       <= 1'b0;

            case (r_state)
            S_IDLE: begin
                if (w_cmd_valid) begin
                    r_pend_valid <= 1'b0;          // si vino del pendiente, se consumió
                    case (w_cmd)
                    CMD_VERSION: begin
                        r_resp      <= 48'h01_00_01_00_01_56;   // 56 01 00 01 00 01
                        r_resp_len  <= 3'd6;
                        r_ret_state <= S_IDLE;
                        r_state     <= S_RESP;
                    end
                    CMD_RESET: begin
                        r_cpu_rst_pulse <= 1'b1;
                        r_timeout       <= 1'b0;
                        r_aborted       <= 1'b0;
                        r_resp          <= {40'd0, RESP_OK};
                        r_resp_len      <= 3'd1;
                        r_ret_state     <= S_IDLE;
                        r_state         <= S_RESP;
                    end
                    CMD_ABORT: begin
                        // fuera de R se ignora (protocolo.md §2, regla 5)
                    end
                    // B-11: CMD_STEP
                    // B-12: CMD_RUN
                    // B-13: CMD_LOAD
                    // B-14: CMD_DUMP
                    default: begin
                        r_resp      <= {32'd0, ERR_UNKNOWN, RESP_ERR};
                        r_resp_len  <= 3'd2;
                        r_ret_state <= S_IDLE;
                        r_state     <= S_RESP;
                    end
                    endcase
                end
            end

            S_RESP: begin
                if (!r_tx_valid) begin
                    r_tx_valid <= 1'b1;
                    r_tx_data  <= r_resp[7:0];
                end else if (w_tx_accept) begin
                    r_tx_valid <= 1'b0;
                    r_resp     <= r_resp >> 8;
                    r_resp_len <= r_resp_len - 3'd1;
                    if (r_resp_len == 3'd1) begin
                        r_state  <= r_ret_state;
                        r_to_cnt <= 32'd0;
                    end
                end
            end

            // B-11: S_STEP
            // B-12: S_RUN
            // B-13: S_LOAD_N, S_LOAD_DATA, S_LOAD_FILL
            // B-14: S_DUMP_COUNT, S_DUMP_HDR, S_DUMP_WORD, S_DUMP_BYTES, S_DUMP_SEEK, S_DUMP_CSUM

            default: begin
                r_state <= S_IDLE;
            end
            endcase

            // Byte pendiente: va después del case para ganarle a sus asignaciones
            if (i_rx_valid && !w_consumes && i_rx_data != CMD_ABORT) begin
                if (!r_pend_valid || r_state == S_IDLE) begin
                    r_pend_valid <= 1'b1;
                    r_pend_data  <= i_rx_data;
                end else begin
                    r_overrun <= 1'b1;
                end
            end
        end
    end

    assign o_tx_start      = r_tx_valid;
    assign o_tx_data       = r_tx_data;
    assign o_cpu_en        = r_cpu_en;
    assign o_cpu_rst       = r_cpu_rst_pulse | r_load_active;
    assign o_dbg_reg_addr  = w_reg_idx[4:0];
    assign o_dbg_latch_sel = w_latch_idx[3:0];
    assign o_dbg_mem_addr  = r_maddr[7:0];
    assign o_imem_we       = r_imem_we;
    assign o_imem_waddr    = r_imem_waddr;
    assign o_imem_wdata    = r_imem_wdata;
    assign o_state         = r_state;
    assign o_overrun       = r_overrun;
endmodule

`default_nettype wire
```

   Verificar: `iverilog -g2012 -Wall -o TP3_FINAL/build/du.vvp TP3_FINAL/VIVADO/TP_FINAL/rtl/debug/debug_unit.v` compila (warnings de registros sin uso: aceptables hasta B-14).

2. `rtl/debug/system.v`: encabezado y parámetros exactamente como `interfaz_cpu.md` §7. Contenido:
   - Cables `w_rx_valid`, `w_rx_data[7:0]`, `w_rx_frame_err`, `w_tx_start`, `w_tx_data[7:0]`, `w_tx_busy`, `w_dbg_cpu_rst`, `w_cpu_en`, `w_cpu_halted`, `w_dbg_reg_addr[4:0]`, `w_dbg_reg_data[31:0]`, `w_dbg_latch_sel[3:0]`, `w_dbg_latch_word[31:0]`, `w_dbg_mem_addr[7:0]`, `w_dbg_mem_data[31:0]`, `w_dbg_mem_dirty`, `w_dbg_pc[31:0]`, `w_imem_addr[31:0]`, `w_imem_data[31:0]`, `w_imem_we`, `w_imem_waddr[7:0]`, `w_imem_wdata[31:0]`, `w_state[3:0]`, `w_overrun`.
   - `wire w_cpu_reset = i_reset | w_dbg_cpu_rst;`
   - `uart_if #(.CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(BAUD_RATE)) u_uart (...)`.
   - `debug_unit #(.BYTE_TIMEOUT(BYTE_TIMEOUT), .RUN_TIMEOUT(RUN_TIMEOUT)) u_debug (...)`, con `.i_reset(i_reset)` (no `w_cpu_reset`).
   - Entre `` `ifdef CPU_STUB `` / `` `else `` / `` `endif ``: `cpu_stub #(.HALT_AT(HALT_AT)) u_cpu (...)` y `cpu u_cpu (...)` con la **misma** lista de conexiones (`.i_clock(i_clock), .i_reset(w_cpu_reset), .i_en(w_cpu_en), .o_halted(w_cpu_halted), .o_imem_addr(w_imem_addr), .i_imem_data(w_imem_data), ...`).
   - `imem u_imem (.i_clock(i_clock), .i_raddr(w_imem_addr[9:2]), .o_rdata(w_imem_data), .i_we(w_imem_we), .i_waddr(w_imem_waddr), .i_wdata(w_imem_wdata));`
   - LEDs: tres registros con reset `i_reset`: `r_led_rx` conmuta con `w_rx_valid`; `r_led_frame` y `r_led_overrun` se ponen en 1 con `w_rx_frame_err` / `w_overrun` y solo los baja `i_reset`. `assign o_leds = {w_state, w_cpu_halted, r_led_overrun, r_led_frame, r_led_rx};`
   - Estilo de `convenciones.md` §4.

3. `tb/debug/tb_debug_helpers.svh`: tareas comunes que se incluyen **dentro** del módulo TB, después de `uart_bfm.svh`. Requiere que el TB declare `clk`, `errors`, `checks` y la instancia `dut` (de `system`). Contenido exacto de las tareas (completar los cuerpos tal como se describe):

```systemverilog
`define VEC_DIR "TP3_FINAL/VIVADO/TP_FINAL/tb/debug/vectors/"

reg  [7:0] q_tx  [0:2047];   // bytes a enviar
integer    n_tx;
reg  [7:0] q_rx  [0:4095];   // bytes recibidos
integer    n_rx;
reg  [7:0] q_exp [0:4095];   // bytes esperados
integer    n_exp;
integer    log_fd = 0;       // B-16 lo abre; 0 = no se loguea

task automatic q_clear;            // n_tx = 0; n_exp = 0
task automatic q_push(input [7:0] b);   // q_tx[n_tx++] = b
task automatic exp_push(input [7:0] b); // q_exp[n_exp++] = b
task automatic log_step(input string name);   // si log_fd: $fwrite(log_fd, "# %s\n", name)

// Envía q_tx[0..n_tx-1] sin pausa; si log_fd != 0 escribe "> xx\n" por byte (hex minúscula)
task automatic send_all;
// Recibe n bytes en q_rx; si un bfm_recv_byte vuelve con ok = 0: errors++,
// $display("FAIL recv: byte %0d de %0d no llegó", i, n) y corta. Loguea "< xx\n".
task automatic recv_n(input integer n);
// fork send_all; recv_n(n); join
task automatic transact(input integer n);
// Compara q_rx[0..n_exp-1] con q_exp; una línea FAIL por byte distinto
// ("FAIL <caso>: byte %0d exp=%02h got=%02h"), checks++ por byte
task automatic check_exp(input string caso);
// Agrega un vector al final de lo esperado:
// $readmemh($sformatf("%s%s", `VEC_DIR, fname), q_exp, n_exp); n_exp = n_exp + n
// (Icarus avisa "not enough words" porque el archivo no llena el arreglo: es esperado)
task automatic exp_vec(input string fname, input integer n);
// n_exp = 0; exp_vec(fname, n); check_exp(caso)
task automatic check_vec(input string fname, input integer n, input string caso);
// Espera t_ns y verifica que no empezó ningún byte en bfm_tx (si hubo start: FAIL)
task automatic expect_silence(input real t_ns, input string caso);
```

   `expect_silence` se implementa con un `bfm_recv_byte` con `bfm_timeout_ns = t_ns` (restaurar el valor anterior al terminar) y fallo si `ok = 1`.

4. `tb/debug/tb_debug_unit.sv`:

```systemverilog
`timescale 1ns/1ps

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

    initial begin #(200_000_000); $fatal(1, "FAIL tb_debug_unit: watchdog"); end

    initial begin
        bfm_bit_ns     = 640.0;
        bfm_gap_ns     = 0.0;
        bfm_timeout_ns = 2_000_000.0;
        repeat (10) @(negedge clk);
        rst = 1'b0;
        repeat (10) @(negedge clk);

        if (HALT_AT == 20) begin
            // casos B-10 (abajo), luego B-14, B-11, B-15, B-12 (parte h20), B-13
        end else begin
            // casos B-12 (parte h0)
        end

        if (errors != 0) $fatal(1, "FAIL tb_debug_unit_h%0d: %0d errores", HALT_AT, errors);
        $display("PASS tb_debug_unit_h%0d: %0d chequeos", HALT_AT, checks);
        $finish;
    end
endmodule
```

   Casos de B-10 (en este orden, dentro de `HALT_AT == 20`). Cada uno: `q_clear`, `q_push` de lo que manda el host, `exp_push` de lo esperado, `transact(n_exp)`, `check_exp("<caso>")`:

| Caso | Host envía | Esperado | Chequeo extra |
| --- | --- | --- | --- |
| `V` | `56` | `56 01 00 01 00 01` | — |
| `X` | `58` | `4B` | `rst_cycles` aumentó exactamente 1 y `en_cycles` no cambió (guardar ambos antes) |
| `desconocido` | `7A` | `45 01` | — |
| `A en reposo` | `41` | nada | `expect_silence(20_000.0, "A en reposo")`; luego caso `V` de nuevo → `56 01 00 01 00 01` |
| `X X seguidos` | `58 58` | `4B 4B` | `rst_cycles` aumentó 2 |
| `V V seguidos` | `56 56` | `56 01 00 01 00 01 56 01 00 01 00 01` | el segundo `V` pasa por el pendiente |
| `V V V seguidos` | `56 56 56` | 12 bytes (dos respuestas `V`) | después `expect_silence(20_000.0, ...)` y `leds[2] == 1` (overrun pegajoso) |

   Para el último caso: tras el `transact`, verificar `leds[2]` en un negedge; `checks++`.

5. `tools/tbs.py`: dos entradas con el mismo TB. Lista común de archivos (desde la raíz):
   `rtl/uart/baud_gen.v`, `rtl/uart/uart_rx.v`, `rtl/uart/uart_tx.v`, `rtl/uart/uart_if.v`, `rtl/debug/debug_unit.v`, `rtl/debug/cpu_stub.v`, `rtl/debug/imem.v`, `rtl/debug/system.v`, `tb/debug/tb_debug_unit.sv` (todas bajo `TP3_FINAL/VIVADO/TP_FINAL/`).

```python
"tb_debug_unit_h20": {"top": "tb_debug_unit", "files": DEBUG_FILES,
                      "defines": {"CPU_STUB": "1"}, "params": {"HALT_AT": 20},
                      "incdirs": ["TP3_FINAL/VIVADO/TP_FINAL/tb/common"]},
"tb_debug_unit_h0":  {"top": "tb_debug_unit", "files": DEBUG_FILES,
                      "defines": {"CPU_STUB": "1"}, "params": {"HALT_AT": 0},
                      "incdirs": ["TP3_FINAL/VIVADO/TP_FINAL/tb/common"]},
```

   `uart_bfm.svh` vive en `tb/common/`, que no es el directorio de ningún archivo de la lista. Si `run.py` de B-04 todavía no soporta la clave opcional `incdirs`, agregarla: cada elemento se pasa como `-I <dir>` además de los directorios de los archivos.

## Validación
```
py TP3_FINAL/tools/run.py tb tb_debug_unit_h20 → "PASS tb_debug_unit_h20: N chequeos", código 0
py TP3_FINAL/tools/run.py tb tb_debug_unit_h0  → "PASS tb_debug_unit_h0: 0 chequeos" (todavía sin casos)
py TP3_FINAL/tools/run.py synth_ooc debug_unit → sin latch / multi-driven / implicit net
py TP3_FINAL/tools/run.py test → código 0
```
Prueba de detección (no se commitea): cambiar `48'h01_00_01_00_01_56` por `48'h02_00_01_00_01_56` → el TB falla en `V`; revertir.

## Listo cuando
- [ ] `X`, `V` y un comando inválido devuelven exactamente los bytes de `protocolo.md` §7.
- [ ] Con `X`, `o_cpu_rst` dura 1 ciclo y `o_cpu_en` no se mueve.
- [ ] Dos comandos seguidos sin pausa se atienden los dos (`X X`, `V V`); un tercero con el pendiente ocupado prende el LED de overrun.
- [ ] `A` en reposo no produce respuesta.
- [ ] Síntesis OOC limpia.

## No hacer
- No implementar todavía `S`, `R`, `L`, `D` (quedan en `default` → `45 01`; los TB de B-10 no los mandan).
- No agregar FIFO ni cambiar el motor de TX.
- No sincronizar `i_reset` dentro de `debug_unit` ni de `system`.

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| Se recibe cada byte dos veces | `o_tx_start` no baja en el ciclo de aceptación: revisar el patrón del motor de TX |
| Falta el primer byte de una respuesta | El receptor del TB empezó tarde: usar `transact` (fork), no `send_all` seguido de `recv_n` |
| `V V` devuelve solo una respuesta | El bloque del pendiente está antes del `case` (tiene que estar después) |
| `dut.u_debug...` no existe | Nombres de instancia de `system.v` (`u_uart`, `u_debug`, `u_cpu`, `u_imem`) |
| Puertos de `uart_if` distintos a los asumidos | Detenerse y avisar (no adaptar `uart_if`) |

## Commits
1. `debug: esqueleto de debug_unit con V, X y errores`
2. `debug: system.v con stub`
3. `debug: tb_debug_unit y helpers`

## Depende de / bloquea
Depende de: B-03, B-04, B-06, B-09. Bloquea: B-11 a B-16. Orden obligatorio en M2 (cada TB agrega casos detrás de los anteriores y parte del estado que estos dejan): B-10 → B-14 → B-11 → B-12 → B-13 → B-15 → B-16 → B-17.

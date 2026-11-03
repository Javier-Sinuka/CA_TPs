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
                    CMD_DUMP: begin
                        r_maddr  <= 9'd0;
                        r_mcount <= 9'd0;
                        r_state  <= S_DUMP_COUNT;
                    end
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
            S_DUMP_COUNT: begin
                // primera pasada: M = cantidad de palabras sucias
                if (i_dbg_mem_dirty) begin
                    r_mcount <= r_mcount + 9'd1;
                end
                if (r_maddr == 9'd255) begin
                    r_maddr <= 9'd0;
                    r_state <= S_DUMP_HDR;
                end else begin
                    r_maddr <= r_maddr + 9'd1;
                end
            end

            S_DUMP_HDR: begin
                if (!r_tx_valid) begin
                    r_tx_valid <= 1'b1;
                    r_tx_data  <= DUMP_HEADER;
                end else if (w_tx_accept) begin
                    r_tx_valid <= 1'b0;
                    r_csum     <= 8'd0;
                    r_widx     <= 6'd0;
                    r_state    <= S_DUMP_WORD;
                end
            end

            S_DUMP_WORD: begin
                r_word  <= w_fixed_word;
                r_bidx  <= 2'd0;
                r_wkind <= 2'd0;
                r_state <= S_DUMP_BYTES;
            end

            S_DUMP_BYTES: begin
                if (!r_tx_valid) begin
                    r_tx_valid <= 1'b1;
                    r_tx_data  <= r_word[7:0];
                end else if (w_tx_accept) begin
                    r_tx_valid <= 1'b0;
                    r_csum     <= r_csum + r_tx_data;
                    r_word     <= r_word >> 8;
                    r_bidx     <= r_bidx + 2'd1;
                    if (r_bidx == 2'd3) begin
                        case (r_wkind)
                        2'd0: begin
                            if (r_widx == 6'd51) begin
                                r_maddr <= 9'd0;
                                r_state <= S_DUMP_SEEK;
                            end else begin
                                r_widx  <= r_widx + 6'd1;
                                r_state <= S_DUMP_WORD;
                            end
                        end
                        2'd1: begin
                            // terminó la dirección: sigue el dato de la misma palabra
                            r_word  <= i_dbg_mem_data;
                            r_wkind <= 2'd2;
                        end
                        default: begin
                            r_maddr <= r_maddr + 9'd1;
                            r_state <= S_DUMP_SEEK;
                        end
                        endcase
                    end
                end
            end

            S_DUMP_SEEK: begin
                // segunda pasada: próxima palabra sucia, en orden ascendente
                if (r_maddr[8]) begin
                    r_state <= S_DUMP_CSUM;
                end else if (i_dbg_mem_dirty) begin
                    r_word  <= {22'd0, r_maddr[7:0], 2'b00};   // dirección en bytes
                    r_wkind <= 2'd1;
                    r_bidx  <= 2'd0;
                    r_state <= S_DUMP_BYTES;
                end else begin
                    r_maddr <= r_maddr + 9'd1;
                end
            end

            S_DUMP_CSUM: begin
                if (!r_tx_valid) begin
                    r_tx_valid <= 1'b1;
                    r_tx_data  <= r_csum;
                end else if (w_tx_accept) begin
                    r_tx_valid <= 1'b0;
                    r_state    <= S_IDLE;
                end
            end

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

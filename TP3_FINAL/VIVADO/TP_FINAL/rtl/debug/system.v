`timescale 1ns/1ps
`default_nettype none

// Todo lo que no es reloj ni pines: UART + Debug Unit + CPU + imem + LEDs
// (interfaz_cpu.md §7). Es lo que simulan los TB. Con CPU_STUB usa cpu_stub.
module system #(
    parameter CLOCK_FREQ   = 50_000_000,
    parameter BAUD_RATE    = 115_200,
    parameter BYTE_TIMEOUT = CLOCK_FREQ / 10,
    parameter RUN_TIMEOUT  = 150_000_000,
    parameter HALT_AT      = 20              // solo lo usa cpu_stub
)(
    input  wire       i_clock,
    input  wire       i_reset,
    input  wire       i_rx,
    output wire       o_tx,
    output wire [7:0] o_leds
);
    wire        w_rx_valid;
    wire [7:0]  w_rx_data;
    wire        w_rx_frame_err;
    wire        w_tx_start;
    wire [7:0]  w_tx_data;
    wire        w_tx_busy;
    wire        w_dbg_cpu_rst;
    wire        w_cpu_en;
    wire        w_cpu_halted;
    wire [4:0]  w_dbg_reg_addr;
    wire [31:0] w_dbg_reg_data;
    wire [3:0]  w_dbg_latch_sel;
    wire [31:0] w_dbg_latch_word;
    wire [7:0]  w_dbg_mem_addr;
    wire [31:0] w_dbg_mem_data;
    wire        w_dbg_mem_dirty;
    wire [31:0] w_dbg_pc;
    wire [31:0] w_imem_addr;
    wire [31:0] w_imem_data;
    wire        w_imem_we;
    wire [7:0]  w_imem_waddr;
    wire [31:0] w_imem_wdata;
    wire [3:0]  w_state;
    wire        w_overrun;

    wire w_cpu_reset = i_reset | w_dbg_cpu_rst;

    uart_if #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_rx(i_rx),
        .o_tx(o_tx),
        .i_tx_start(w_tx_start),
        .i_tx_data(w_tx_data),
        .o_tx_busy(w_tx_busy),
        .o_rx_valid(w_rx_valid),
        .o_rx_data(w_rx_data),
        .o_rx_frame_err(w_rx_frame_err)
    );

    debug_unit #(
        .BYTE_TIMEOUT(BYTE_TIMEOUT),
        .RUN_TIMEOUT(RUN_TIMEOUT)
    ) u_debug (
        .i_clock(i_clock),
        .i_reset(i_reset),
        .i_rx_valid(w_rx_valid),
        .i_rx_data(w_rx_data),
        .o_tx_start(w_tx_start),
        .o_tx_data(w_tx_data),
        .i_tx_busy(w_tx_busy),
        .o_cpu_rst(w_dbg_cpu_rst),
        .o_cpu_en(w_cpu_en),
        .i_cpu_halted(w_cpu_halted),
        .o_dbg_reg_addr(w_dbg_reg_addr),
        .i_dbg_reg_data(w_dbg_reg_data),
        .o_dbg_latch_sel(w_dbg_latch_sel),
        .i_dbg_latch_word(w_dbg_latch_word),
        .o_dbg_mem_addr(w_dbg_mem_addr),
        .i_dbg_mem_data(w_dbg_mem_data),
        .i_dbg_mem_dirty(w_dbg_mem_dirty),
        .i_dbg_pc(w_dbg_pc),
        .o_imem_we(w_imem_we),
        .o_imem_waddr(w_imem_waddr),
        .o_imem_wdata(w_imem_wdata),
        .o_state(w_state),
        .o_overrun(w_overrun)
    );

`ifdef CPU_STUB
    cpu_stub #(
        .HALT_AT(HALT_AT)
    ) u_cpu (
        .i_clock(i_clock),
        .i_reset(w_cpu_reset),
        .i_en(w_cpu_en),
        .o_halted(w_cpu_halted),
        .o_imem_addr(w_imem_addr),
        .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(w_dbg_reg_addr),
        .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(w_dbg_latch_sel),
        .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(w_dbg_mem_addr),
        .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty),
        .o_dbg_pc(w_dbg_pc)
    );
`else
    cpu u_cpu (
        .i_clock(i_clock),
        .i_reset(w_cpu_reset),
        .i_en(w_cpu_en),
        .o_halted(w_cpu_halted),
        .o_imem_addr(w_imem_addr),
        .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(w_dbg_reg_addr),
        .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(w_dbg_latch_sel),
        .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(w_dbg_mem_addr),
        .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty),
        .o_dbg_pc(w_dbg_pc)
    );
`endif

    imem u_imem (
        .i_clock(i_clock),
        .i_raddr(w_imem_addr[9:2]),
        .o_rdata(w_imem_data),
        .i_we(w_imem_we),
        .i_waddr(w_imem_waddr),
        .i_wdata(w_imem_wdata)
    );

    // LEDs: el de RX conmuta con cada byte; framing y overrun quedan pegados hasta i_reset
    reg r_led_rx;
    reg r_led_frame;
    reg r_led_overrun;

    always @(posedge i_clock) begin
        if (i_reset) begin
            r_led_rx      <= 1'b0;
            r_led_frame   <= 1'b0;
            r_led_overrun <= 1'b0;
        end else begin
            if (w_rx_valid)     r_led_rx      <= ~r_led_rx;
            if (w_rx_frame_err) r_led_frame   <= 1'b1;
            if (w_overrun)      r_led_overrun <= 1'b1;
        end
    end

    assign o_leds = {w_state, w_cpu_halted, r_led_overrun, r_led_frame, r_led_rx};
endmodule

`default_nettype wire

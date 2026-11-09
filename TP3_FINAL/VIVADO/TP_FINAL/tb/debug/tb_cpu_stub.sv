`timescale 1ns/1ps
`define VEC_DIR "TP3_FINAL/VIVADO/TP_FINAL/tb/debug/vectors/"

// Compara cpu_stub contra los vectores de stub_model.py (B-09). Dos instancias
// con las mismas entradas: u_h20 (HALT_AT = 20) y u_h0 (HALT_AT = 0).
module tb_cpu_stub;
    reg clk = 1'b0;
    always #10 clk = ~clk;                        // 50 MHz

    reg        rst = 1'b1, en = 1'b0;
    reg [4:0]  reg_addr = 5'd0;
    reg [3:0]  latch_sel = 4'd0;
    reg [7:0]  mem_addr = 8'd0;

    wire        w20_halted, w0_halted;
    wire [31:0] w20_imem_addr, w0_imem_addr;
    wire [31:0] w20_reg_data, w0_reg_data;
    wire [31:0] w20_latch_word, w0_latch_word;
    wire [31:0] w20_mem_data, w0_mem_data;
    wire        w20_mem_dirty, w0_mem_dirty;
    wire [31:0] w20_pc, w0_pc;

    cpu_stub #(.HALT_AT(20)) u_h20 (
        .i_clock(clk), .i_reset(rst), .i_en(en),
        .o_halted(w20_halted),
        .o_imem_addr(w20_imem_addr), .i_imem_data(32'd0),
        .i_dbg_reg_addr(reg_addr), .o_dbg_reg_data(w20_reg_data),
        .i_dbg_latch_sel(latch_sel), .o_dbg_latch_word(w20_latch_word),
        .i_dbg_mem_addr(mem_addr), .o_dbg_mem_data(w20_mem_data),
        .o_dbg_mem_dirty(w20_mem_dirty),
        .o_dbg_pc(w20_pc)
    );

    cpu_stub #(.HALT_AT(0)) u_h0 (
        .i_clock(clk), .i_reset(rst), .i_en(en),
        .o_halted(w0_halted),
        .o_imem_addr(w0_imem_addr), .i_imem_data(32'd0),
        .i_dbg_reg_addr(reg_addr), .o_dbg_reg_data(w0_reg_data),
        .i_dbg_latch_sel(latch_sel), .o_dbg_latch_word(w0_latch_word),
        .i_dbg_mem_addr(mem_addr), .o_dbg_mem_data(w0_mem_data),
        .o_dbg_mem_dirty(w0_mem_dirty),
        .o_dbg_pc(w0_pc)
    );

    integer errors = 0, checks = 0;
    reg [31:0] exp_words [0:562];

    // en = 1 durante exactamente n flancos de subida
    task automatic run_en(input integer n);
        begin
            @(negedge clk) en = 1'b1;
            repeat (n) @(negedge clk);
            en = 1'b0;
        end
    endtask

    task automatic chk(input string fname, input integer idx, input [31:0] got);
        begin
            checks = checks + 1;
            if (got !== exp_words[idx]) begin
                errors = errors + 1;
                $display("FAIL %s[%0d]: exp=%h got=%h", fname, idx, exp_words[idx], got);
            end
        end
    endtask

    // Recorre todas las direcciones de debug de una instancia (which: 0 = u_h20,
    // 1 = u_h0) y compara contra el vector. Se llama siempre después de un negedge.
    task automatic check_state(input integer which, input string fname);
        integer i;
        begin
            $readmemh($sformatf("%s%s", `VEC_DIR, fname), exp_words);
            // [0] pc, [1] imem_addr, [2] halted
            #1;
            chk(fname, 0, which ? w0_pc        : w20_pc);
            chk(fname, 1, which ? w0_imem_addr : w20_imem_addr);
            chk(fname, 2, which ? {31'd0, w0_halted} : {31'd0, w20_halted});
            // [3..34] regs
            for (i = 0; i < 32; i = i + 1) begin
                reg_addr = i[4:0];
                #1;
                chk(fname, 3 + i, which ? w0_reg_data : w20_reg_data);
            end
            // [35..50] latches
            for (i = 0; i < 16; i = i + 1) begin
                latch_sel = i[3:0];
                #1;
                chk(fname, 35 + i, which ? w0_latch_word : w20_latch_word);
            end
            // [51..306] dirty y [307..562] dato
            for (i = 0; i < 256; i = i + 1) begin
                mem_addr = i[7:0];
                #1;
                chk(fname, 51 + i,  which ? {31'd0, w0_mem_dirty} : {31'd0, w20_mem_dirty});
                chk(fname, 307 + i, which ? w0_mem_data : w20_mem_data);
            end
        end
    endtask

    initial begin #(2_000_000); $fatal(1, "FAIL tb_cpu_stub: watchdog"); end

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        check_state(0, "stub_state_c0_h20.hex");
        run_en(1);  @(negedge clk); check_state(0, "stub_state_c1_h20.hex");
        run_en(6);  @(negedge clk); check_state(0, "stub_state_c7_h20.hex");
        run_en(13); @(negedge clk); check_state(0, "stub_state_c20_h20.hex");   // halted = 1
        run_en(5);  @(negedge clk); check_state(0, "stub_state_c20_h20.hex");   // halted congela
        repeat (3) @(negedge clk);   check_state(0, "stub_state_c20_h20.hex");   // en = 0 no cambia
        check_state(1, "stub_state_c25_h0.hex");                                  // 1+6+13+5 = 25
        @(negedge clk) rst = 1'b1; @(negedge clk) rst = 1'b0;                     // reset de 1 ciclo
        @(negedge clk); check_state(0, "stub_state_c0_h20.hex");
        if (errors != 0) $fatal(1, "FAIL tb_cpu_stub: %0d errores", errors);
        $display("PASS tb_cpu_stub: %0d chequeos", checks);
        $finish;
    end
endmodule

`timescale 1ns/1ps
`default_nettype none

module tb_cpu_no_hazard;
    localparam integer ADVANCES = 145;
    localparam integer MARKER_PC = 560;
    reg r_clock = 1'b0;
    reg r_reset = 1'b1;
    reg r_en = 1'b0;
    reg r_imem_we = 1'b0;
    reg [7:0] r_imem_waddr = 8'd0;
    reg [31:0] r_imem_wdata = 32'd0;
    reg [4:0] r_dbg_reg_addr = 5'd0;
    reg [3:0] r_dbg_latch_sel = 4'd0;
    reg [7:0] r_dbg_mem_addr = 8'd0;
    wire w_halted;
    wire [31:0] w_imem_addr, w_imem_data, w_dbg_pc;
    wire [31:0] w_dbg_reg_data, w_dbg_latch_word, w_dbg_mem_data;
    wire w_dbg_mem_dirty;
    reg [31:0] r_program [0:255];
    reg [39:0] r_golden [0:799];
    reg [31:0] r_snapshot_regs [0:31];
    reg [32:0] r_snapshot_mem [0:255];
    reg [31:0] r_snapshot_latches [0:15];
    reg [31:0] r_snapshot_pc;
    reg [31:0] r_reference_regs [0:31];
    reg [39:0] r_event;
    string r_root;
    string r_program_prefix;
    string r_output_prefix;
    integer input_file;
    integer checks = 0;
    integer errors = 0;
    integer advances;
    integer clocks;
    integer writes;
    integer stores;
    integer markers;
    integer trace_file;
    integer index;
    integer mode;
    integer stage;

    cpu u_cpu (
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .o_halted(w_halted), .o_imem_addr(w_imem_addr), .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr), .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel), .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr), .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty), .o_dbg_pc(w_dbg_pc)
    );

    imem u_imem (
        .i_clock(r_clock), .i_raddr(w_imem_addr[9:2]), .o_rdata(w_imem_data),
        .i_we(r_imem_we), .i_waddr(r_imem_waddr), .i_wdata(r_imem_wdata)
    );

    always #1000 r_clock = ~r_clock;

    task automatic check_word(input [39:0] got, input [39:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL tb_cpu_no_hazard: mode=%0d clock=%0d advance=%0d %s expected=%010h got=%010h",
                         mode, clocks, advances, label, expected, got);
            end
        end
    endtask

    task automatic scan_state(input bit compare_snapshot);
        integer n;
        begin
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n;
                #1;
                if (compare_snapshot) check_word(w_dbg_reg_data, r_snapshot_regs[n], "paused register");
                else r_snapshot_regs[n] = w_dbg_reg_data;
            end
            for (n = 0; n < 256; n = n + 1) begin
                r_dbg_mem_addr = n;
                #1;
                if (compare_snapshot) check_word({w_dbg_mem_dirty, w_dbg_mem_data}, r_snapshot_mem[n], "paused memory/dirty");
                else r_snapshot_mem[n] = {w_dbg_mem_dirty, w_dbg_mem_data};
            end
            for (n = 0; n < 16; n = n + 1) begin
                r_dbg_latch_sel = n;
                #1;
                if (compare_snapshot) check_word(w_dbg_latch_word, r_snapshot_latches[n], "paused latch");
                else r_snapshot_latches[n] = w_dbg_latch_word;
            end
            if (compare_snapshot) check_word(w_dbg_pc, r_snapshot_pc, "paused PC");
            else r_snapshot_pc = w_dbg_pc;
        end
    endtask

    task automatic check_pipeline;
        reg [31:0] expected_pc;
        reg [3:0] expected_valid;
        begin
            check_word(w_imem_addr, advances*4, "IF byte PC");
            expected_valid = 4'd0;
            for (stage = 0; stage < 4; stage = stage + 1) begin
                expected_pc = advances > stage ? (advances-stage-1)*4 : 0;
                expected_valid[stage] = advances > stage;
                casez (stage)
                    0: begin
                        check_word(u_cpu.w_pc_id, expected_pc, "ID PC");
                        check_word(u_cpu.w_valid_id, expected_valid[stage], "ID valid");
                        check_word(u_cpu.w_instr_id, advances > 0 ? r_program[advances-1] : 0, "ID instruction");
                    end
                    1: begin
                        check_word(u_cpu.w_pc_ex, expected_pc, "EX PC");
                        check_word(u_cpu.w_valid_ex, expected_valid[stage], "EX valid");
                    end
                    2: begin
                        check_word(u_cpu.w_pc_mem, expected_pc, "MEM PC");
                        check_word(u_cpu.w_valid_mem, expected_valid[stage], "MEM valid");
                    end
                    3: begin
                        check_word(u_cpu.w_pc_wb, expected_pc, "WB PC");
                        check_word(u_cpu.w_valid_wb, expected_valid[stage], "WB valid");
                    end
                endcase
            end
            r_dbg_latch_sel = 4'd15;
            #1;
            check_word(w_dbg_latch_word, expected_valid, "public valid flags");
            $fdisplay(trace_file, "%0d,%0d,%0d,%0d,%08h,%08h,%08h,%08h,%08h,%01h",
                      mode, clocks, advances, r_en, w_dbg_pc, u_cpu.w_pc_id, u_cpu.w_pc_ex,
                      u_cpu.w_pc_mem, u_cpu.w_pc_wb, expected_valid);
        end
    endtask

    task automatic run_cycle(input bit enable);
        integer n;
        reg expected_store;
        begin
            @(negedge r_clock);
            r_en = enable;
            if (!enable) scan_state(1'b0);
            @(posedge r_clock);
            clocks = clocks + 1;
            r_event = 40'd0;
            if (advances >= 4) r_event = r_golden[544+advances-4];
            check_word(u_cpu.w_regfile_we, enable && r_event[37], "commit permission");
            if (enable && r_event[37]) begin
                check_word(u_cpu.w_pc_wb, (advances-4)*4, "commit PC");
                check_word(u_cpu.w_rd_wb, r_event[36:32], "commit destination");
                check_word(u_cpu.w_wb_data, r_event[31:0], "independent commit value");
                r_reference_regs[r_event[36:32]] = r_event[31:0];
                writes = writes + 1;
                if (u_cpu.w_pc_wb == MARKER_PC) markers = markers + 1;
            end
            expected_store = advances == 91 || advances == 95 || advances == 99 || advances == 103;
            check_word(u_cpu.w_dmem_we, enable && expected_store, "store permission");
            if (enable && expected_store) stores = stores + 1;
            if (enable) advances = advances + 1;
            #1;
            check_pipeline();
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n;
                #1;
                check_word(w_dbg_reg_data, r_reference_regs[n], "architectural register at this advance");
            end
            if (!enable) scan_state(1'b1);
        end
    endtask

    task automatic finish_run;
        integer n;
        begin
            @(negedge r_clock);
            r_en = 1'b0;
            check_word(advances, ADVANCES, "bounded logical end");
            check_word(markers, 1, "exactly one marker commit");
            check_word(writes, 31, "register write count");
            check_word(stores, 4, "store count");
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n;
                #1;
                check_word(w_dbg_reg_data, r_golden[n], "final independent registers");
            end
            for (n = 0; n < 256; n = n + 1) begin
                r_dbg_mem_addr = n;
                #1;
                check_word(w_dbg_mem_data, r_golden[32+n], "final independent memory");
                check_word(w_dbg_mem_dirty, r_golden[288+n], "final independent dirty");
            end
            $display("TRACE tb_cpu_no_hazard: mode=%0d advances=%0d clocks=%0d writes=%0d stores=%0d marker_pc=%0d",
                     mode, advances, clocks, writes, stores, MARKER_PC);
        end
    endtask

    initial begin
        #2000000;
        $fatal(1, "FAIL tb_cpu_no_hazard: watchdog before bounded completion");
    end

    initial begin
        r_root = "";
        if ($value$plusargs("ROOT=%s", r_root)) begin end
        r_program_prefix = {r_root, "TP3_FINAL/programs/"};
        r_output_prefix = {r_root, "TP3_FINAL/build/a17_"};
        input_file = $fopen({r_program_prefix, "arith_no_hazard.hex"}, "r");
        if (!input_file) begin
            r_program_prefix = "";
            r_output_prefix = "a17_";
            input_file = $fopen("arith_no_hazard.hex", "r");
        end
        if (!input_file) $fatal(1, "FAIL tb_cpu_no_hazard: missing program; set +ROOT=repository/");
        $fclose(input_file);
        input_file = $fopen({r_program_prefix, "arith_no_hazard.expected.hex"}, "r");
        if (!input_file) $fatal(1, "FAIL tb_cpu_no_hazard: missing independent expected state");
        $fclose(input_file);
        $readmemh({r_program_prefix, "arith_no_hazard.hex"}, r_program);
        $readmemh({r_program_prefix, "arith_no_hazard.expected.hex"}, r_golden);
        trace_file = $fopen({r_output_prefix, "trace.csv"}, "w");
        if (!trace_file) $fatal(1, "FAIL tb_cpu_no_hazard: cannot open trace");
        $fdisplay(trace_file, "mode,clock,advance,enable,if_pc,id_pc,ex_pc,mem_pc,wb_pc,valid");
        $dumpfile({r_output_prefix, "pipeline.vcd"});
        $dumpvars(2, tb_cpu_no_hazard);
        for (index = 0; index < 256; index = index + 1) begin
            @(negedge r_clock);
            r_imem_we = 1'b1;
            r_imem_waddr = index;
            r_imem_wdata = r_program[index];
            @(posedge r_clock);
            #1;
        end
        @(negedge r_clock);
        r_imem_we = 1'b0;
        for (mode = 0; mode < 2; mode = mode + 1) begin
            r_reset = 1'b1;
            r_en = 1'b0;
            @(posedge r_clock);
            #1;
            advances = 0;
            clocks = 0;
            writes = 0;
            stores = 0;
            markers = 0;
            for (index = 0; index < 32; index = index + 1) r_reference_regs[index] = 0;
            check_pipeline();
            @(negedge r_clock);
            r_reset = 1'b0;
            if (mode == 1) repeat (3) run_cycle(1'b0);
            while (advances < ADVANCES) begin
                if (mode == 1 && (advances % 5 == 0 || advances % 7 == 0)) begin
                    run_cycle(1'b0);
                    run_cycle(1'b0);
                end
                run_cycle(1'b1);
                if (clocks > 400) $fatal(1, "FAIL tb_cpu_no_hazard: excessive physical cycles");
            end
            finish_run();
            repeat (4) run_cycle(1'b0);
        end
        $fclose(trace_file);
        if (errors != 0) $fatal(1, "FAIL tb_cpu_no_hazard: %0d errors / %0d checks", errors, checks);
        $display("PASS tb_cpu_no_hazard: %0d checks, continuous and paused, 10 R + 9 I-ALU + LUI", checks);
        $finish;
    end
endmodule

`default_nettype wire

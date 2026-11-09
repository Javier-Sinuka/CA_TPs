`timescale 1ns/1ps
`default_nettype none

module tb_cpu_step_halt;
    localparam integer STATE_WORDS = 564;
    localparam integer GOLD_WORDS = 560;
    reg r_clock = 0;
    reg r_reset = 0;
    reg r_en = 0;
    reg [31:0] r_program [0:255];
    reg [31:0] r_golden [0:4479];
    reg [31:0] r_reference [0:511][0:STATE_WORDS-1];
    reg [4:0] r_dbg_reg_addr = 0;
    reg [3:0] r_dbg_latch_sel = 0;
    reg [7:0] r_dbg_mem_addr = 0;
    wire [31:0] w_imem_addr, w_dbg_pc, w_dbg_reg_data, w_dbg_mem_data, w_dbg_latch_word;
    wire w_halted, w_dbg_mem_dirty;
    wire [31:0] w_imem_data = r_program[w_imem_addr[9:2]];
    integer checks = 0;
    integer errors = 0;
    integer program_index, mode, index, input_file, trace_file;
    integer base, advances, clocks, writes, stores, stalls, takes, retired, accepts;
    reg r_effective_advance, r_should_halt;
    string r_root, r_name, r_path, r_output;

    cpu dut (
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .o_halted(w_halted), .o_imem_addr(w_imem_addr), .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr), .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel), .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr), .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty), .o_dbg_pc(w_dbg_pc)
    );

    task automatic check_word(input [31:0] got, input [31:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                if (errors <= 30)
                    $display("FAIL tb_cpu_step_halt: program=%s mode=%0d clock=%0d advance=%0d %s expected=%08h got=%08h",
                             r_name, mode, clocks, advances, label, expected, got);
            end
        end
    endtask

    task automatic cycle(input bit enable, input bit reset);
        begin
            r_en = enable;
            r_reset = reset;
            #1;
            r_effective_advance = enable && !w_halted && !reset;
            check_word(w_halted, dut.w_valid_wb && dut.w_halt_wb, "combinational halted");
            if (!reset) begin
                check_word(dut.w_regfile_we && !r_effective_advance, 0, "write requires advance");
                check_word(dut.w_dmem_we && !r_effective_advance, 0, "store requires advance");
                if (r_effective_advance) begin
                    if (dut.w_valid_wb) retired = retired + 1;
                    if (dut.w_regfile_we) writes = writes + 1;
                    if (dut.w_dmem_we) stores = stores + 1;
                    if (dut.w_load_use_stall) stalls = stalls + 1;
                    if (dut.w_take_ex) takes = takes + 1;
                    if (dut.w_halt_accept_id) begin
                        accepts = accepts + 1;
                        check_word(dut.w_pc_id, r_golden[base], "only reachable HALT accepted");
                    end
                end
            end
            #4;
            r_clock = 1;
            #1;
            clocks = clocks + 1;
            if (reset) begin
                advances = 0; writes = 0; stores = 0; stalls = 0;
                takes = 0; retired = 0; accepts = 0;
            end else if (r_effective_advance) advances = advances + 1;
            check_word(w_halted, r_should_halt && advances == r_golden[base+1], "independent HALT cycle");
            check_word(w_dbg_pc, w_imem_addr, "public IF PC");
            if (w_halted) begin
                check_word({dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id}, 8, "HALT WB and empty younger stages");
                check_word(dut.w_pc_wb, r_golden[base], "architectural HALT PC");
                check_word(dut.w_halt_wb, 1, "WB holds HALT");
                check_word(dut.r_fetch_stopped, 1, "fetch remains stopped");
            end
            $fdisplay(trace_file, "%s,%0d,%0d,%0d,%b,%b,%b,%08h,%08h,%b%b%b%b,%0d,%0d,%0d,%0d",
                      r_name, mode, clocks, advances, enable, reset, w_halted, w_dbg_pc,
                      dut.w_pc_wb, dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id,
                      writes, stores, stalls, takes);
            #4;
            r_clock = 0;
            #1;
        end
    endtask

    task automatic observe_state(input bit save_reference);
        integer n;
        reg [31:0] value;
        reg [31:0] expected;
        begin
            for (n = 0; n < STATE_WORDS; n = n + 1) begin
                if (n >= 4 && n < 20) r_dbg_latch_sel = n - 4;
                else if (n >= 20 && n < 52) r_dbg_reg_addr = n - 20;
                else if (n >= 52) r_dbg_mem_addr = (n - 52) / 2;
                #1;
                casez (n)
                    0: value = w_dbg_pc;
                    1: value = {31'd0, dut.r_fetch_stopped};
                    2: value = {31'd0, w_halted};
                    3: value = {30'd0, dut.w_uses_rs1_ex, dut.w_uses_rs2_ex};
                    default: begin
                        if (n < 20) value = w_dbg_latch_word;
                        else if (n < 52) value = w_dbg_reg_data;
                        else if (n[0]) value = {31'd0, w_dbg_mem_dirty};
                        else value = w_dbg_mem_data;
                    end
                endcase
                if (save_reference) r_reference[advances][n] = value;
                else begin
                    expected = r_reference[advances][n];
                    if (n == 19)
                        expected[7] = !r_reference[advances][19][6] &&
                            (r_reference[advances][1] != 0 ||
                             (!r_reset && r_en && !r_reference[advances][2][0] &&
                              r_reference[advances][19][0] &&
                              r_reference[advances][5] == 32'h00000073 &&
                              !r_reference[advances][19][5]));
                    check_word(value, expected, "same complete state at same enabled cycle");
                end
            end
        end
    endtask

    task automatic check_final;
        integer n;
        begin
            check_word(advances, r_golden[base+1], "enabled cycles to completion");
            check_word(writes, r_golden[base+2], "independent register write count");
            check_word(stores, r_golden[base+3], "independent store count");
            check_word(stalls, r_golden[base+4], "independent load-use count");
            check_word(takes, r_golden[base+5], "independent taken count");
            check_word(retired, r_golden[base+6], "instructions before HALT or bounded no-HALT interval");
            check_word(accepts, r_should_halt ? 1 : 0, "HALT accepted once or absent");
            check_word(w_halted, r_should_halt, "expected stop cause");
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n[4:0];
                #1;
                check_word(w_dbg_reg_data, r_golden[base+7+n], "independent final register");
            end
            for (n = 0; n < 256; n = n + 1) begin
                r_dbg_mem_addr = n[7:0];
                #1;
                check_word(w_dbg_mem_data, r_golden[base+39+n], "independent final memory");
                check_word(w_dbg_mem_dirty, r_golden[base+295+n], "independent final dirty");
            end
            $display("TRACE tb_cpu_step_halt: program=%s mode=%0d cycles=%0d clocks=%0d halted=%b writes=%0d stores=%0d stalls=%0d takes=%0d retired=%0d",
                     r_name, mode, advances, clocks, w_halted, writes, stores, stalls, takes, retired);
        end
    endtask

    initial begin
        #10000000;
        $fatal(1, "FAIL tb_cpu_step_halt: watchdog program=%s pc=%08h valid=%b%b%b%b",
               r_name, w_dbg_pc, dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id);
    end

    initial begin
        r_root = "";
        if ($value$plusargs("ROOT=%s", r_root)) begin end
        r_path = {r_root, "TP3_FINAL/programs/halt_suite.expected.hex"};
        input_file = $fopen(r_path, "r");
        if (!input_file) begin
            r_path = "halt_suite.expected.hex";
            input_file = $fopen(r_path, "r");
        end
        if (!input_file) $fatal(1, "FAIL tb_cpu_step_halt: missing expected state");
        $fclose(input_file);
        $readmemh(r_path, r_golden);
        r_output = {r_root, "TP3_FINAL/build/"};
        trace_file = $fopen({r_output, "a29_step_trace.csv"}, "w");
        if (!trace_file) begin
            r_output = "";
            trace_file = $fopen("a29_step_trace.csv", "w");
        end
        if (!trace_file) $fatal(1, "FAIL tb_cpu_step_halt: cannot open trace");
        $fdisplay(trace_file, "program,mode,clock,advance,enable,reset,halted,pc_if,pc_wb,valid,writes,stores,stalls,takes");
        $dumpfile({r_output, "a29_step_halt.vcd"});
        $dumpvars(1, dut);
        for (program_index = 0; program_index < 8; program_index = program_index + 1) begin
            casez (program_index)
                0: r_name = "arith_no_hazard";
                1: r_name = "raw_distance";
                2: r_name = "load_use";
                3: r_name = "suma";
                4: r_name = "jump_link";
                5: r_name = "branch_load_use";
                6: r_name = "flush_halt";
                7: r_name = "no_halt";
            endcase
            base = GOLD_WORDS*program_index;
            r_should_halt = r_golden[base] != 32'hffffffff;
            r_path = {r_root, "TP3_FINAL/programs/", r_name, ".hex"};
            input_file = $fopen(r_path, "r");
            if (!input_file) begin
                r_path = {r_name, ".hex"};
                input_file = $fopen(r_path, "r");
            end
            if (!input_file) $fatal(1, "FAIL tb_cpu_step_halt: missing program %s", r_name);
            $fclose(input_file);
            $readmemh(r_path, r_program);
            for (mode = 0; mode < 2; mode = mode + 1) begin
                clocks = 0;
                cycle(0, 1);
                r_reset = 0;
                observe_state(mode == 0);
                while ((r_should_halt && !w_halted) || (!r_should_halt && advances < r_golden[base+1])) begin
                    if (mode == 1) begin
                        repeat (2) begin
                            cycle(0, 0);
                            observe_state(0);
                        end
                    end
                    cycle(1, 0);
                    if (advances > r_golden[base+1] + 8 || clocks > 2000)
                        $fatal(1, "FAIL tb_cpu_step_halt: completion limit program=%s pc=%08h valid=%b%b%b%b halted=%b",
                               r_name, w_dbg_pc, dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id, w_halted);
                    observe_state(mode == 0);
                end
                if (!r_should_halt && $test$plusargs("EXPECT_HALT_NO_HALT"))
                    $fatal(1, "FAIL tb_cpu_step_halt: expected HALT timeout program=%s pc=%08h valid=%b%b%b%b",
                           r_name, w_dbg_pc, dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id);
                check_final();
                if (r_should_halt) begin
                    repeat (3) begin
                        cycle(1, 0);
                        observe_state(0);
                    end
                end else begin
                    cycle(0, 0);
                    observe_state(0);
                end
            end
        end
        $fclose(trace_file);
        if (errors != 0) $fatal(1, "FAIL tb_cpu_step_halt: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_cpu_step_halt: %0d checks, seven HALT programs and one no-HALT program in RUN and STEP", checks);
        $finish;
    end
endmodule

`default_nettype wire

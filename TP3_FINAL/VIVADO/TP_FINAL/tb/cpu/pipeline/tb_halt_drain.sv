`timescale 1ns/1ps
`default_nettype none

module tb_halt_drain;
    reg r_clock = 1'b0;
    reg r_reset = 1'b0;
    reg r_en = 1'b0;
    reg [31:0] r_program [0:255];
    reg [4:0] r_dbg_reg_addr = 5'd0;
    reg [3:0] r_dbg_latch_sel = 4'd0;
    reg [7:0] r_dbg_mem_addr = 8'd0;
    wire [31:0] w_imem_addr, w_dbg_pc, w_dbg_reg_data, w_dbg_latch_word, w_dbg_mem_data;
    wire w_halted, w_dbg_mem_dirty;
    wire [31:0] w_imem_data = r_program[w_imem_addr[9:2]];
    reg [31:0] r_expected_regs [0:31];
    reg [31:0] r_snapshot [0:559];
    reg [31:0] r_halt_pc, r_snapshot_pc;
    integer checks = 0;
    integer errors = 0;
    integer scenario, mode, index, clocks, advances, accepts, writes, stores, stalls;
    integer ex_entries, mem_entries, expected_writes, expected_stores, trace_file;
    reg r_paused_id, r_paused_ex, r_paused_mem;
    reg r_expected_halt_ex, r_expected_halt_mem, r_expected_halt_wb;
    reg r_advance, r_accept;
    reg [31:0] r_old_pc;

    cpu dut (
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .o_halted(w_halted), .o_imem_addr(w_imem_addr), .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr), .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel), .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr), .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty), .o_dbg_pc(w_dbg_pc)
    );

    task automatic check_word(input [31:0] got, input [31:0] expected,
                              input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                if (errors <= 30)
                    $display("FAIL tb_halt_drain: scenario=%0d mode=%0d clock=%0d advance=%0d %s expected=%08h got=%08h",
                             scenario, mode, clocks, advances, label, expected, got);
            end
        end
    endtask

    task automatic scan_state(input bit compare_snapshot);
        integer n;
        reg [31:0] value;
        begin
            if (compare_snapshot) check_word(w_dbg_pc, r_snapshot_pc, "paused PC");
            else r_snapshot_pc = w_dbg_pc;
            for (n = 0; n < 560; n = n + 1) begin
                if (n < 16) r_dbg_latch_sel = n[3:0];
                else if (n < 48) r_dbg_reg_addr = n - 16;
                else r_dbg_mem_addr = (n - 48) / 2;
                #1;
                if (n < 16) value = w_dbg_latch_word;
                else if (n < 48) value = w_dbg_reg_data;
                else if (n[0]) value = {31'd0, w_dbg_mem_dirty};
                else value = w_dbg_mem_data;
                if (compare_snapshot) check_word(value, r_snapshot[n], "paused state");
                else r_snapshot[n] = value;
            end
        end
    endtask

    task automatic cycle(input bit enable, input bit reset);
        begin
            r_en = enable;
            r_reset = reset;
            #1;
            r_advance = enable && !w_halted && !reset;
            r_accept = r_advance && dut.w_valid_id &&
                       (dut.w_instr_id == 32'h00000073) &&
                       !dut.w_take_ex && !dut.w_load_use_stall;
            check_word(dut.w_halt_accept_id, r_accept, "qualified HALT acceptance");
            r_old_pc = w_dbg_pc;
            if (reset) begin
                r_expected_halt_ex = 0;
                r_expected_halt_mem = 0;
                r_expected_halt_wb = 0;
            end else if (r_advance) begin
                r_expected_halt_wb = r_expected_halt_mem;
                r_expected_halt_mem = r_expected_halt_ex;
                r_expected_halt_ex = r_accept;
                if (r_accept) begin
                    accepts = accepts + 1;
                    check_word(dut.w_pc_id, r_halt_pc, "only the reachable HALT is accepted");
                    check_word(dut.w_stop_fetch, 1, "fetch stops on acceptance");
                end
                if (dut.w_valid_ex && dut.w_halt_ex) ex_entries = ex_entries + 1;
                if (dut.w_valid_mem && dut.w_halt_mem) mem_entries = mem_entries + 1;
                if (dut.w_load_use_stall) stalls = stalls + 1;
            end
            if (!reset) begin
                if (dut.w_regfile_we) begin
                    writes = writes + 1;
                    check_word(r_advance, 1, "register write requires advance");
                    check_word(dut.w_pc_wb < r_halt_pc, 1, "register write precedes HALT");
                    check_word(dut.w_wb_data, r_expected_regs[dut.w_rd_wb], "independent register commit");
                end
                if (dut.w_dmem_we) begin
                    stores = stores + 1;
                    check_word(r_advance, 1, "store requires advance");
                    check_word(dut.w_pc_mem, 4, "only the older store is allowed");
                    check_word(dut.w_result_mem, 0, "older store byte address");
                    check_word(dut.w_store_data_mem, 7, "older store data");
                end
                if (dut.w_valid_ex && dut.w_halt_ex)
                    check_word({dut.w_reg_write_ex, dut.w_mem_write_ex, dut.w_mem_read_ex,
                                dut.w_branch_ex, dut.w_jump_ex}, 0, "HALT has no EX effects");
                if (dut.w_valid_mem && dut.w_halt_mem)
                    check_word({dut.w_reg_write_mem, dut.w_mem_write_mem, dut.w_mem_read_mem}, 0, "HALT has no MEM effects");
            end
            #4;
            r_clock = 1'b1;
            #1;
            clocks = clocks + 1;
            if (r_advance) advances = advances + 1;
            check_word(dut.w_valid_ex && dut.w_halt_ex, r_expected_halt_ex, "HALT position in EX");
            check_word(dut.w_valid_mem && dut.w_halt_mem, r_expected_halt_mem, "HALT position in MEM");
            check_word(dut.w_valid_wb && dut.w_halt_wb, r_expected_halt_wb, "HALT position in WB");
            check_word(w_halted, r_expected_halt_wb, "halted starts at WB");
            if (reset) begin
                check_word(dut.r_fetch_stopped, 0, "reset releases fetch");
                check_word(w_dbg_pc, 0, "reset restores PC");
                check_word({dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id}, 0, "reset empties pipeline");
            end else if (r_accept || !r_advance)
                check_word(w_dbg_pc, r_old_pc, "PC holds on acceptance or pause");
            if (accepts != 0 && !reset) begin
                check_word(dut.r_fetch_stopped, 1, "fetch stays stopped during drain");
                check_word(dut.w_valid_id, 0, "IFID is invalid after acceptance");
                check_word(w_dbg_pc, r_halt_pc + 4, "fetch PC stays immediately after HALT");
            end
            if (w_halted) begin
                check_word({dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id}, 0, "older stages empty at HALT WB");
                check_word(dut.w_pc_wb, r_halt_pc, "HALT PC retained in WB");
                check_word(dut.w_reg_write_wb, 0, "HALT has no WB write");
            end
            $fdisplay(trace_file, "%0d,%0d,%0d,%0d,%b,%b,%08h,%b,%b,%b,%b,%b,%b,%b,%b",
                      scenario, mode, clocks, advances, enable, reset, w_dbg_pc,
                      dut.w_valid_id, dut.w_valid_ex, dut.w_valid_mem, dut.w_valid_wb,
                      dut.w_halt_ex, dut.w_halt_mem, dut.w_halt_wb, w_halted);
            #4;
            r_clock = 1'b0;
            #1;
        end
    endtask

    task automatic pause_stage;
        begin
            r_en = 0;
            #1;
            scan_state(0);
            repeat (2) begin
                cycle(0, 0);
                scan_state(1);
            end
        end
    endtask

    task automatic check_final;
        integer n;
        begin
            r_en = 0;
            #1;
            check_word(accepts, 1, "one HALT accepted");
            check_word(ex_entries, 1, "one HALT advances out of EX");
            check_word(mem_entries, 1, "one HALT advances out of MEM");
            check_word(writes, expected_writes, "exact register writes");
            check_word(stores, expected_stores, "exact stores");
            check_word(stalls, scenario == 7 ? 1 : 0, "real load-use only");
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n[4:0];
                #1;
                check_word(w_dbg_reg_data, r_expected_regs[n], "independent final register");
            end
            for (n = 0; n < 256; n = n + 1) begin
                r_dbg_mem_addr = n[7:0];
                #1;
                check_word(w_dbg_mem_data, expected_stores && n == 0 ? 7 : 0, "independent final memory");
                check_word(w_dbg_mem_dirty, expected_stores && n == 0, "independent final dirty");
            end
        end
    endtask

    initial begin
        #1000000;
        $fatal(1, "FAIL tb_halt_drain: watchdog before HALT");
    end

    initial begin
        trace_file = $fopen("TP3_FINAL/build/a27_halt_trace.csv", "w");
        if (!trace_file) $fatal(1, "FAIL tb_halt_drain: cannot open trace");
        $fdisplay(trace_file, "scenario,mode,clock,advance,enable,reset,pc_if,valid_id,valid_ex,valid_mem,valid_wb,halt_ex,halt_mem,halt_wb,halted");
        $dumpfile("TP3_FINAL/build/a27_halt_drain.vcd");
        $dumpvars(0, tb_halt_drain);
        for (scenario = 0; scenario < 9; scenario = scenario + 1) begin
            for (mode = 0; mode < 2; mode = mode + 1) begin
                r_en = 0;
                accepts = 0; writes = 0; stores = 0; stalls = 0;
                ex_entries = 0; mem_entries = 0; clocks = 0; advances = 0;
                r_paused_id = 0; r_paused_ex = 0; r_paused_mem = 0;
                expected_writes = 0; expected_stores = 0; r_halt_pc = 0;
                for (index = 0; index < 32; index = index + 1) r_expected_regs[index] = 0;
                for (index = 0; index < 256; index = index + 1) r_program[index] = 32'h00000013;
                casez (scenario)
                    0, 8: begin
                        r_program[0] = 32'h00000073;
                    end
                    1, 6, 7: begin
                        r_program[0] = 32'h00700093;
                        r_program[1] = 32'h00102023;
                        r_program[2] = scenario == 1 ? 32'h00900113 : 32'h00002103;
                        r_halt_pc = scenario == 7 ? 16 : 12;
                        if (scenario == 7) r_program[3] = 32'h002101b3;
                        r_expected_regs[1] = 7;
                        r_expected_regs[2] = scenario == 1 ? 9 : 7;
                        if (scenario == 7) r_expected_regs[3] = 14;
                        expected_writes = scenario == 7 ? 3 : 2;
                        expected_stores = 1;
                    end
                    2: begin
                        r_program[0] = 32'h00100093;
                        r_program[1] = 32'h00009663;
                        r_program[2] = 32'h00000073;
                        r_program[3] = 32'h00102223;
                        r_program[4] = 32'h00900113;
                        r_expected_regs[1] = 1; r_expected_regs[2] = 9;
                        r_halt_pc = 20; expected_writes = 2;
                    end
                    3: begin
                        r_program[0] = 32'h00c002ef;
                        r_program[1] = 32'h06300513;
                        r_program[2] = 32'h00000073;
                        r_program[3] = 32'h00900113;
                        r_expected_regs[5] = 4; r_expected_regs[2] = 9;
                        r_halt_pc = 16; expected_writes = 2;
                    end
                    4: begin
                        r_program[0] = 32'h00001863;
                        r_halt_pc = 4;
                    end
                    5: begin
                        r_program[0] = 32'h00100073;
                        r_program[1] = 32'h00001073;
                        r_program[2] = 32'h000000f3;
                        r_program[3] = 32'h10000073;
                        r_program[4] = 32'h00900113;
                        r_expected_regs[2] = 9;
                        r_halt_pc = 20; expected_writes = 1;
                    end
                endcase
                r_program[r_halt_pc / 4] = 32'h00000073;
                r_program[r_halt_pc / 4 + 1] = scenario == 8 ? 32'h00000073 : 32'h06300513;
                r_program[r_halt_pc / 4 + 2] = 32'h00102223;
                cycle(0, 1);
                r_reset = 0;
                while (!w_halted && clocks < 60) begin
                    if (mode == 1) begin
                        if (dut.w_valid_id && dut.w_instr_id == 32'h00000073 && !r_paused_id) begin
                            r_paused_id = 1;
                            pause_stage();
                        end else if (dut.w_valid_ex && dut.w_halt_ex && !r_paused_ex) begin
                            r_paused_ex = 1;
                            pause_stage();
                        end else if (dut.w_valid_mem && dut.w_halt_mem && !r_paused_mem) begin
                            r_paused_mem = 1;
                            pause_stage();
                        end
                    end
                    cycle(1, 0);
                end
                check_word(w_halted, 1, "bounded completion requires HALT");
                check_final();
                scan_state(0);
                repeat (3) begin
                    cycle(1, 0);
                    scan_state(1);
                end
                accepts = 0;
                cycle(0, 1);
                r_reset = 0;
                cycle(1, 0);
                check_word(dut.w_valid_id, 1, "fetch restarts after reset");
                check_word(dut.w_pc_id, 0, "restart fetches program entry");
            end
        end
        scenario = 9;
        for (index = 0; index < 3; index = index + 1) begin
            accepts = 0; writes = 0; stores = 0; stalls = 0;
            ex_entries = 0; mem_entries = 0; clocks = 0; advances = 0;
            r_halt_pc = 0;
            r_program[0] = 32'h00000073;
            cycle(0, 1);
            r_reset = 0;
            repeat (2 + index) cycle(1, 0);
            accepts = 0;
            cycle(0, 1);
            r_program[0] = 32'h00900113;
            r_reset = 0;
            cycle(1, 0);
            check_word(dut.w_instr_id, 32'h00900113, "reset cancels HALT and permits replacement program");
        end
        $fclose(trace_file);
        if (errors != 0) $fatal(1, "FAIL tb_halt_drain: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_halt_drain: %0d checks, 18 program runs and reset during drain", checks);
        $finish;
    end
endmodule

`default_nettype wire

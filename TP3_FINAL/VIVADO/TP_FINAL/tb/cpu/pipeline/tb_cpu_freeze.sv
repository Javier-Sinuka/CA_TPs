`timescale 1ns/1ps
`default_nettype none

module tb_cpu_freeze;
    localparam integer PIPE_WORDS = 19;
    reg r_clock = 1'b0;
    reg r_reset = 1'b0;
    reg r_en = 1'b0;
    reg r_imem_we = 1'b0;
    reg [7:0] r_imem_waddr = 8'd0;
    reg [31:0] r_imem_wdata = 32'd0;
    reg [4:0] r_dbg_reg_addr = 5'd0;
    reg [3:0] r_dbg_latch_sel = 4'd0;
    reg [7:0] r_dbg_mem_addr = 8'd0;
    wire [31:0] w_imem_addr, w_imem_data, w_dbg_pc;
    wire [31:0] w_dbg_reg_data, w_dbg_latch_word, w_dbg_mem_data;
    wire w_halted, w_dbg_mem_dirty;
    reg [31:0] r_program [0:255];
    reg [31:0] r_pipe_snapshot [0:PIPE_WORDS-1];
    reg [31:0] r_regs_snapshot [0:31];
    reg [31:0] r_mem_snapshot [0:255];
    reg [255:0] r_dirty_snapshot;
    reg [31:0] r_continuous_pipe [0:15][0:PIPE_WORDS-1];
    reg [31:0] r_expected_pc [0:15];
    reg [3:0] r_expected_valid [0:15];
    reg [31:0] r_expected_stage_pc [0:15][0:3];
    integer checks = 0;
    integer errors = 0;
    integer clocks = 0;
    integer advances = 0;
    integer writes = 0;
    integer stores = 0;
    integer index, stage, mode, scenario, trace_file;
    integer paused_clocks = 0;
    integer halted_clocks = 0;
    reg r_do_advance;

    cpu dut (
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

    function automatic [31:0] pipeline_word(input integer address);
        begin
            casez (address)
                0: pipeline_word = dut.r_pc_if;
                1: pipeline_word = {31'd0, dut.r_fetch_stopped};
                2: pipeline_word = dut.w_pc_id;
                3: pipeline_word = dut.w_instr_id;
                4: pipeline_word = {28'd0, dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id};
                5: pipeline_word = dut.w_pc_ex;
                6: pipeline_word = dut.w_rs1_data_ex;
                7: pipeline_word = dut.w_rs2_data_ex;
                8: pipeline_word = dut.w_imm_ex;
                9: pipeline_word = dut.w_info_ex;
                10: pipeline_word = {30'd0, dut.w_uses_rs1_ex, dut.w_uses_rs2_ex};
                11: pipeline_word = dut.w_pc_mem;
                12: pipeline_word = dut.w_result_mem;
                13: pipeline_word = dut.w_store_data_mem;
                14: pipeline_word = dut.w_info_mem;
                15: pipeline_word = dut.w_pc_wb;
                16: pipeline_word = dut.w_result_wb;
                17: pipeline_word = dut.w_load_data_wb;
                18: pipeline_word = dut.w_info_wb;
                default: pipeline_word = 0;
            endcase
        end
    endfunction

    function automatic [31:0] expected_register(input integer address, input integer count);
        begin
            expected_register = 0;
            casez (address)
                1: if (count >= 5) expected_register = 7;
                2: if (count >= 6) expected_register = 11;
                3: if (count >= 8) expected_register = 11;
                4: if (count >= 10) expected_register = 18;
                5: if (count >= 15) expected_register = 19;
                default: begin end
            endcase
        end
    endfunction

    task automatic check_word(input [31:0] got, input [31:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                if (errors <= 30)
                    $display("FAIL tb_cpu_freeze: scenario=%0d mode=%0d clock=%0d advance=%0d %s expected=%08h got=%08h",
                             scenario, mode, clocks, advances, label, expected, got);
            end
        end
    endtask

    task automatic check_guards;
        reg advance;
        begin
            advance = r_en && !w_halted;
            check_word(w_halted, dut.w_valid_wb && dut.w_halt_wb, "combinational halted");
            check_word(dut.w_adv, advance, "global enable");
            check_word(dut.w_regfile_we,
                       !r_reset && advance && dut.w_valid_wb && dut.w_reg_write_wb && dut.w_rd_wb != 0,
                       "effective WB write");
            check_word(dut.w_dmem_we,
                       !r_reset && advance && dut.w_valid_mem && dut.w_mem_write_mem,
                       "effective MEM store");
            check_word(dut.u_decode.u_regfile.w_we, dut.w_regfile_we, "regfile local enable");
            check_word(dut.u_memory.u_dmem.w_we, dut.w_dmem_we, "dmem local enable");
            check_word(w_dbg_pc, w_imem_addr, "IF address equals debug PC");
            if (!r_imem_we) check_word(w_imem_data, r_program[w_imem_addr[9:2]], "external program read");
        end
    endtask

    task automatic clock_edge(input bit enable, input bit reset);
        begin
            r_en = enable;
            r_reset = reset;
            #1;
            check_guards();
            r_do_advance = enable && !w_halted && !reset;
            if (!reset && !r_imem_we) begin
                if (dut.w_regfile_we) begin
                    writes = writes + 1;
                    casez (advances)
                        4: begin
                            check_word(dut.w_pc_wb, 0, "first WB PC");
                            check_word(dut.w_rd_wb, 1, "first WB destination");
                            check_word(dut.w_wb_data, 7, "first WB value");
                        end
                        5: begin
                            check_word(dut.w_rd_wb, 2, "second WB destination");
                            check_word(dut.w_wb_data, 11, "second WB value");
                        end
                        7: begin
                            check_word(dut.w_rd_wb, 3, "load WB destination");
                            check_word(dut.w_wb_data, 11, "load WB value");
                        end
                        9: begin
                            check_word(dut.w_rd_wb, 4, "dependent WB destination");
                            check_word(dut.w_wb_data, 18, "dependent WB value");
                        end
                        14: begin
                            check_word(dut.w_rd_wb, 5, "last WB destination");
                            check_word(dut.w_wb_data, 19, "last WB value before HALT");
                        end
                        default: check_word(1, 0, "unexpected register write");
                    endcase
                end
                if (dut.w_dmem_we) begin
                    stores = stores + 1;
                    check_word(advances == 5 || advances == 9, 1, "store occurs once at expected advance");
                    check_word(dut.w_pc_mem, advances == 5 ? 8 : 20, "store instruction PC");
                    check_word(dut.w_result_mem, advances == 5 ? 0 : 4, "store address");
                    check_word(dut.w_store_data_mem, advances == 5 ? 11 : 18, "store data");
                end
            end
            #4;
            r_clock = 1;
            #1;
            clocks = clocks + 1;
            if (reset) begin
                advances = 0; writes = 0; stores = 0;
            end else if (r_do_advance) advances = advances + 1;
            check_guards();
            $fdisplay(trace_file, "%0d,%0d,%0d,%0d,%b,%b,%b,%08h,%b,%b,%b,%b,%b",
                      scenario, mode, clocks, advances, enable, reset, w_halted,
                      w_dbg_pc, dut.w_valid_id, dut.w_valid_ex, dut.w_valid_mem,
                      dut.w_valid_wb, dut.r_fetch_stopped);
            #4;
            r_clock = 0;
            #1;
        end
    endtask

    task automatic save_snapshot;
        integer n;
        begin
            for (n = 0; n < PIPE_WORDS; n = n + 1) r_pipe_snapshot[n] = pipeline_word(n);
            r_regs_snapshot[0] = 0;
            for (n = 1; n < 32; n = n + 1) r_regs_snapshot[n] = dut.u_decode.u_regfile.r_regs[n];
            for (n = 0; n < 256; n = n + 1) r_mem_snapshot[n] = dut.u_memory.u_dmem.r_mem[n];
            r_dirty_snapshot = dut.u_memory.u_dmem.r_dirty;
        end
    endtask

    task automatic compare_snapshot;
        integer n;
        begin
            for (n = 0; n < PIPE_WORDS; n = n + 1)
                check_word(pipeline_word(n), r_pipe_snapshot[n], "full pipeline snapshot");
            for (n = 1; n < 32; n = n + 1)
                check_word(dut.u_decode.u_regfile.r_regs[n], r_regs_snapshot[n], "raw register snapshot");
            for (n = 0; n < 256; n = n + 1) begin
                check_word(dut.u_memory.u_dmem.r_mem[n], r_mem_snapshot[n], "raw dmem snapshot");
                check_word(dut.u_memory.u_dmem.r_dirty[n], r_dirty_snapshot[n], "dirty snapshot");
                check_word(u_imem.r_mem[n], r_program[n], "imem preserved");
            end
        end
    endtask

    task automatic check_debug;
        reg [31:0] expected_latch;
        begin
            check_word(w_dbg_reg_data, r_regs_snapshot[r_dbg_reg_addr], "combinational debug register");
            check_word(w_dbg_mem_dirty, r_dirty_snapshot[r_dbg_mem_addr], "combinational debug dirty");
            check_word(w_dbg_mem_data,
                       r_dirty_snapshot[r_dbg_mem_addr] ? r_mem_snapshot[r_dbg_mem_addr] : 0,
                       "combinational debug memory");
            casez (r_dbg_latch_sel)
                0: expected_latch = r_pipe_snapshot[2];
                1: expected_latch = r_pipe_snapshot[3];
                2: expected_latch = r_pipe_snapshot[5];
                3: expected_latch = r_pipe_snapshot[6];
                4: expected_latch = r_pipe_snapshot[7];
                5: expected_latch = r_pipe_snapshot[8];
                6: expected_latch = r_pipe_snapshot[9];
                7: expected_latch = r_pipe_snapshot[11];
                8: expected_latch = r_pipe_snapshot[12];
                9: expected_latch = r_pipe_snapshot[13];
                10: expected_latch = r_pipe_snapshot[14];
                11: expected_latch = r_pipe_snapshot[15];
                12: expected_latch = r_pipe_snapshot[16];
                13: expected_latch = r_pipe_snapshot[17];
                14: expected_latch = r_pipe_snapshot[18];
                15: expected_latch = {
                    24'd0, dut.w_stop_fetch, dut.w_take_ex, dut.w_load_use_stall, w_halted,
                    r_pipe_snapshot[4][3:0]
                };
            endcase
            check_word(w_dbg_latch_word, expected_latch, "combinational debug latch");
        end
    endtask

    task automatic freeze(input integer count, input integer enable_mode);
        integer n;
        begin
            r_en = 0;
            #1;
            save_snapshot();
            for (n = 0; n < count; n = n + 1) begin
                r_dbg_reg_addr = n[4:0];
                r_dbg_mem_addr = n[7:0];
                r_dbg_latch_sel = n[3:0];
                #1;
                check_debug();
                compare_snapshot();
                clock_edge(enable_mode == 1 || (enable_mode == 2 && n[0]), 0);
                check_debug();
                compare_snapshot();
                if (enable_mode == 0) paused_clocks = paused_clocks + 1;
                else halted_clocks = halted_clocks + 1;
            end
        end
    endtask

    task automatic check_architecture;
        integer n;
        begin
            check_word(w_dbg_pc, r_expected_pc[advances], "independent IF PC per advance");
            check_word(pipeline_word(4), r_expected_valid[advances], "independent valid per advance");
            if (dut.w_valid_id) check_word(dut.w_pc_id, r_expected_stage_pc[advances][0], "independent ID PC");
            if (dut.w_valid_ex) check_word(dut.w_pc_ex, r_expected_stage_pc[advances][1], "independent EX PC");
            if (dut.w_valid_mem) check_word(dut.w_pc_mem, r_expected_stage_pc[advances][2], "independent MEM PC");
            if (dut.w_valid_wb) check_word(dut.w_pc_wb, r_expected_stage_pc[advances][3], "independent WB PC");
            check_word(w_halted, advances == 15, "HALT only after fifteenth enabled cycle");
            check_word(dut.r_fetch_stopped, advances >= 13, "fetch stop begins on HALT acceptance");
            check_word(dut.w_load_use_stall, advances == 5, "pending load-use at exact cycle");
            check_word(dut.w_take_ex, advances == 9, "pending taken branch at exact cycle");
            check_word(writes, (advances >= 5) + (advances >= 6) + (advances >= 8) +
                              (advances >= 10) + (advances >= 15), "exact writes per advance");
            check_word(stores, (advances >= 6) + (advances >= 10), "exact stores per advance");
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n[4:0];
                #1;
                check_word(w_dbg_reg_data, expected_register(n, advances), "independent architectural register");
            end
            for (n = 0; n < 256; n = n + 1) begin
                r_dbg_mem_addr = n[7:0];
                #1;
                check_word(w_dbg_mem_data, n == 0 && advances >= 6 ? 11 :
                           n == 1 && advances >= 10 ? 18 : 0, "independent architectural memory");
                check_word(w_dbg_mem_dirty, (n == 0 && advances >= 6) ||
                           (n == 1 && advances >= 10), "independent architectural dirty");
            end
            for (n = 0; n < PIPE_WORDS; n = n + 1) begin
                if (mode == 0) r_continuous_pipe[advances][n] = pipeline_word(n);
                else check_word(pipeline_word(n), r_continuous_pipe[advances][n], "STEP matches continuous pipeline");
            end
        end
    endtask

    task automatic reset_and_check(input bit enable);
        integer n;
        begin
            r_en = 0;
            r_reset = 0;
            #1;
            save_snapshot();
            r_reset = 1;
            #1;
            compare_snapshot();
            clock_edge(enable, 1);
            for (n = 0; n < PIPE_WORDS; n = n + 1)
                check_word(pipeline_word(n), 0, "reset clears pipeline payload and control");
            for (n = 1; n < 32; n = n + 1)
                check_word(dut.u_decode.u_regfile.r_regs[n], 0, "reset clears all stored registers");
            for (n = 0; n < 256; n = n + 1) begin
                check_word(dut.u_memory.u_dmem.r_mem[n], r_mem_snapshot[n], "reset preserves physical dmem");
                check_word(dut.u_memory.u_dmem.r_dirty[n], 0, "reset clears every dirty bit");
                check_word(u_imem.r_mem[n], r_program[n], "reset preserves external imem");
            end
            check_word(w_halted, 0, "reset releases halted immediately after edge");
            r_reset = 0;
            r_en = 0;
            #1;
            check_architecture();
        end
    endtask

    initial begin
        #10000000;
        $fatal(1, "FAIL tb_cpu_freeze: watchdog");
    end

    initial begin
        trace_file = $fopen("TP3_FINAL/build/a28_freeze_trace.csv", "w");
        if (!trace_file) $fatal(1, "FAIL tb_cpu_freeze: cannot open trace");
        $fdisplay(trace_file, "scenario,mode,clock,advance,enable,reset,halted,pc_if,valid_id,valid_ex,valid_mem,valid_wb,fetch_stopped");
        $dumpfile("TP3_FINAL/build/a28_cpu_freeze.vcd");
        $dumpvars(0, tb_cpu_freeze);
        for (index = 0; index < 256; index = index + 1) r_program[index] = 32'h00000073;
        r_program[0] = 32'h00700093;
        r_program[1] = 32'h00b00113;
        r_program[2] = 32'h00202023;
        r_program[3] = 32'h00002183;
        r_program[4] = 32'h00118233;
        r_program[5] = 32'h00402223;
        r_program[6] = 32'h00420463;
        r_program[7] = 32'h06300513;
        r_program[8] = 32'h00120293;
        r_program[9] = 32'h00000073;
        r_program[10] = 32'h06300513;
        r_program[11] = 32'h00202423;
        for (index = 0; index < 16; index = index + 1) begin
            for (stage = 0; stage < 4; stage = stage + 1) r_expected_stage_pc[index][stage] = 0;
            casez (index)
                0: begin r_expected_pc[index] = 0; r_expected_valid[index] = 0; end
                1: begin r_expected_pc[index] = 4; r_expected_valid[index] = 1; end
                2: begin r_expected_pc[index] = 8; r_expected_valid[index] = 3; end
                3: begin r_expected_pc[index] = 12; r_expected_valid[index] = 7; end
                4: begin r_expected_pc[index] = 16; r_expected_valid[index] = 15; end
                5: begin r_expected_pc[index] = 20; r_expected_valid[index] = 15; end
                6: begin r_expected_pc[index] = 20; r_expected_valid[index] = 13; end
                7: begin r_expected_pc[index] = 24; r_expected_valid[index] = 11; end
                8: begin r_expected_pc[index] = 28; r_expected_valid[index] = 7; end
                9: begin r_expected_pc[index] = 32; r_expected_valid[index] = 15; end
                10: begin r_expected_pc[index] = 32; r_expected_valid[index] = 12; end
                11: begin r_expected_pc[index] = 36; r_expected_valid[index] = 9; end
                12: begin r_expected_pc[index] = 40; r_expected_valid[index] = 3; end
                13: begin r_expected_pc[index] = 40; r_expected_valid[index] = 6; end
                14: begin r_expected_pc[index] = 40; r_expected_valid[index] = 12; end
                15: begin r_expected_pc[index] = 40; r_expected_valid[index] = 8; end
            endcase
        end
        r_expected_stage_pc[2][0] = 4;
        r_expected_stage_pc[3][0] = 8; r_expected_stage_pc[3][1] = 4;
        r_expected_stage_pc[4][0] = 12; r_expected_stage_pc[4][1] = 8; r_expected_stage_pc[4][2] = 4;
        r_expected_stage_pc[5][0] = 16; r_expected_stage_pc[5][1] = 12; r_expected_stage_pc[5][2] = 8; r_expected_stage_pc[5][3] = 4;
        r_expected_stage_pc[6][0] = 16; r_expected_stage_pc[6][2] = 12; r_expected_stage_pc[6][3] = 8;
        r_expected_stage_pc[7][0] = 20; r_expected_stage_pc[7][1] = 16; r_expected_stage_pc[7][3] = 12;
        r_expected_stage_pc[8][0] = 24; r_expected_stage_pc[8][1] = 20; r_expected_stage_pc[8][2] = 16;
        r_expected_stage_pc[9][0] = 28; r_expected_stage_pc[9][1] = 24; r_expected_stage_pc[9][2] = 20; r_expected_stage_pc[9][3] = 16;
        r_expected_stage_pc[10][2] = 24; r_expected_stage_pc[10][3] = 20;
        r_expected_stage_pc[11][0] = 32; r_expected_stage_pc[11][3] = 24;
        r_expected_stage_pc[12][0] = 36; r_expected_stage_pc[12][1] = 32;
        r_expected_stage_pc[13][1] = 36; r_expected_stage_pc[13][2] = 32;
        r_expected_stage_pc[14][2] = 36; r_expected_stage_pc[14][3] = 32;
        r_expected_stage_pc[15][3] = 36;
        scenario = 0; mode = 0;
        r_reset = 1;
        for (index = 0; index < 256; index = index + 1) begin
            r_imem_we = 1;
            r_imem_waddr = index[7:0];
            r_imem_wdata = r_program[index];
            clock_edge(0, 1);
        end
        r_imem_we = 0;
        r_reset = 0;
        for (mode = 0; mode < 2; mode = mode + 1) begin
            scenario = mode;
            reset_and_check(0);
            while (advances < 15) begin
                if (mode == 1) freeze(200, 0);
                clock_edge(1, 0);
                check_architecture();
            end
            if (mode == 1) begin
                freeze(256, 1);
                freeze(256, 2);
            end
        end
        mode = 1;
        for (scenario = 2; scenario < 6; scenario = scenario + 1) begin
            if (scenario == 2 || scenario == 3) reset_and_check(scenario[0]);
            else begin
                reset_and_check(0);
                repeat (9) clock_edge(1, 0);
                check_architecture();
                check_word(dut.w_reg_write_wb, 1, "reset test has pending register write");
                check_word(dut.w_mem_write_mem, 1, "reset test has pending store");
                check_word(dut.w_take_ex, 1, "reset test has pending redirect");
                freeze(200, 0);
                reset_and_check(scenario[0]);
            end
            while (advances < 15) clock_edge(1, 0);
            check_architecture();
            freeze(200, 1);
        end
        $fclose(trace_file);
        if (errors != 0) $fatal(1, "FAIL tb_cpu_freeze: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_cpu_freeze: %0d checks, %0d paused clocks, %0d halted clocks, STEP and reset priority",
                 checks, paused_clocks, halted_clocks);
        $finish;
    end
endmodule

`default_nettype wire

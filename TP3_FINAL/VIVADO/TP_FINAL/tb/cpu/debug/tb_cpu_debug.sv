`timescale 1ns/1ps
`default_nettype none

module tb_cpu_debug;
    reg r_clock = 0;
    reg r_reset = 0;
    reg r_en = 0;
    reg [31:0] r_program [0:255];
    reg [31:0] r_expected_regs [0:31];
    reg [31:0] r_saved [0:47];
    reg [31:0] r_pattern = 0;
    reg [7:0] r_flags = 0;
    reg [4:0] r_dbg_reg_addr = 0;
    reg [3:0] r_dbg_latch_sel = 0;
    reg [7:0] r_dbg_mem_addr = 0;
    reg r_memory_written = 0;
    wire [31:0] w_imem_addr, w_dbg_pc, w_dbg_reg_data, w_dbg_latch_word, w_dbg_mem_data;
    wire w_halted, w_dbg_mem_dirty;
    wire [4:0] w_pattern_0_5 = r_pattern[0 +: 5];
    wire [4:0] w_pattern_10_5 = r_pattern[10 +: 5];
    wire [2:0] w_pattern_15_3 = r_pattern[15 +: 3];
    wire [3:0] w_pattern_18_4 = r_pattern[18 +: 4];
    wire [0:0] w_pattern_22_1 = r_pattern[22 +: 1];
    wire [0:0] w_pattern_23_1 = r_pattern[23 +: 1];
    wire [0:0] w_pattern_24_1 = r_pattern[24 +: 1];
    wire [0:0] w_pattern_25_1 = r_pattern[25 +: 1];
    wire [0:0] w_pattern_26_1 = r_pattern[26 +: 1];
    wire [0:0] w_pattern_27_1 = r_pattern[27 +: 1];
    wire [0:0] w_pattern_28_1 = r_pattern[28 +: 1];
    wire [0:0] w_pattern_29_1 = r_pattern[29 +: 1];
    wire [0:0] w_pattern_30_1 = r_pattern[30 +: 1];
    wire [0:0] w_pattern_31_1 = r_pattern[31 +: 1];
    wire [4:0] w_pattern_5_5 = r_pattern[5 +: 5];
    wire w_flag_0 = r_flags[0];
    wire w_flag_1 = r_flags[1];
    wire w_flag_2 = r_flags[2];
    wire w_flag_3 = r_flags[3];
    wire w_flag_4 = r_flags[4];
    wire w_flag_5 = r_flags[5];
    wire w_flag_6 = r_flags[6];
    wire w_flag_7 = r_flags[7];
    integer checks = 0;
    integer errors = 0;
    integer clocks = 0;
    integer advances = 0;
    integer stalls = 0;
    integer takes = 0;
    integer accepts = 0;
    integer captured_differences = 0;
    integer retained_bubbles = 0;
    integer n, bit_index;
    reg [7:0] r_seen_flags = 0;

    cpu dut (
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .o_halted(w_halted), .o_imem_addr(w_imem_addr),
        .i_imem_data(r_program[w_imem_addr[9:2]]),
        .i_dbg_reg_addr(r_dbg_reg_addr), .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel), .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr), .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty), .o_dbg_pc(w_dbg_pc)
    );

    function automatic [31:0] latch_word(input integer selector);
        begin
            casez (selector)
                0: latch_word = dut.w_pc_id;
                1: latch_word = dut.w_instr_id;
                2: latch_word = dut.w_pc_ex;
                3: latch_word = dut.w_rs1_data_ex;
                4: latch_word = dut.w_rs2_data_ex;
                5: latch_word = dut.w_imm_ex;
                6: latch_word = dut.w_info_ex;
                7: latch_word = dut.w_pc_mem;
                8: latch_word = dut.w_result_mem;
                9: latch_word = dut.w_store_data_mem;
                10: latch_word = dut.w_info_mem;
                11: latch_word = dut.w_pc_wb;
                12: latch_word = dut.w_result_wb;
                13: latch_word = dut.w_load_data_wb;
                14: latch_word = dut.w_info_wb;
                15: latch_word = (dut.w_valid_id ? 1 : 0) |
                                 (dut.w_valid_ex ? 2 : 0) |
                                 (dut.w_valid_mem ? 4 : 0) |
                                 (dut.w_valid_wb ? 8 : 0) |
                                 (w_halted ? 16 : 0) |
                                 (dut.w_load_use_stall ? 32 : 0) |
                                 (dut.w_take_ex ? 64 : 0) |
                                 (dut.w_stop_fetch ? 128 : 0);
                default: latch_word = 0;
            endcase
        end
    endfunction

    function automatic [31:0] program_info(input [31:0] pc);
        begin
            casez (pc)
                32'd0: program_info = 32'h04402401;
                32'd4: program_info = 32'h04000422;
                32'd8: program_info = 32'h01410800;
                32'd12: program_info = 32'h06c10003;
                32'd16: program_info = 32'h04000464;
                32'd20: program_info = 32'h0800108c;
                32'd32: program_info = 32'h44428d06;
                32'd36: program_info = 32'h14003007;
                32'd48: program_info = 32'h04407ce8;
                32'd52: program_info = 32'h34400409;
                32'd64: program_info = 32'h08008108;
                32'd72: program_info = 32'h80000000;
                default: program_info = 32'hffffffff;
            endcase
        end
    endfunction

    function automatic [31:0] register_result(input [4:0] address);
        begin
            casez (address)
                1: register_result = 9;
                2, 3: register_result = 18;
                4: register_result = 27;
                6: register_result = 32'h12345000;
                7: register_result = 40;
                8: register_result = 39;
                9: register_result = 56;
                default: register_result = 0;
            endcase
        end
    endfunction

    task automatic check_word(input [31:0] got, input [31:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL tb_cpu_debug: clock=%0d advance=%0d selector=%0d %s expected=%08h got=%08h",
                         clocks, advances, r_dbg_latch_sel, label, expected, got);
                if ($test$plusargs("FAIL_FAST")) $fatal(1, "FAIL tb_cpu_debug: first discrepancy");
            end
        end
    endtask

    task automatic scan(input bit compare_saved);
        integer i;
        reg [31:0] expected;
        begin
            for (i = 0; i < 16; i = i + 1) begin
                r_dbg_latch_sel = i[3:0];
                #1;
                expected = latch_word(i);
                check_word(w_dbg_latch_word, expected, "public latch matches source");
                if (compare_saved) check_word(w_dbg_latch_word, r_saved[i], "paused latch payload");
                else r_saved[i] = w_dbg_latch_word;
            end
            for (i = 0; i < 32; i = i + 1) begin
                r_dbg_reg_addr = i[4:0];
                #1;
                check_word(w_dbg_reg_data, r_expected_regs[i], "independent register state");
                if (compare_saved) check_word(w_dbg_reg_data, r_saved[16+i], "paused register state");
                else r_saved[16+i] = w_dbg_reg_data;
            end
            check_word(dut.w_info_mem & ~32'h8783801f, 0, "MEM absent fields");
            check_word(dut.w_info_wb & ~32'h8600001f, 0, "WB absent fields");
            check_word(dut.w_dbg_flags & 32'hffffff00, 0, "reserved flags");
            check_word(w_dbg_pc, w_imem_addr, "public IF byte PC");
            check_word(w_dbg_mem_data, r_memory_written ? 18 : 0, "independent memory word");
            check_word(w_dbg_mem_dirty, r_memory_written, "independent dirty");
            if (dut.w_valid_ex)
                check_word(dut.w_info_ex, program_info(dut.w_pc_ex), "independent EX info");
            if (dut.w_valid_mem)
                check_word(dut.w_info_mem, program_info(dut.w_pc_mem) & 32'h8783801f, "independent MEM info");
            if (dut.w_valid_wb)
                check_word(dut.w_info_wb, program_info(dut.w_pc_wb) & 32'h8600001f, "independent WB info");
            if (!dut.w_valid_ex && dut.w_pc_ex != 0) retained_bubbles = retained_bubbles + 1;
            if (dut.w_valid_ex && dut.w_pc_ex == 4) begin
                check_word(dut.w_rs1_data_ex, 0, "captured rs1 before forwarding");
                check_word(dut.w_rs2_data_ex, 0, "captured rs2 before forwarding");
                check_word(dut.w_rs1_fwd_ex, 9, "forwarded rs1 differs");
                check_word(dut.w_rs2_fwd_ex, 9, "forwarded rs2 differs");
                captured_differences = captured_differences + 1;
            end
            r_seen_flags = r_seen_flags | latch_word(15);
        end
    endtask

    task automatic cycle(input bit enable, input bit reset);
        reg commit, store;
        reg [4:0] destination;
        begin
            r_en = enable;
            r_reset = reset;
            #1;
            if (!reset) begin
                scan(0);
                check_word(dut.w_load_use_stall,
                           dut.w_valid_ex && dut.w_pc_ex == 12 && dut.w_valid_id && dut.w_pc_id == 16,
                           "independent current load-use");
                check_word(dut.w_take_ex,
                           dut.w_valid_ex && (dut.w_pc_ex == 20 || dut.w_pc_ex == 36 ||
                                             dut.w_pc_ex == 52 || dut.w_pc_ex == 64),
                           "independent current redirect");
            end
            commit = !reset && dut.w_regfile_we;
            store = !reset && dut.w_dmem_we;
            destination = dut.w_rd_wb;
            if (commit) check_word(dut.w_wb_data, register_result(destination), "independent committed result");
            if (store) begin
                check_word(dut.w_pc_mem, 8, "only the reachable store commits");
                check_word(dut.w_result_mem, 0, "store byte address");
                check_word(dut.w_store_data_mem, 18, "store forwarded data");
            end
            if (enable && !w_halted && !reset) begin
                advances = advances + 1;
                if (dut.w_load_use_stall) stalls = stalls + 1;
                if (dut.w_take_ex) takes = takes + 1;
                if (dut.w_halt_accept_id) accepts = accepts + 1;
            end
            #2;
            r_clock = 1;
            #1;
            clocks = clocks + 1;
            if (reset) begin
                for (integer i = 0; i < 32; i = i + 1) r_expected_regs[i] = 0;
                r_memory_written = 0;
            end else begin
                if (commit) r_expected_regs[destination] = register_result(destination);
                if (store) r_memory_written = 1;
            end
            #2;
            r_clock = 0;
            #1;
            scan(!enable && !reset);
        end
    endtask

    task synthetic_info;
        begin
            force dut.u_decode.u_id_ex.r_rd = w_pattern_0_5;
            force dut.u_decode.u_id_ex.r_rs1 = w_pattern_5_5;
            force dut.u_decode.u_id_ex.r_rs2 = w_pattern_10_5;
            force dut.u_decode.u_id_ex.r_funct3 = w_pattern_15_3;
            force dut.u_decode.u_id_ex.r_alu_op = w_pattern_18_4;
            force dut.u_decode.u_id_ex.r_alu_src_b = w_pattern_22_1;
            force dut.u_decode.u_id_ex.r_mem_read = w_pattern_23_1;
            force dut.u_decode.u_id_ex.r_mem_write = w_pattern_24_1;
            force dut.u_decode.u_id_ex.r_mem_to_reg = w_pattern_25_1;
            force dut.u_decode.u_id_ex.r_reg_write = w_pattern_26_1;
            force dut.u_decode.u_id_ex.r_branch = w_pattern_27_1;
            force dut.u_decode.u_id_ex.r_jump = w_pattern_28_1;
            force dut.u_decode.u_id_ex.r_jalr = w_pattern_29_1;
            force dut.u_decode.u_id_ex.r_lui = w_pattern_30_1;
            force dut.u_decode.u_id_ex.r_halt = w_pattern_31_1;
            force dut.u_execute.u_ex_mem.r_rd = w_pattern_0_5;
            force dut.u_execute.u_ex_mem.r_funct3 = w_pattern_15_3;
            force dut.u_execute.u_ex_mem.r_mem_read = w_pattern_23_1;
            force dut.u_execute.u_ex_mem.r_mem_write = w_pattern_24_1;
            force dut.u_execute.u_ex_mem.r_mem_to_reg = w_pattern_25_1;
            force dut.u_execute.u_ex_mem.r_reg_write = w_pattern_26_1;
            force dut.u_execute.u_ex_mem.r_halt = w_pattern_31_1;
            force dut.u_memory.u_mem_wb.r_rd = w_pattern_0_5;
            force dut.u_memory.u_mem_wb.r_mem_to_reg = w_pattern_25_1;
            force dut.u_memory.u_mem_wb.r_reg_write = w_pattern_26_1;
            force dut.u_memory.u_mem_wb.r_halt = w_pattern_31_1;
            force dut.u_if_id.r_valid = 1'b0;
            force dut.u_decode.u_id_ex.r_valid = 1'b0;
            force dut.u_execute.u_ex_mem.r_valid = 1'b0;
            force dut.u_memory.u_mem_wb.r_valid = 1'b0;
            force dut.u_if_id.r_pc = 32'ha0000000;
            force dut.u_if_id.r_instr = 32'ha0000001;
            force dut.u_decode.u_id_ex.r_pc = 32'ha0000002;
            force dut.u_decode.u_id_ex.r_rs1_data = 32'ha0000003;
            force dut.u_decode.u_id_ex.r_rs2_data = 32'ha0000004;
            force dut.u_decode.u_id_ex.r_imm = 32'ha0000005;
            force dut.u_execute.u_ex_mem.r_pc = 32'ha0000007;
            force dut.u_execute.u_ex_mem.r_result = 32'ha0000008;
            force dut.u_execute.u_ex_mem.r_store_data = 32'ha0000009;
            force dut.u_memory.u_mem_wb.r_pc = 32'ha000000b;
            force dut.u_memory.u_mem_wb.r_result = 32'ha000000c;
            force dut.u_memory.u_mem_wb.r_load_data = 32'ha000000d;
            for (bit_index = 0; bit_index < 34; bit_index = bit_index + 1) begin
                if (bit_index < 32) r_pattern = 32'd1 << bit_index;
                else if (bit_index == 32) r_pattern = 32'h84000005;
                else r_pattern = 32'hffffffff;
                #1;
                for (n = 0; n < 15; n = n + 1) begin
                    r_dbg_latch_sel = n[3:0];
                    #1;
                    casez (n)
                        6: check_word(w_dbg_latch_word, r_pattern, "EX walking info bit with valid zero");
                        10: check_word(w_dbg_latch_word, r_pattern & 32'h8783801f, "MEM walking info bit with valid zero");
                        14: check_word(w_dbg_latch_word, r_pattern & 32'h8600001f, "WB walking info bit with valid zero");
                        default: check_word(w_dbg_latch_word, 32'ha0000000 + n, "distinct retained payload");
                    endcase
                end
            end
            release dut.u_decode.u_id_ex.r_rd;
            release dut.u_decode.u_id_ex.r_rs1;
            release dut.u_decode.u_id_ex.r_rs2;
            release dut.u_decode.u_id_ex.r_funct3;
            release dut.u_decode.u_id_ex.r_alu_op;
            release dut.u_decode.u_id_ex.r_alu_src_b;
            release dut.u_decode.u_id_ex.r_mem_read;
            release dut.u_decode.u_id_ex.r_mem_write;
            release dut.u_decode.u_id_ex.r_mem_to_reg;
            release dut.u_decode.u_id_ex.r_reg_write;
            release dut.u_decode.u_id_ex.r_branch;
            release dut.u_decode.u_id_ex.r_jump;
            release dut.u_decode.u_id_ex.r_jalr;
            release dut.u_decode.u_id_ex.r_lui;
            release dut.u_decode.u_id_ex.r_halt;
            release dut.u_execute.u_ex_mem.r_rd;
            release dut.u_execute.u_ex_mem.r_funct3;
            release dut.u_execute.u_ex_mem.r_mem_read;
            release dut.u_execute.u_ex_mem.r_mem_write;
            release dut.u_execute.u_ex_mem.r_mem_to_reg;
            release dut.u_execute.u_ex_mem.r_reg_write;
            release dut.u_execute.u_ex_mem.r_halt;
            release dut.u_memory.u_mem_wb.r_rd;
            release dut.u_memory.u_mem_wb.r_mem_to_reg;
            release dut.u_memory.u_mem_wb.r_reg_write;
            release dut.u_memory.u_mem_wb.r_halt;
            release dut.u_if_id.r_valid;
            release dut.u_decode.u_id_ex.r_valid;
            release dut.u_execute.u_ex_mem.r_valid;
            release dut.u_memory.u_mem_wb.r_valid;
            release dut.u_if_id.r_pc;
            release dut.u_if_id.r_instr;
            release dut.u_decode.u_id_ex.r_pc;
            release dut.u_decode.u_id_ex.r_rs1_data;
            release dut.u_decode.u_id_ex.r_rs2_data;
            release dut.u_decode.u_id_ex.r_imm;
            release dut.u_execute.u_ex_mem.r_pc;
            release dut.u_execute.u_ex_mem.r_result;
            release dut.u_execute.u_ex_mem.r_store_data;
            release dut.u_memory.u_mem_wb.r_pc;
            release dut.u_memory.u_mem_wb.r_result;
            release dut.u_memory.u_mem_wb.r_load_data;
        end
    endtask

    task synthetic_flags;
        begin
            force dut.w_valid_id = w_flag_0;
            force dut.w_valid_ex = w_flag_1;
            force dut.w_valid_mem = w_flag_2;
            force dut.w_valid_wb = w_flag_3;
            force dut.w_halt_wb = w_flag_4;
            force dut.w_load_use_stall = w_flag_5;
            force dut.w_take_ex = w_flag_6;
            force dut.w_stop_fetch = w_flag_7;
            r_dbg_latch_sel = 15;
            for (n = 0; n < 256; n = n + 1) begin
                r_flags = n[7:0];
                #1;
                check_word(w_dbg_latch_word, (n & 32'hef) | ((n & 24) == 24 ? 16 : 0), "all flag combinations");
            end
            r_flags = 8'h18;
            #1;
            check_word(w_dbg_latch_word, 32'h18, "halted WB without stop_fetch");
            r_flags = 8'h98;
            #1;
            check_word(w_dbg_latch_word, 32'h98, "halted WB with stop_fetch");
            release dut.w_valid_id;
            release dut.w_valid_ex;
            release dut.w_valid_mem;
            release dut.w_valid_wb;
            release dut.w_halt_wb;
            release dut.w_load_use_stall;
            release dut.w_take_ex;
            release dut.w_stop_fetch;
        end
    endtask

    initial begin
        #1000000;
        $fatal(1, "FAIL tb_cpu_debug: watchdog");
    end

    initial begin
        for (n = 0; n < 256; n = n + 1) r_program[n] = 32'h00000073;
        r_program[0] = 32'h00900093;
        r_program[1] = 32'h00108133;
        r_program[2] = 32'h00202023;
        r_program[3] = 32'h00002183;
        r_program[4] = 32'h00118233;
        r_program[5] = 32'h00420663;
        r_program[6] = 32'h06300293;
        r_program[7] = 32'h00000073;
        r_program[8] = 32'h12345337;
        r_program[9] = 32'h00c003ef;
        r_program[10] = 32'h05800293;
        r_program[11] = 32'h00000073;
        r_program[12] = 32'hfff38413;
        r_program[13] = 32'h041004e7;
        r_program[14] = 32'h04d00293;
        r_program[15] = 32'h00000073;
        r_program[16] = 32'h00041463;
        r_program[17] = 32'h04200293;
        r_program[18] = 32'h00000073;
        cycle(0, 1);
        r_reset = 0;
        synthetic_info();
        synthetic_flags();
        cycle(0, 1);
        r_reset = 0;
        r_dbg_latch_sel = 4'bx000;
        #1;
        check_word(w_dbg_latch_word, 0, "unknown selector defaults to zero");
        r_dbg_latch_sel = 4'bz111;
        #1;
        check_word(w_dbg_latch_word, 0, "high impedance selector defaults to zero");
        while (!w_halted && advances < 64) begin
            cycle(0, 0);
            scan(1);
            cycle(0, 0);
            scan(1);
            cycle(1, 0);
        end
        check_word(w_halted, 1, "reachable HALT terminates program");
        check_word(dut.w_pc_wb, 72, "HALT PC in selector 11 source");
        check_word(w_dbg_pc, 76, "IF PC differs from HALT PC");
        check_word(stalls, 1, "one enabled load-use stall");
        check_word(advances, 24, "independent enabled cycles to HALT");
        check_word(takes, 4, "four reachable redirects");
        check_word(accepts, 1, "wrong path HALTs never accepted");
        check_word(r_seen_flags, 255, "all flags observed in real execution");
        check_word(captured_differences > 0, 1, "captured and forwarded operands exercised");
        check_word(retained_bubbles > 0, 1, "nonzero payload in invalid stages exercised");
        for (n = 0; n < 32; n = n + 1)
            check_word(r_expected_regs[n], register_result(n[4:0]), "independent final registers");
        repeat (3) begin
            cycle(1, 0);
            scan(1);
        end
        r_dbg_latch_sel = 15;
        #1;
        check_word(w_dbg_latch_word, 32'h98, "real halted flags");
        r_dbg_latch_sel = 11;
        #1;
        check_word(w_dbg_latch_word, 72, "public canonical HALT PC");
        cycle(0, 1);
        check_word(w_halted, 0, "reset overrides HALT and pause");
        if (errors != 0) $fatal(1, "FAIL tb_cpu_debug: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_cpu_debug: %0d checks, walking info bits, 256 flag patterns, 16 selectors and 32 registers", checks);
        $finish;
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_load_use_consumers;
    localparam ADVANCES = 127;
    reg r_clock, r_reset, r_en;
    reg [4:0] r_dbg_reg_addr;
    reg [3:0] r_dbg_latch_sel;
    reg [7:0] r_dbg_mem_addr;
    reg [31:0] r_program [0:255];
    reg [37:0] r_commits [0:255];
    reg [255:0] r_store_valid, r_hazard_at;
    reg [31:0] r_store_addr [0:255];
    reg [31:0] r_store_data [0:255];
    reg [31:0] r_regs [0:31];
    reg [31:0] r_memory [0:255];
    reg [255:0] r_dirty;
    reg [31:0] r_pc_if;
    reg [31:0] r_pc [0:3];
    reg [3:0] r_valid;
    reg [12:0] r_seen;
    reg [31:0] r_snapshot [0:303];
    reg [31:0] r_snapshot_pc;
    reg [1:0] r_snapshot_usage;
    reg r_expected_stall, r_observed_stall;
    reg [37:0] r_event;
    reg r_expected_store;
    wire [31:0] w_imem_addr;
    wire [31:0] w_imem_data = r_program[w_imem_addr[9:2]];
    wire [31:0] w_dbg_pc, w_dbg_reg_data, w_dbg_mem_data, w_dbg_latch_word;
    wire w_halted, w_dbg_mem_dirty;
    wire w_branch_equal = dut.w_rs1_fwd_ex == dut.w_rs2_fwd_ex;
    wire w_branch_condition = dut.w_funct3_ex[0] ? !w_branch_equal : w_branch_equal;
    integer checks, errors, mode, clocks, advances, stalls, writes, stores, markers;
    integer paused_hazards, consumer, index, trace_file, input_file;
    string r_root, r_program_path, r_output_path;

    cpu dut (
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .o_halted(w_halted), .o_imem_addr(w_imem_addr), .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr), .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel), .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr), .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty), .o_dbg_pc(w_dbg_pc)
    );

    task automatic check_word(input [63:0] got, input [63:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                if (errors <= 40)
                    $display("FAIL tb_load_use_consumers: mode=%0d clock=%0d advance=%0d %s expected=%h got=%h",
                             mode, clocks, advances, label, expected, got);
            end
        end
    endtask

    task automatic set_commit(input integer instruction, input [4:0] destination, input [31:0] value);
        begin
            r_commits[instruction] = {1'b1, destination, value};
        end
    endtask

    task automatic set_store(input integer instruction, input [31:0] address, input [31:0] value);
        begin
            r_store_valid[instruction] = 1'b1;
            r_store_addr[instruction] = address;
            r_store_data[instruction] = value;
        end
    endtask

    task automatic scan_state(input bit compare_snapshot);
        integer n;
        begin
            if (compare_snapshot) begin
                check_word(w_dbg_pc, r_snapshot_pc, "paused PC");
                check_word({dut.w_uses_rs1_ex, dut.w_uses_rs2_ex}, r_snapshot_usage, "paused consumption");
            end else begin
                r_snapshot_pc = w_dbg_pc;
                r_snapshot_usage = {dut.w_uses_rs1_ex, dut.w_uses_rs2_ex};
            end
            for (n = 0; n < 304; n = n + 1) begin
                if (n < 16) r_dbg_latch_sel = n[3:0];
                else if (n < 48) r_dbg_reg_addr = n - 16;
                else r_dbg_mem_addr = n - 48;
                #1;
                if (n < 16) begin
                    if (compare_snapshot) check_word(w_dbg_latch_word, r_snapshot[n], "paused latch");
                    else r_snapshot[n] = w_dbg_latch_word;
                end else if (n < 48) begin
                    if (compare_snapshot) check_word(w_dbg_reg_data, r_snapshot[n], "paused register");
                    else r_snapshot[n] = w_dbg_reg_data;
                end else begin
                    if (compare_snapshot) begin
                        check_word(w_dbg_mem_data, r_snapshot[n], "paused memory");
                        check_word(w_dbg_mem_dirty, r_dirty[n-48], "paused dirty");
                    end else r_snapshot[n] = w_dbg_mem_data;
                end
            end
        end
    endtask

    task automatic check_operands(input [1:0] select_a, input [1:0] select_b,
                                  input [31:0] value_a, input [31:0] value_b,
                                  input bit check_b, input [31:0] result, input bit check_result);
        begin
            check_word(dut.w_forward_a_ex, select_a, "consumer selector A");
            check_word(dut.w_forward_b_ex, select_b, "consumer selector B");
            check_word(dut.w_rs1_fwd_ex, value_a, "consumer operand A");
            if (check_b) check_word(dut.w_rs2_fwd_ex, value_b, "consumer operand B");
            if (check_result) check_word(dut.w_result_ex, result, "consumer EX result or address");
        end
    endtask

    task automatic check_consumer;
        integer group_index;
        reg [31:0] sentinel;
        begin
            if (dut.w_valid_ex && dut.w_pc_ex >= 32'd40 && dut.w_pc_ex <= 32'd424 &&
                (dut.w_pc_ex[4:0] == 5'd8)) begin
                group_index = (dut.w_pc_ex - 40) / 32;
                check_word(r_seen[group_index], 1'b0, "consumer enters EX once");
                r_seen[group_index] = 1'b1;
                sentinel = -group_index - 1;
                if (r_hazard_at[dut.w_pc_ex[9:2]]) begin
                    check_word(dut.w_valid_wb, 1'b1, "load ready in WB");
                    check_word(dut.w_pc_wb, dut.w_pc_ex - 32'd4, "WB belongs to immediately preceding load");
                    check_word(dut.w_load_use_stall, 1'b0, "risk released after bubble");
                    if (dut.w_rs1_ex == 5'd1)
                        check_word(dut.w_rs1_data_ex, sentinel, "captured rs1 differs from loaded value");
                    if (dut.w_rs2_ex == 5'd1)
                        check_word(dut.w_rs2_data_ex, sentinel, "captured rs2 differs from loaded value");
                end
                casez (group_index)
                    0: check_operands(2'b01, 2'b01, 73, 73, 1'b1, 146, 1'b1);
                    1: check_operands(2'b00, 2'b01, 0, 73, 1'b1, 64, 1'b1);
                    2: check_operands(2'b01, 2'b00, 96, 21, 1'b1, 100, 1'b1);
                    3: check_operands(2'b00, 2'b00, 0, 0, 1'b0, 1, 1'b1);
                    4: check_operands(2'b00, 2'b00, 21, 21, 1'b1, 42, 1'b1);
                    5: check_operands(2'b01, 2'b00, 73, 73, 1'b1, 0, 1'b0);
                    6: check_operands(2'b00, 2'b01, 21, 73, 1'b1, 0, 1'b0);
                    7: check_operands(2'b00, 2'b01, 21, 73, 1'b1, 94, 1'b1);
                    8: check_operands(2'b01, 2'b00, 73, 0, 1'b0, 75, 1'b1);
                    9: check_operands(2'b00, 2'b00, 0, 0, 1'b0, 0, 1'b1);
                    10: check_operands(2'b01, 2'b00, 73, 21, 1'b1, 0, 1'b0);
                    11: check_operands(2'b00, 2'b01, 73, 73, 1'b1, 0, 1'b0);
                    12: check_operands(2'b01, 2'b01, 96, 96, 1'b1, 104, 1'b1);
                    default: $fatal(1, "FAIL tb_load_use_consumers: unknown consumer");
                endcase
                if (group_index == 5 || group_index == 6 || group_index == 10 || group_index == 11) begin
                    check_word(dut.w_branch_ex, 1'b1, "branch decoded in EX");
                    check_word(dut.w_funct3_ex, (group_index == 6 || group_index == 11) ? 1 : 0, "BEQ/BNE harness selection");
                    check_word(w_branch_equal, (group_index == 5 || group_index == 11), "forwarded equality in harness");
                    check_word(w_branch_condition, (group_index == 5 || group_index == 6), "BEQ/BNE condition in harness");
                end
            end
        end
    endtask

    task automatic cycle(input bit enable);
        integer n;
        begin
            r_en = enable;
            #1;
            r_expected_stall = r_valid[0] && r_valid[1] && r_hazard_at[r_pc[0][9:2]] &&
                               (r_pc[1] + 32'd4 == r_pc[0]);
            r_observed_stall = dut.w_load_use_stall;
            if (!r_reset) check_word(r_observed_stall, r_expected_stall, "scheduled consumer stall");
            r_event = 38'd0;
            r_expected_store = 1'b0;
            if (enable && !r_reset) begin
                if (r_valid[3]) r_event = r_commits[r_pc[3][9:2]];
                r_expected_store = r_valid[2] && r_store_valid[r_pc[2][9:2]];
            end
            check_word(dut.w_regfile_we, r_event[37], "commit permission");
            check_word(dut.w_dmem_we, r_expected_store, "store permission");
            if (r_event[37]) begin
                check_word(dut.w_rd_wb, r_event[36:32], "commit destination");
                check_word(dut.w_wb_data, r_event[31:0], "independent commit value");
                r_regs[r_event[36:32]] = r_event[31:0];
                writes = writes + 1;
                if (r_event[36:32] == 5'd31) markers = markers + 1;
            end
            if (r_expected_store) begin
                n = r_pc[2][9:2];
                check_word(dut.w_result_mem, r_store_addr[n], "independent store address");
                check_word(dut.w_store_data_mem, r_store_data[n], "independent store data");
                r_memory[r_store_addr[n][9:2]] = r_store_data[n];
                r_dirty[r_store_addr[n][9:2]] = 1'b1;
                stores = stores + 1;
            end
            if (!enable && !r_reset) scan_state(1'b0);
            #5;
            r_clock = 1'b1;
            #1;
            clocks = clocks + 1;
            if (r_reset) begin
                advances = 0; stalls = 0; paused_hazards = 0; writes = 0; stores = 0; markers = 0;
                r_pc_if = 32'd0;
                r_valid = 4'd0; r_dirty = 256'd0; r_seen = 13'd0;
                for (n = 0; n < 4; n = n + 1) r_pc[n] = 32'd0;
                for (n = 0; n < 32; n = n + 1) r_regs[n] = 32'd0;
                for (n = 0; n < 256; n = n + 1) r_memory[n] = 32'd0;
            end else if (enable) begin
                advances = advances + 1;
                if (r_observed_stall) stalls = stalls + 1;
                r_pc[3] = r_pc[2]; r_valid[3] = r_valid[2];
                r_pc[2] = r_pc[1]; r_valid[2] = r_valid[1];
                if (r_expected_stall) begin
                    r_valid[1] = 1'b0;
                    check_word(dut.w_info_ex[31:18], 0, "bubble controls neutralized");
                end else begin
                    r_pc[1] = r_pc[0]; r_valid[1] = r_valid[0];
                    r_pc[0] = r_pc_if; r_valid[0] = 1'b1;
                    r_pc_if = r_pc_if + 32'd4;
                end
                check_consumer();
            end else begin
                if (r_observed_stall) paused_hazards = paused_hazards + 1;
                scan_state(1'b1);
            end
            check_word(w_imem_addr, r_pc_if, "IF PC and penalty");
            check_word(w_dbg_pc, r_pc_if, "debug PC");
            check_word(dut.w_pc_id, r_pc[0], "ID PC");
            check_word(dut.w_pc_ex, r_pc[1], "EX PC");
            check_word(dut.w_pc_mem, r_pc[2], "MEM PC");
            check_word(dut.w_pc_wb, r_pc[3], "WB PC");
            check_word({dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id}, r_valid, "valid pattern");
            check_word(dut.w_instr_id, r_valid[0] ? r_program[r_pc[0][9:2]] : 0, "IFID instruction");
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n[4:0];
                #1;
                check_word(w_dbg_reg_data, r_regs[n], "stored register after each clock");
            end
            $fwrite(trace_file, "%0d,%0d,%0d,%b,%b,%08h,%08h,%08h,%08h,%08h,%b%b%b%b,%b,%b,%08h,%08h\n",
                    mode, clocks, advances, r_en, r_observed_stall, w_imem_addr,
                    dut.w_pc_id, dut.w_pc_ex, dut.w_pc_mem, dut.w_pc_wb,
                    dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id,
                    dut.w_forward_a_ex, dut.w_forward_b_ex, dut.w_rs1_fwd_ex, dut.w_rs2_fwd_ex);
            #5;
            r_clock = 1'b0;
            #1;
        end
    endtask

    initial begin
        #1000000;
        $fatal(1, "FAIL tb_load_use_consumers: watchdog");
    end

    initial begin
        checks = 0; errors = 0; r_clock = 1'b0; r_reset = 1'b1; r_en = 1'b0;
        r_dbg_reg_addr = 5'd0; r_dbg_latch_sel = 4'd0; r_dbg_mem_addr = 8'd0;
        r_root = "";
        if ($value$plusargs("ROOT=%s", r_root)) begin end
        r_program_path = {r_root, "TP3_FINAL/programs/load_use.hex"};
        r_output_path = {r_root, "TP3_FINAL/build/"};
        input_file = $fopen(r_program_path, "r");
        if (!input_file) begin
            r_program_path = "load_use.hex";
            r_output_path = "";
            input_file = $fopen(r_program_path, "r");
        end
        if (!input_file) $fatal(1, "FAIL tb_load_use_consumers: missing load_use.hex");
        $fclose(input_file);
        $readmemh(r_program_path, r_program);
        trace_file = $fopen({r_output_path, "a23_trace.csv"}, "w");
        if (!trace_file) $fatal(1, "FAIL tb_load_use_consumers: cannot open trace");
        $fwrite(trace_file, "mode,clock,advance,enable,stall_before,if_pc,id_pc,ex_pc,mem_pc,wb_pc,valid,forward_a,forward_b,operand_a,operand_b\n");
        $dumpfile({r_output_path, "a23_consumers.vcd"});
        $dumpvars(0, tb_load_use_consumers);
        r_store_valid = 256'd0; r_hazard_at = 256'd0;
        for (index = 0; index < 256; index = index + 1) r_commits[index] = 38'd0;
        set_commit(0, 8, 73); set_commit(1, 9, 21); set_commit(2, 10, 96); set_commit(5, 12, 31);
        for (index = 0; index < 13; index = index + 1) begin
            set_commit(8 + 8*index, 1, -index-1);
            if (index != 9) set_commit(9 + 8*index, 1, (index == 2 || index == 12) ? 96 : 73);
            if (index != 3 && index != 4 && index != 9) r_hazard_at[10 + 8*index] = 1'b1;
        end
        set_commit(10, 2, 146); set_commit(34, 3, 1); set_commit(42, 4, 42);
        set_commit(66, 5, 94); set_commit(74, 6, 75); set_commit(82, 7, 0);
        set_commit(112, 31, 32'h0000_05a5);
        set_store(3, 0, 73); set_store(4, 4, 96);
        set_store(18, 64, 73); set_store(26, 100, 21); set_store(106, 104, 96);
        for (mode = 0; mode < 2; mode = mode + 1) begin
            clocks = 0;
            r_reset = 1'b1;
            cycle(1'b0);
            r_reset = 1'b0;
            while (advances < ADVANCES) begin
                if (mode == 1 && r_valid[0] && r_valid[1] && r_hazard_at[r_pc[0][9:2]] &&
                    (r_pc[1] + 32'd4 == r_pc[0])) begin
                    repeat (3) cycle(1'b0);
                    cycle(1'b1);
                    cycle(1'b0);
                end else cycle(1'b1);
            end
            r_en = 1'b0;
            #1;
            check_word(stalls, 10, "ten real dependencies, no false stalls");
            check_word(paused_hazards, mode == 1 ? 30 : 0, "paused risk does not add enabled stalls");
            check_word(advances, ADVANCES, "exact logical completion");
            check_word(clocks, mode == 1 ? 168 : 128, "physical clocks including reset and pauses");
            check_word(r_seen, 13'h1fff, "all thirteen consumers observed");
            check_word(writes, 36, "exact commit count");
            check_word(stores, 5, "exact store count");
            check_word(markers, 1, "marker commits once");
            for (index = 0; index < 256; index = index + 1) begin
                r_dbg_mem_addr = index[7:0];
                #1;
                check_word(w_dbg_mem_data, r_memory[index], "independent final memory");
                check_word(w_dbg_mem_dirty, r_dirty[index], "independent final dirty");
            end
            $display("TRACE tb_load_use_consumers: mode=%0d advances=%0d clocks=%0d stalls=%0d paused_hazards=%0d writes=%0d stores=%0d seen=%h",
                     mode, advances, clocks, stalls, paused_hazards, writes, stores, r_seen);
        end
        $fclose(trace_file);
        if (errors != 0) $fatal(1, "FAIL tb_load_use_consumers: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_load_use_consumers: %0d checks, 13 consumers, continuous and paused; branch operands only", checks);
        $finish;
    end
endmodule

`default_nettype wire

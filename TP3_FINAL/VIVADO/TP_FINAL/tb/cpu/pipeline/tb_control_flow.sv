`timescale 1ns/1ps
`default_nettype none

module tb_control_flow;
    localparam EVENT_BASE = 551;
    localparam EVENT_WORDS = 14;
    reg r_clock = 1'b0;
    reg r_reset = 1'b0;
    reg r_en = 1'b0;
    reg [31:0] r_program [0:255];
    reg [31:0] r_golden [0:1151];
    reg [31:0] r_regs [0:31];
    reg [31:0] r_memory [0:255];
    reg [255:0] r_dirty;
    reg [31:0] r_snapshot [0:559];
    reg [31:0] r_snapshot_pc;
    reg [4:0] r_dbg_reg_addr = 5'd0;
    reg [3:0] r_dbg_latch_sel = 4'd0;
    reg [7:0] r_dbg_mem_addr = 8'd0;
    wire [31:0] w_imem_addr, w_dbg_pc, w_dbg_reg_data, w_dbg_latch_word, w_dbg_mem_data;
    wire w_halted, w_dbg_mem_dirty;
    wire [31:0] w_imem_data = r_program[w_imem_addr[9:2]];
    integer checks = 0;
    integer errors = 0;
    integer program_index, mode, index, input_file, trace_file;
    integer clocks, advances, stalls, takes, writes, stores, markers;
    integer ex_seen, mem_seen, retired;
    reg r_expected_take, r_expected_stall;
    reg r_effective_enable, r_stop_model, r_accept_model, r_before_stopped;
    reg [31:0] r_before_pc, r_before_pc_id, r_before_pc_ex, r_before_instr_id, r_expected_target;
    string r_root, r_path, r_name, r_output_path;

    cpu dut (
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .o_halted(w_halted), .o_imem_addr(w_imem_addr), .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr), .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel), .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr), .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty), .o_dbg_pc(w_dbg_pc)
    );

    function automatic [31:0] event_word(input integer event_index, input integer field);
        begin
            event_word = r_golden[EVENT_BASE + EVENT_WORDS*event_index + field];
        end
    endfunction

    task automatic check_word(input [31:0] got, input [31:0] expected,
                              input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                if (errors <= 40)
                    $display("FAIL tb_control_flow: program=%s mode=%0d clock=%0d advance=%0d %s expected=%08h got=%08h",
                             r_name, mode, clocks, advances, label, expected, got);
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
                if (compare_snapshot) check_word(value, r_snapshot[n], "paused full snapshot");
                else r_snapshot[n] = value;
            end
        end
    endtask

    task automatic check_ex;
        integer n, e;
        begin
            r_expected_take = 1'b0;
            r_expected_target = 32'd0;
            r_expected_stall = 1'b0;
            if (dut.w_valid_ex && ex_seen > 0 && ex_seen <= r_golden[1]) begin
                e = ex_seen - 1;
                check_word(dut.w_pc_ex, event_word(e, 0), "EX trace PC");
                r_expected_take = event_word(e, 8) != 0;
                r_expected_target = event_word(e, 7);
                if (event_word(e, 6)) check_word(dut.w_target_ex, r_expected_target, "control byte target");
                if (event_word(e, 10) & 1) check_word(dut.w_rs1_fwd_ex, event_word(e, 11), "control forwarded rs1");
                if (event_word(e, 10) & 2) check_word(dut.w_rs2_fwd_ex, event_word(e, 12), "control forwarded rs2");
                if (event_word(e, 13) != 32'hffffffff)
                    check_word({28'd0, dut.w_forward_a_ex, dut.w_forward_b_ex}, event_word(e, 13), "control forwarding selectors");
            end
            for (n = 0; n < r_golden[1]; n = n + 1) begin
                if (event_word(n, 9) && dut.w_valid_ex && dut.w_valid_id &&
                    dut.w_pc_ex + 4 == event_word(n, 0) && dut.w_pc_id == event_word(n, 0))
                    r_expected_stall = 1'b1;
            end
            check_word(dut.w_take_ex, r_expected_take, "independent scheduled take");
            check_word(dut.w_load_use_stall, r_expected_stall, "independent scheduled load-use");
        end
    endtask

    task automatic step(input bit enable, input bit reset);
        integer n, e;
        reg [31:0] effects;
        reg [31:0] address;
        begin
            r_en = enable;
            r_reset = reset;
            #1;
            r_effective_enable = enable && !w_halted;
            r_before_stopped = r_stop_model;
            r_accept_model = dut.w_valid_id && dut.w_pc_id == r_golden[6] + 4 && !dut.w_take_ex && !dut.w_load_use_stall;
            r_before_pc = w_imem_addr;
            r_before_pc_id = dut.w_pc_id;
            r_before_pc_ex = dut.w_pc_ex;
            r_before_instr_id = dut.w_instr_id;
            if (!reset) begin
                check_ex();
                effects = 0;
                if (dut.w_valid_wb && retired < r_golden[1]) effects = event_word(retired, 1);
                check_word(dut.w_regfile_we, r_effective_enable && effects[0], "WB permission");
                if (dut.w_valid_wb && r_effective_enable) begin
                    if (retired >= r_golden[1]) $fatal(1, "FAIL tb_control_flow: unexpected retirement after marker");
                    check_word(dut.w_pc_wb, event_word(retired, 0), "independent retirement PC");
                    if (effects[0]) begin
                        check_word(dut.w_rd_wb, event_word(retired, 2), "WB destination");
                        check_word(dut.w_wb_data, event_word(retired, 3), "independent WB value");
                        r_regs[event_word(retired, 2)] = event_word(retired, 3);
                        writes = writes + 1;
                        if (event_word(retired, 2) == 31) begin
                            markers = markers + 1;
                            check_word(dut.w_pc_wb, r_golden[6], "marker PC");
                        end
                    end
                    retired = retired + 1;
                end
                effects = 0;
                e = mem_seen - 1;
                if (dut.w_valid_mem && mem_seen > 0 && mem_seen <= r_golden[1]) effects = event_word(e, 1);
                check_word(dut.w_dmem_we, r_effective_enable && effects[1], "MEM permission");
                if (dut.w_dmem_we) begin
                    address = event_word(e, 4);
                    check_word(dut.w_pc_mem, event_word(e, 0), "independent store PC");
                    check_word(dut.w_result_mem, address, "independent store byte address");
                    check_word(dut.w_store_data_mem, event_word(e, 5), "independent store value");
                    r_memory[address[9:2]] = event_word(e, 5);
                    r_dirty[address[9:2]] = 1'b1;
                    stores = stores + 1;
                end
            end
            $fwrite(trace_file, "%s,%0d,%0d,%0d,%b,%b,%b,%08h,%08h,%08h,%08h,%08h,%b%b%b%b,%08h,%08h,%0d\n",
                    r_name, mode, clocks, advances, enable, dut.w_take_ex, dut.w_load_use_stall,
                    w_imem_addr, dut.w_pc_id, dut.w_pc_ex, dut.w_pc_mem, dut.w_pc_wb,
                    dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id,
                    dut.w_rs1_fwd_ex, dut.w_rs2_fwd_ex, retired);
            #4;
            r_clock = 1'b1;
            #1;
            clocks = clocks + 1;
            if (reset) begin
                advances = 0; stalls = 0; takes = 0; writes = 0; stores = 0; markers = 0;
                ex_seen = 0; mem_seen = 0; retired = 0;
                r_stop_model = 0;
                r_dirty = 0;
                for (n = 0; n < 32; n = n + 1) r_regs[n] = 0;
                for (n = 0; n < 256; n = n + 1) r_memory[n] = 0;
                check_word(w_imem_addr, 0, "reset PC");
                check_word({dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id}, 0, "reset valid");
            end else if (r_effective_enable) begin
                advances = advances + 1;
                if (r_expected_take) begin
                    r_stop_model = 0;
                    takes = takes + 1;
                    check_word(w_imem_addr, r_expected_target, "redirected IF PC");
                    check_word({dut.w_valid_ex, dut.w_valid_id}, 0, "two young stages flushed");
                    check_word(dut.w_valid_mem, 1, "control instruction survives redirect");
                    check_word(dut.w_pc_mem, r_before_pc_ex, "control PC in MEM");
                end else if (r_expected_stall) begin
                    stalls = stalls + 1;
                    check_word(w_imem_addr, r_before_pc, "load-use holds IF PC");
                    check_word(dut.w_pc_id, r_before_pc_id, "load-use holds ID PC");
                    check_word(dut.w_instr_id, r_before_instr_id, "load-use holds ID instruction");
                    check_word(dut.w_valid_ex, 0, "one load-use bubble");
                end else if (r_before_stopped || r_accept_model) begin
                    r_stop_model = 1;
                    check_word(w_imem_addr, r_before_pc, "HALT stops IF while draining");
                end else check_word(w_imem_addr, r_before_pc + 4, "sequential IF PC");
                if (dut.w_valid_ex) begin
                    if (ex_seen < r_golden[1]) check_word(dut.w_pc_ex, event_word(ex_seen, 0), "arriving EX PC");
                    else begin
                        check_word(dut.w_pc_ex, r_golden[6] + 4, "HALT arrives in EX");
                        check_word(dut.w_halt_ex, 1, "extra instruction is HALT");
                        check_word(dut.w_mem_write_ex, 0, "HALT has no store");
                    end
                    ex_seen = ex_seen + 1;
                end
                if (dut.w_valid_mem) begin
                    if (mem_seen < r_golden[1]) check_word(dut.w_pc_mem, event_word(mem_seen, 0), "arriving MEM PC");
                    mem_seen = mem_seen + 1;
                end
            end
            check_word(w_dbg_pc, w_imem_addr, "public byte PC");
            check_word(w_halted, !reset && advances == r_golden[0], "HALT at exact expected advance");
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n[4:0];
                #1;
                check_word(w_dbg_reg_data, r_regs[n], "stored register after each clock");
            end
            #4;
            r_clock = 1'b0;
            #1;
        end
    endtask

    task automatic check_final;
        integer n;
        begin
            r_en = 1'b0;
            #1;
            check_word(advances, r_golden[0], "exact logical advances");
            check_word(retired, r_golden[1], "exact retirement count");
            check_word(writes, r_golden[2], "exact register writes");
            check_word(stores, r_golden[3], "exact stores");
            check_word(stalls, r_golden[4], "exact enabled load-use stalls");
            check_word(takes, r_golden[5], "exact enabled redirects");
            check_word(markers, 1, "marker committed once");
            check_word(w_halted, 1, "completion requires HALT");
            check_word({dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id}, 8, "HALT WB and empty younger stages");
            check_word(dut.w_pc_wb, r_golden[6] + 4, "HALT instruction PC");
            check_word(ex_seen, r_golden[1] + 1, "HALT enters EX once");
            check_word(mem_seen, r_golden[1] + 1, "HALT enters MEM once");
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n[4:0];
                #1;
                check_word(w_dbg_reg_data, r_golden[7+n], "independent final register");
            end
            for (n = 0; n < 256; n = n + 1) begin
                r_dbg_mem_addr = n[7:0];
                #1;
                check_word(w_dbg_mem_data, r_golden[39+n], "independent final memory");
                check_word(w_dbg_mem_dirty, r_golden[295+n], "independent final dirty");
            end
            $display("TRACE tb_control_flow: program=%s mode=%0d advances=%0d clocks=%0d retired=%0d writes=%0d stores=%0d stalls=%0d redirects=%0d",
                     r_name, mode, advances, clocks, retired, writes, stores, stalls, takes);
        end
    endtask

    initial begin
        #10000000;
        $fatal(1, "FAIL tb_control_flow: watchdog before all HALTs");
    end

    initial begin
        r_root = "";
        if ($value$plusargs("ROOT=%s", r_root)) begin end
        r_output_path = {r_root, "TP3_FINAL/build/"};
        trace_file = $fopen({r_output_path, "a26_trace.csv"}, "w");
        if (!trace_file) begin
            r_output_path = "";
            trace_file = $fopen("a26_trace.csv", "w");
        end
        if (!trace_file) $fatal(1, "FAIL tb_control_flow: cannot open trace");
        $fwrite(trace_file, "program,mode,clock,advance,enable,take,stall,if_pc,id_pc,ex_pc,mem_pc,wb_pc,valid,rs1,rs2,retired\n");
        $dumpfile({r_output_path, "a26_control_flow.vcd"});
        $dumpvars(0, tb_control_flow);
        for (program_index = 0; program_index < 3; program_index = program_index + 1) begin
            casez (program_index)
                0: r_name = "suma";
                1: r_name = "jump_link";
                2: r_name = "branch_load_use";
            endcase
            r_path = {r_root, "TP3_FINAL/programs/cpu/", r_name, ".hex"};
            input_file = $fopen(r_path, "r");
            if (!input_file) begin
                r_path = {r_name, ".hex"};
                input_file = $fopen(r_path, "r");
            end
            if (!input_file) $fatal(1, "FAIL tb_control_flow: missing program %s", r_name);
            $fclose(input_file);
            $readmemh(r_path, r_program);
            r_path = {r_root, "TP3_FINAL/programs/cpu/", r_name, ".expected.hex"};
            input_file = $fopen(r_path, "r");
            if (!input_file) begin
                r_path = {r_name, ".expected.hex"};
                input_file = $fopen(r_path, "r");
            end
            if (!input_file) $fatal(1, "FAIL tb_control_flow: missing expected state %s", r_name);
            $fclose(input_file);
            $readmemh(r_path, r_golden);
            for (mode = 0; mode < 2; mode = mode + 1) begin
                clocks = 0;
                step(1'b0, 1'b1);
                r_reset = 1'b0;
                while (!w_halted && advances < r_golden[0] + 8) begin
                    if (mode == 1 && (dut.w_take_ex || dut.w_load_use_stall || advances % 7 == 0)) begin
                        r_en = 1'b0;
                        #1;
                        scan_state(1'b0);
                        repeat (2) begin
                            step(1'b0, 1'b0);
                            scan_state(1'b1);
                        end
                    end
                    step(1'b1, 1'b0);
                    if (clocks > 500) $fatal(1, "FAIL tb_control_flow: excessive physical clocks");
                end
                check_final();
                scan_state(1'b0);
                repeat (2) begin
                    step(1'b0, 1'b0);
                    scan_state(1'b1);
                end
            end
        end
        $fclose(trace_file);
        if (errors != 0) $fatal(1, "FAIL tb_control_flow: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_control_flow: %0d checks, three programs in continuous and paused modes", checks);
        $finish;
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_load_use;
    reg r_clock;
    reg r_reset;
    reg r_en;
    reg [4:0] r_dbg_reg_addr;
    reg [3:0] r_dbg_latch_sel;
    reg [7:0] r_dbg_mem_addr;
    reg [31:0] r_program [0:255];
    reg [31:0] r_registers [0:31];
    reg [31:0] r_snapshot_regs [0:31];
    reg [31:0] r_snapshot_latches [0:15];
    reg [32:0] r_snapshot_mem [0:255];
    reg [31:0] r_snapshot_pc;
    reg [1:0] r_snapshot_usage;
    reg [31:0] r_expected_pc [0:3];
    reg [3:0] r_expected_valid;
    reg r_dependent;
    reg r_paused;
    reg r_expected_stall;
    reg r_observed_stall;
    reg r_expected_write;
    reg r_expected_store;
    reg [4:0] r_expected_rd;
    reg [31:0] r_expected_data;
    reg [31:0] r_expected_if;
    reg [31:0] r_expected_mem [0:1];
    reg [1:0] r_expected_dirty;
    wire [31:0] w_imem_addr;
    wire [31:0] w_imem_data = r_program[w_imem_addr[9:2]];
    wire w_halted;
    wire [31:0] w_dbg_reg_data;
    wire [31:0] w_dbg_latch_word;
    wire [31:0] w_dbg_mem_data;
    wire w_dbg_mem_dirty;
    wire [31:0] w_dbg_pc;
    integer checks;
    integer errors;
    integer mode;
    integer clocks;
    integer advances;
    integer stalls;
    integer paused_hazards;
    integer writes;
    integer stores;
    integer markers;
    integer trace_file;
    integer index;
    integer final_advances;

    cpu dut (
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .o_halted(w_halted), .o_imem_addr(w_imem_addr), .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr), .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel), .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr), .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty), .o_dbg_pc(w_dbg_pc)
    );

    task automatic check_word(input [63:0] got, input [63:0] expected,
                              input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                if (errors <= 30)
                    $display("FAIL tb_load_use: mode=%0d clock=%0d advance=%0d %s expected=%h got=%h",
                             mode, clocks, advances, label, expected, got);
            end
        end
    endtask

    task automatic scan_state(input bit compare_snapshot);
        integer n;
        begin
            if (compare_snapshot) begin
                check_word(w_dbg_pc, r_snapshot_pc, "paused PC");
                check_word({dut.w_uses_rs1_ex, dut.w_uses_rs2_ex}, r_snapshot_usage, "paused EX usage");
            end else begin
                r_snapshot_pc = w_dbg_pc;
                r_snapshot_usage = {dut.w_uses_rs1_ex, dut.w_uses_rs2_ex};
            end
            for (n = 0; n < 16; n = n + 1) begin
                r_dbg_latch_sel = n[3:0];
                #1;
                if (compare_snapshot) check_word(w_dbg_latch_word, r_snapshot_latches[n], "paused latch");
                else r_snapshot_latches[n] = w_dbg_latch_word;
            end
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n[4:0];
                #1;
                if (compare_snapshot) check_word(w_dbg_reg_data, r_snapshot_regs[n], "paused register");
                else r_snapshot_regs[n] = w_dbg_reg_data;
            end
            for (n = 0; n < 256; n = n + 1) begin
                r_dbg_mem_addr = n[7:0];
                #1;
                if (compare_snapshot)
                    check_word({w_dbg_mem_dirty, w_dbg_mem_data}, r_snapshot_mem[n], "paused memory and dirty");
                else r_snapshot_mem[n] = {w_dbg_mem_dirty, w_dbg_mem_data};
            end
        end
    endtask

    task automatic trace_cycle(input string phase);
        begin
            $fwrite(trace_file, "%0d,%s,%0d,%0d,%b,%b,%b,%08h,%08h,%08h,%08h,%08h,%b%b%b%b,%0d,%0d,%0d,%0d,%0d,%b,%08h,%b\n",
                    mode, phase, clocks, advances, r_reset, r_en, dut.w_load_use_stall,
                    w_imem_addr, dut.w_pc_id, dut.w_pc_ex, dut.w_pc_mem, dut.w_pc_wb,
                    dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id,
                    dut.w_rs1_id, dut.w_rs2_id, dut.w_rd_ex, dut.w_rd_mem, dut.w_rd_wb,
                    dut.w_regfile_we, dut.w_wb_data, dut.w_dmem_we);
        end
    endtask

    task automatic cycle(input bit enable);
        integer n;
        begin
            r_en = enable;
            #1;
            r_expected_stall = r_dependent && (advances == 4);
            r_observed_stall = dut.w_load_use_stall;
            if (!r_reset)
                check_word(r_observed_stall, r_expected_stall, "combinational hazard at known instruction pair");
            r_expected_write = 1'b0;
            r_expected_store = 1'b0;
            r_expected_rd = 5'd0;
            r_expected_data = 32'd0;
            if (enable && !r_reset) begin
                if (r_expected_valid[3]) begin
                    casez (r_expected_pc[3])
                        32'd0: begin r_expected_write = 1'b1; r_expected_rd = 5'd10; r_expected_data = 32'd9; end
                        32'd8: begin r_expected_write = 1'b1; r_expected_rd = 5'd1; r_expected_data = 32'd9; end
                        32'd12: begin r_expected_write = 1'b1; r_expected_rd = 5'd2; r_expected_data = r_dependent ? 32'd18 : 32'd0; end
                        32'd16: begin r_expected_write = 1'b1; r_expected_rd = 5'd3; r_expected_data = r_dependent ? 32'd19 : 32'd1; end
                        32'd24: begin r_expected_write = 1'b1; r_expected_rd = 5'd31; r_expected_data = 32'h0000_05a5; end
                        default: begin end
                    endcase
                end
                r_expected_store = r_expected_valid[2] &&
                                   ((r_expected_pc[2] == 32'd4) || (r_expected_pc[2] == 32'd20));
            end
            check_word(dut.w_regfile_we, r_expected_write, "accepted WB permission");
            check_word(dut.w_dmem_we, r_expected_store, "accepted store permission");
            if (r_expected_write) begin
                check_word(dut.w_rd_wb, r_expected_rd, "commit destination");
                check_word(dut.w_wb_data, r_expected_data, "independent commit value");
                r_registers[r_expected_rd] = r_expected_data;
                writes = writes + 1;
                if (r_expected_rd == 5'd31) markers = markers + 1;
            end
            if (r_expected_store) begin
                if (r_expected_pc[2] == 32'd4) begin
                    check_word(dut.w_result_mem, 32'd0, "initial store address");
                    check_word(dut.w_store_data_mem, 32'd9, "initial store value");
                    r_expected_mem[0] = 32'd9;
                    r_expected_dirty[0] = 1'b1;
                end else begin
                    check_word(dut.w_result_mem, 32'd4, "result store address");
                    check_word(dut.w_store_data_mem, r_dependent ? 32'd19 : 32'd1, "result store value");
                    r_expected_mem[1] = r_dependent ? 32'd19 : 32'd1;
                    r_expected_dirty[1] = 1'b1;
                end
                stores = stores + 1;
            end
            if (!enable && !r_reset) scan_state(1'b0);
            trace_cycle("before");
            #5;
            r_clock = 1'b1;
            #1;
            clocks = clocks + 1;
            if (r_reset) begin
                advances = 0;
                stalls = 0;
                paused_hazards = 0;
                writes = 0;
                stores = 0;
                markers = 0;
                r_expected_if = 32'd0;
                r_expected_valid = 4'd0;
                r_expected_dirty = 2'd0;
                r_expected_mem[0] = 32'd0;
                r_expected_mem[1] = 32'd0;
                for (n = 0; n < 4; n = n + 1) r_expected_pc[n] = 32'd0;
                for (n = 0; n < 32; n = n + 1) r_registers[n] = 32'd0;
            end else if (enable) begin
                advances = advances + 1;
                if (r_observed_stall) stalls = stalls + 1;
                r_expected_pc[3] = r_expected_pc[2];
                r_expected_valid[3] = r_expected_valid[2];
                r_expected_pc[2] = r_expected_pc[1];
                r_expected_valid[2] = r_expected_valid[1];
                if (r_expected_stall) begin
                    r_expected_valid[1] = 1'b0;
                    check_word(dut.w_info_ex[31:18], 32'd0, "bubble neutral controls");
                    check_word({dut.w_uses_rs1_ex, dut.w_uses_rs2_ex}, 32'd0, "bubble consumes no sources");
                end else begin
                    r_expected_pc[1] = r_expected_pc[0];
                    r_expected_valid[1] = r_expected_valid[0];
                    r_expected_pc[0] = r_expected_if;
                    r_expected_valid[0] = 1'b1;
                    r_expected_if = r_expected_if + 32'd4;
                end
            end else begin
                if (r_observed_stall) paused_hazards = paused_hazards + 1;
                scan_state(1'b1);
            end
            trace_cycle("after");
            check_word(w_imem_addr, r_expected_if, "IF PC with exact stall count");
            check_word(w_dbg_pc, r_expected_if, "debug IF PC");
            check_word(dut.w_pc_id, r_expected_pc[0], "ID PC retained during stall");
            check_word(dut.w_pc_ex, r_expected_pc[1], "EX PC with bubble data retained");
            check_word(dut.w_pc_mem, r_expected_pc[2], "MEM continues through stall");
            check_word(dut.w_pc_wb, r_expected_pc[3], "WB continues through stall");
            check_word({dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id}, r_expected_valid, "pipeline valid pattern");
            check_word(dut.w_instr_id, r_expected_valid[0] ? r_program[r_expected_pc[0][9:2]] : 32'd0, "IFID instruction retained");
            if (r_dependent && advances == 6 && !r_reset) begin
                check_word(dut.w_forward_a_ex, 2'b01, "load rs1 forwarded from WB");
                check_word(dut.w_forward_b_ex, 2'b01, "load rs2 forwarded from WB");
                check_word(dut.w_rs1_fwd_ex, 32'd9, "load rs1 value");
                check_word(dut.w_rs2_fwd_ex, 32'd9, "load rs2 value");
                check_word(dut.w_result_ex, 32'd18, "dependent ADD result after one bubble");
            end
            for (n = 0; n < 32; n = n + 1) begin
                r_dbg_reg_addr = n[4:0];
                #1;
                check_word(w_dbg_reg_data, r_registers[n], "stored architectural register");
            end
            for (n = 0; n < 2; n = n + 1) begin
                r_dbg_mem_addr = n[7:0];
                #1;
                check_word({w_dbg_mem_dirty, w_dbg_mem_data}, {r_expected_dirty[n], r_expected_mem[n]}, "stored memory and dirty");
            end
            check_word(w_halted, 1'b0, "bounded execution before HALT milestone");
            #5;
            r_clock = 1'b0;
            #1;
        end
    endtask

    initial begin
        #1000000;
        $fatal(1, "FAIL tb_load_use: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        r_clock = 1'b0;
        r_reset = 1'b1;
        r_en = 1'b0;
        r_dbg_reg_addr = 5'd0;
        r_dbg_latch_sel = 4'd0;
        r_dbg_mem_addr = 8'd0;
        trace_file = $fopen("TP3_FINAL/build/a22_trace.csv", "w");
        if (!trace_file) $fatal(1, "FAIL tb_load_use: cannot open trace");
        $fwrite(trace_file, "mode,phase,clock,advance,reset,enable,stall,if_pc,id_pc,ex_pc,mem_pc,wb_pc,valid,rs1_id,rs2_id,rd_ex,rd_mem,rd_wb,regfile_we,wb_data,dmem_we\n");
        $dumpfile("TP3_FINAL/build/a22_load_use.vcd");
        $dumpvars(0, tb_load_use);
        for (mode = 0; mode < 5; mode = mode + 1) begin
            r_dependent = (mode != 2) && (mode != 3);
            r_paused = (mode == 1) || (mode == 3);
            clocks = 0;
            advances = 0;
            r_reset = 1'b1;
            for (index = 0; index < 256; index = index + 1) r_program[index] = 32'h0000_0013;
            r_program[0] = 32'h0090_0513;
            r_program[1] = 32'h00a0_2023;
            r_program[2] = 32'h0000_2083;
            r_program[3] = r_dependent ? 32'h0010_8133 : 32'h0000_0133;
            r_program[4] = 32'h0011_0193;
            r_program[5] = 32'h0030_2223;
            r_program[6] = 32'h5a50_0f93;
            cycle(1'b0);
            r_reset = 1'b0;
            repeat (4) cycle(1'b1);
            if (mode == 4) begin
                cycle(1'b0);
                r_reset = 1'b1;
                cycle(1'b0);
                check_word(dut.w_load_use_stall, 1'b0, "paused reset clears pending hazard");
                r_reset = 1'b0;
                repeat (4) cycle(1'b1);
            end
            if (r_paused) repeat (3) cycle(1'b0);
            cycle(1'b1);
            if (r_paused) repeat (2) cycle(1'b0);
            final_advances = r_dependent ? 12 : 11;
            while (advances < final_advances) cycle(1'b1);
            check_word(stalls, r_dependent ? 1 : 0, "exact enabled stall count");
            check_word(paused_hazards, (r_paused && r_dependent) ? 3 : 0, "paused hazard clocks excluded from stall count");
            check_word(writes, 5, "no missing or duplicated commits");
            check_word(stores, 2, "no missing or duplicated stores");
            check_word(markers, 1, "one marker commit");
            for (index = 2; index < 256; index = index + 1) begin
                r_dbg_mem_addr = index[7:0];
                #1;
                check_word({w_dbg_mem_dirty, w_dbg_mem_data}, 33'd0, "all other memory words remain clean");
            end
            $display("TRACE tb_load_use: mode=%0d advances=%0d clocks=%0d stalls=%0d paused_hazards=%0d writes=%0d stores=%0d",
                     mode, advances, clocks, stalls, paused_hazards, writes, stores);
        end
        $fclose(trace_file);
        if (errors != 0) $fatal(1, "FAIL tb_load_use: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_load_use: %0d checks, continuous/paused dependencies, independent control and reset during hazard", checks);
        $finish;
    end
endmodule

`default_nettype wire

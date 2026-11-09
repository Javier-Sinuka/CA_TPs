`timescale 1ns/1ps
`default_nettype none

module tb_flush;
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
    reg [31:0] r_snapshot [0:559];
    reg [31:0] r_snapshot_pc;
    reg [31:0] r_value, r_target;
    reg r_taken, r_link;
    integer checks = 0;
    integer errors = 0;
    integer scenario, mode, index, advances, writes, stores, markers;

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
                    $display("FAIL tb_flush: scenario=%0d mode=%0d advance=%0d %s expected=%08h got=%08h",
                             scenario, mode, advances, label, expected, got);
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

    task automatic step(input bit enable, input bit reset);
        begin
            r_en = enable;
            r_reset = reset;
            #1;
            if (!reset) begin
                check_word(dut.w_regfile_we && !enable, 0, "no paused register write");
                check_word(dut.w_dmem_we && !enable, 0, "no paused store");
                if (dut.w_regfile_we) begin
                    writes = writes + 1;
                    casez (dut.w_pc_wb)
                        32'd0: begin
                            check_word(dut.w_rd_wb, 1, "older instruction destination");
                            check_word(dut.w_wb_data, r_value, "older instruction value");
                        end
                        32'd8: begin
                            check_word(r_link, 1, "only a jump writes at control PC");
                            check_word(dut.w_rd_wb, 5, "link register");
                            check_word(dut.w_wb_data, 12, "architectural link");
                        end
                        32'd12: begin
                            check_word(r_taken, 0, "young ID write allowed only without redirect");
                            check_word(dut.w_rd_wb, 10, "sequential destination");
                            check_word(dut.w_wb_data, 99, "sequential value");
                        end
                        default: begin
                            if (dut.w_pc_wb == r_target) begin
                                check_word(dut.w_rd_wb, 11, "target destination");
                                check_word(dut.w_wb_data, 7, "target value");
                            end else if (dut.w_pc_wb == r_target + 4) begin
                                markers = markers + 1;
                                check_word(dut.w_rd_wb, 31, "marker destination");
                                check_word(dut.w_wb_data, 32'h5a5, "marker value");
                            end else check_word(1, 0, "unexpected register write PC");
                        end
                    endcase
                end
                if (dut.w_dmem_we) begin
                    stores = stores + 1;
                    check_word(dut.w_store_data_mem, r_value, "store data");
                    if (dut.w_pc_mem == 4)
                        check_word(dut.w_result_mem, 0, "older store completes");
                    else begin
                        check_word(r_taken, 0, "wrong path store forbidden");
                        check_word(dut.w_pc_mem, 16, "sequential store PC");
                        check_word(dut.w_result_mem, 4, "sequential store address");
                    end
                end
                check_word(dut.w_valid_ex && dut.w_halt_ex, 0, "discarded HALT absent from EX");
                check_word(dut.w_valid_mem && dut.w_halt_mem, 0, "discarded HALT absent from MEM");
                check_word(dut.w_valid_wb && dut.w_halt_wb, 0, "discarded HALT absent from WB");
            end
            #4;
            r_clock = 1'b1;
            #1;
            if (reset) advances = 0;
            else if (enable) advances = advances + 1;
            #4;
            r_clock = 1'b0;
            #1;
        end
    endtask

    task automatic check_final;
        integer n;
        reg [31:0] expected;
        begin
            r_en = 1'b0;
            for (n = 0; n < 32; n = n + 1) begin
                expected = 0;
                casez (n)
                    1: expected = r_value;
                    5: expected = r_link ? 12 : 0;
                    10: expected = r_taken ? 0 : 99;
                    11: expected = 7;
                    31: expected = 32'h5a5;
                    default: begin end
                endcase
                r_dbg_reg_addr = n[4:0];
                #1;
                check_word(w_dbg_reg_data, expected, "independent final register");
            end
            for (n = 0; n < 256; n = n + 1) begin
                r_dbg_mem_addr = n[7:0];
                #1;
                expected = n == 0 || (n == 1 && !r_taken) ? r_value : 0;
                check_word(w_dbg_mem_data, expected, "independent final memory");
                check_word(w_dbg_mem_dirty, n == 0 || (n == 1 && !r_taken), "independent final dirty");
            end
            check_word(writes, 3 + r_link + !r_taken, "exact register write count");
            check_word(stores, r_taken ? 1 : 2, "exact store count");
            check_word(markers, 1, "bounded marker reached once");
            check_word(w_halted, 0, "wrong path HALT does not stop execution");
        end
    endtask

    initial begin
        #1000000;
        $fatal(1, "FAIL tb_flush: watchdog before marker completion");
    end

    initial begin
        for (scenario = 0; scenario < 8; scenario = scenario + 1) begin
            for (mode = 0; mode < 2; mode = mode + 1) begin
                r_en = 1'b0;
                writes = 0; stores = 0; markers = 0;
                r_taken = scenario != 1;
                r_link = scenario == 2 || scenario == 3 || scenario == 6 || scenario == 7;
                r_value = scenario == 3 ? 25 : scenario == 6 ? 1049 : scenario == 7 ? 27 : 1;
                r_target = scenario == 6 ? 32'h418 : scenario == 7 ? 26 : 24;
                for (index = 0; index < 256; index = index + 1)
                    r_program[index] = 32'h00000013;
                r_program[0] = scenario == 3 ? 32'h01900093 : scenario == 6 ? 32'h41900093 :
                               scenario == 7 ? 32'h01b00093 : 32'h00100093;
                r_program[1] = 32'h00102023;
                r_program[2] = scenario == 1 ? 32'h00008863 : scenario == 2 ? 32'h010002ef :
                               r_link ? 32'h000082e7 : 32'h00009863;
                r_program[3] = scenario == 4 ? 32'h00000073 : scenario == 5 ? 32'h00102223 : 32'h06300513;
                r_program[4] = scenario == 5 ? 32'h06300513 : 32'h00102223;
                r_program[6] = 32'h00700593;
                r_program[7] = 32'h5a500f93;
                step(1'b0, 1'b1);
                r_reset = 1'b0;
                repeat (4) begin
                    step(1'b1, 1'b0);
                    check_word(w_dbg_pc, advances*4, "PC before control instruction");
                end
                check_word(dut.w_take_ex, r_taken, "control decision before redirect");
                check_word(dut.w_pc_ex, 8, "control instruction PC");
                check_word(dut.w_pc_id, 12, "young ID PC");
                check_word(dut.w_instr_id, r_program[3], "young ID instruction");
                check_word(w_imem_data, r_program[4], "second young instruction in IF");
                if (r_taken && mode == 1) force dut.w_load_use_stall = 1'b1;
                if (mode == 1) begin
                    r_en = 1'b0;
                    #1;
                    scan_state(1'b0);
                    repeat (2) begin
                        step(1'b0, 1'b0);
                        scan_state(1'b1);
                        check_word(dut.w_take_ex, r_taken, "take remains pending during pause");
                    end
                end
                step(1'b1, 1'b0);
                release dut.w_load_use_stall;
                check_word(w_dbg_pc, r_taken ? r_target : 20, "redirect wins over injected stall");
                check_word(w_imem_addr, r_taken ? r_target : 20, "full byte PC exposed to imem");
                check_word({dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id},
                           r_taken ? 12 : 15, "only young stages invalidated");
                check_word(dut.w_pc_mem, 8, "control instruction enters MEM");
                check_word(dut.w_pc_wb, 4, "older instruction enters WB");
                if (r_taken) begin
                    check_word(dut.w_info_ex[31:18], 0, "flushed EX effects neutralized");
                    check_word(dut.w_instr_id, r_program[3], "invalid IFID retains payload");
                end
                step(1'b1, 1'b0);
                if (r_taken) begin
                    check_word(dut.w_pc_id, r_target, "target PC captured in ID");
                    check_word(dut.w_instr_id, 32'h00700593, "target instruction fetched by index");
                    check_word(dut.w_valid_id, 1, "target ID valid");
                    check_word(dut.w_valid_wb, 1, "control instruction survives to WB");
                    check_word(dut.w_pc_wb, 8, "control WB PC");
                    if (r_link) check_word(dut.w_wb_data, 12, "link survives flush");
                end
                repeat (6) step(1'b1, 1'b0);
                check_final();
            end
        end

        scenario = 8;
        mode = 0;
        writes = 0; stores = 0; markers = 0;
        r_link = 1'b0; r_taken = 1'b1; r_value = 1; r_target = 24;
        r_program[0] = 32'h00100093;
        r_program[1] = 32'h00102023;
        r_program[2] = 32'h00009863;
        step(1'b0, 1'b1);
        repeat (4) step(1'b1, 1'b0);
        check_word(dut.w_take_ex, 1, "reset test has pending redirect");
        force dut.w_load_use_stall = 1'b1;
        step(1'b0, 1'b1);
        release dut.w_load_use_stall;
        check_word(w_dbg_pc, 0, "reset wins over paused redirect and stall");
        check_word({dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id}, 0, "reset clears every valid");
        check_word(dut.w_take_ex, 0, "reset clears pending take");
        r_dbg_reg_addr = 1;
        r_dbg_mem_addr = 0;
        #1;
        check_word(w_dbg_reg_data, 0, "reset cancels older pending register write");
        check_word(w_dbg_mem_data, 0, "reset clears logical memory");
        check_word(w_dbg_mem_dirty, 0, "reset clears dirty");

        if (errors != 0)
            $fatal(1, "FAIL tb_flush: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_flush: %0d checks, 16 program runs and reset priority", checks);
        $finish;
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_raw;
    localparam integer ADVANCES = 80;
    reg r_clock = 1'b0;
    reg r_reset = 1'b1;
    reg r_en = 1'b0;
    reg [4:0] r_dbg_reg_addr = 5'd0;
    reg [3:0] r_dbg_latch_sel = 4'd0;
    reg [7:0] r_dbg_mem_addr = 8'd0;
    reg [31:0] r_program [0:255];
    reg [31:0] r_expected_regs [0:31];
    wire [31:0] w_imem_addr;
    wire [31:0] w_imem_data = r_program[w_imem_addr[9:2]];
    wire w_halted;
    wire [31:0] w_dbg_reg_data;
    wire [31:0] w_dbg_latch_word;
    wire [31:0] w_dbg_mem_data;
    wire w_dbg_mem_dirty;
    wire [31:0] w_dbg_pc;
    reg [11:0] r_seen;
    string r_root;
    string r_program_path;
    integer input_file;
    integer checks;
    integer errors;
    integer advances;
    integer index;

    cpu dut (
        .i_clock(r_clock),
        .i_reset(r_reset),
        .i_en(r_en),
        .o_halted(w_halted),
        .o_imem_addr(w_imem_addr),
        .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr),
        .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel),
        .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr),
        .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty),
        .o_dbg_pc(w_dbg_pc)
    );

    task automatic check_word(input [31:0] got, input [31:0] expected,
                              input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL tb_raw: advance=%0d pc_ex=%08h %s expected=%08h got=%08h",
                         advances, dut.w_pc_ex, label, expected, got);
            end
        end
    endtask

    task automatic check_path(input [1:0] expected_a, input [1:0] expected_b,
                              input [31:0] expected_result);
        begin
            check_word({30'd0, dut.w_forward_a_ex}, {30'd0, expected_a}, "selector rs1");
            check_word({30'd0, dut.w_forward_b_ex}, {30'd0, expected_b}, "selector rs2");
            check_word(dut.w_result_ex, expected_result, "EX result");
        end
    endtask

    task automatic check_pipeline;
        begin
            check_word(w_imem_addr, (advances < 77 ? advances : 77)*4, "IF advances without stall");
            check_word(w_dbg_pc, (advances < 77 ? advances : 77)*4, "debug PC advances");
            check_word({31'd0, dut.w_valid_id}, advances > 0 && advances <= 77, "ID valid");
            check_word({31'd0, dut.w_valid_ex}, advances > 1 && advances <= 78, "EX valid");
            check_word({31'd0, dut.w_valid_mem}, advances > 2 && advances <= 79, "MEM valid");
            check_word({31'd0, dut.w_valid_wb}, advances > 3 && advances <= 80, "WB valid");
            if (advances > 1)
                check_word(dut.w_pc_ex, (advances-2 < 76 ? advances-2 : 76)*4, "EX PC without bubble");
            check_word({31'd0, dut.w_dmem_we}, 32'd0, "no store");
            check_word({31'd0, w_halted}, advances == ADVANCES, "HALT at expected advance");
            if (dut.w_valid_ex) begin
                casez (dut.w_pc_ex)
                    32'd4: begin
                        r_seen[0] = 1'b1;
                        check_path(2'b10, 2'b00, 32'd14);
                        check_word(dut.w_rs1_fwd_ex, 32'd11, "distance 1 rs1 value");
                    end
                    32'd24: begin
                        r_seen[1] = 1'b1;
                        check_path(2'b00, 2'b10, 32'd7);
                        check_word(dut.w_rs2_fwd_ex, 32'd7, "distance 1 rs2 value");
                    end
                    32'd48: begin
                        r_seen[2] = 1'b1;
                        check_path(2'b01, 2'b00, 32'd24);
                        check_word(dut.w_rs1_fwd_ex, 32'd20, "distance 2 rs1 value");
                    end
                    32'd72: begin
                        r_seen[3] = 1'b1;
                        check_path(2'b00, 2'b01, 32'hffff_fff7);
                        check_word(dut.w_rs2_fwd_ex, 32'd9, "distance 2 rs2 value");
                    end
                    32'd100: begin
                        r_seen[4] = 1'b1;
                        check_path(2'b00, 2'b00, 32'd35);
                        check_word(dut.w_rs1_data_ex, 32'd30, "distance 3 rs1 captured at ID");
                        check_word(dut.w_rs1_fwd_ex, 32'd30, "distance 3 rs1 value");
                    end
                    32'd128: begin
                        r_seen[5] = 1'b1;
                        check_path(2'b00, 2'b00, 32'd12);
                        check_word(dut.w_rs2_data_ex, 32'd12, "distance 3 rs2 captured at ID");
                        check_word(dut.w_rs2_fwd_ex, 32'd12, "distance 3 rs2 value");
                    end
                    32'd152: begin
                        r_seen[6] = 1'b1;
                        check_path(2'b01, 2'b10, 32'd10);
                        check_word(dut.w_rs1_fwd_ex, 32'd4, "dual source rs1");
                        check_word(dut.w_rs2_fwd_ex, 32'd6, "dual source rs2");
                    end
                    32'd176: begin
                        r_seen[7] = 1'b1;
                        check_path(2'b10, 2'b00, 32'd7);
                        check_word(dut.w_result_mem, 32'd3, "young x16 value");
                        check_word(dut.w_wb_data, 32'd1, "old x16 value");
                        check_word(dut.w_rs1_fwd_ex, 32'd3, "young x16 wins");
                    end
                    32'd196: begin
                        r_seen[8] = 1'b1;
                        check_path(2'b00, 2'b00, 32'd5);
                        check_word(dut.w_rs1_fwd_ex, 32'd0, "x0 never forwarded");
                    end
                    32'd224: begin
                        r_seen[9] = 1'b1;
                        check_path(2'b00, 2'b00, 32'd4);
                    end
                    32'd248: begin
                        r_seen[10] = 1'b1;
                        check_path(2'b10, 2'b01, 32'd2);
                        check_word(dut.w_rs1_fwd_ex, 32'd4, "reverse dual rs1");
                        check_word(dut.w_rs2_fwd_ex, 32'd2, "reverse dual rs2");
                    end
                    32'd272: begin
                        r_seen[11] = 1'b1;
                        check_path(2'b00, 2'b10, 32'd8);
                        check_word(dut.w_result_mem, 32'd8, "young x29 value");
                        check_word(dut.w_wb_data, 32'd3, "old x29 value");
                        check_word(dut.w_rs2_fwd_ex, 32'd8, "young x29 wins");
                    end
                    default: begin end
                endcase
            end
        end
    endtask

    initial begin
        forever #5 r_clock = ~r_clock;
    end

    initial begin
        #10000;
        $fatal(1, "FAIL tb_raw: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        advances = 0;
        r_seen = 12'd0;
        r_root = "";
        if ($value$plusargs("ROOT=%s", r_root)) begin end
        r_program_path = {r_root, "TP3_FINAL/programs/cpu/raw_distance.hex"};
        input_file = $fopen(r_program_path, "r");
        if (!input_file) begin
            r_program_path = "raw_distance.hex";
            input_file = $fopen(r_program_path, "r");
        end
        if (!input_file)
            $fatal(1, "FAIL tb_raw: missing raw_distance.hex");
        $fclose(input_file);
        $readmemh(r_program_path, r_program);

        for (index = 0; index < 32; index = index + 1)
            r_expected_regs[index] = 32'd0;
        r_expected_regs[1] = 32'd11;
        r_expected_regs[2] = 32'd14;
        r_expected_regs[3] = 32'd7;
        r_expected_regs[4] = 32'd7;
        r_expected_regs[5] = 32'd20;
        r_expected_regs[6] = 32'd24;
        r_expected_regs[7] = 32'd9;
        r_expected_regs[8] = 32'hffff_fff7;
        r_expected_regs[9] = 32'd30;
        r_expected_regs[10] = 32'd35;
        r_expected_regs[11] = 32'd12;
        r_expected_regs[12] = 32'd12;
        r_expected_regs[13] = 32'd4;
        r_expected_regs[14] = 32'd6;
        r_expected_regs[15] = 32'd10;
        r_expected_regs[16] = 32'd3;
        r_expected_regs[17] = 32'd7;
        r_expected_regs[18] = 32'd5;
        r_expected_regs[19] = 32'd1;
        r_expected_regs[20] = 32'd2;
        r_expected_regs[21] = 32'd3;
        r_expected_regs[23] = 32'd4;
        r_expected_regs[26] = 32'd2;
        r_expected_regs[27] = 32'd4;
        r_expected_regs[28] = 32'd2;
        r_expected_regs[29] = 32'd8;
        r_expected_regs[30] = 32'd8;
        r_expected_regs[31] = 32'd1445;

        @(posedge r_clock);
        #1;
        @(negedge r_clock);
        r_reset = 1'b0;
        r_en = 1'b1;
        while (!w_halted && advances < ADVANCES + 8) begin
            @(posedge r_clock);
            #1;
            advances = advances + 1;
            check_pipeline();
        end
        check_word(w_halted, 1, "completion requires HALT");
        check_word({dut.w_valid_wb, dut.w_valid_mem, dut.w_valid_ex, dut.w_valid_id}, 8, "HALT WB and empty younger stages");
        check_word(dut.w_pc_wb, 304, "HALT instruction PC");
        @(negedge r_clock);
        r_en = 1'b0;
        check_word({20'd0, r_seen}, 32'h0000_0fff, "all RAW cases observed");
        check_word(advances, ADVANCES, "exact advancement count");
        for (index = 0; index < 32; index = index + 1) begin
            r_dbg_reg_addr = index[4:0];
            #1;
            check_word(w_dbg_reg_data, r_expected_regs[index], "independent final register");
        end
        for (index = 0; index < 256; index = index + 1) begin
            r_dbg_mem_addr = index[7:0];
            #1;
            check_word(w_dbg_mem_data, 32'd0, "memory remains zero");
            check_word({31'd0, w_dbg_mem_dirty}, 32'd0, "memory remains clean");
        end

        if (errors != 0)
            $fatal(1, "FAIL tb_raw: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_raw: %0d checks, %0d advances without stalls", checks, advances);
        $finish;
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_branch_execute;
    reg r_clock = 1'b0;
    reg r_reset = 1'b1;
    reg r_en = 1'b0;
    reg [31:0] r_program [0:255];
    reg [4:0] r_dbg_reg_addr = 5'd5;
    wire [31:0] w_imem_addr;
    wire [31:0] w_dbg_pc;
    wire [31:0] w_dbg_reg_data;
    wire [31:0] w_imem_data = r_program[w_imem_addr[9:2]];
    reg r_probe_we = 1'b0;
    reg [7:0] r_probe_addr = 8'd0;
    reg [31:0] r_probe_data = 32'd0;
    wire [31:0] w_probe_data;
    reg r_valid = 1'b0;
    reg r_branch = 1'b0;
    reg r_jump = 1'b0;
    reg r_jalr = 1'b0;
    reg [2:0] r_funct3 = 3'd0;
    reg [31:0] r_pc = 32'd0;
    reg [31:0] r_imm = 32'd0;
    reg [31:0] r_a = 32'd0;
    reg [31:0] r_b = 32'd0;
    integer checks = 0;
    integer errors = 0;
    integer index;
    integer scenario;
    integer cycle;
    integer stalls;
    integer observations;
    reg [31:0] r_expected_target;
    reg [31:0] r_expected_link;
    reg r_expected_take;
    reg [1:0] r_expected_forward_a;
    reg [1:0] r_expected_forward_b;
    reg [31:0] r_operation_pc;

    cpu dut (
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .o_halted(), .o_imem_addr(w_imem_addr), .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr), .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(4'd0), .o_dbg_latch_word(),
        .i_dbg_mem_addr(8'd0), .o_dbg_mem_data(), .o_dbg_mem_dirty(),
        .o_dbg_pc(w_dbg_pc)
    );

    imem u_target_probe (
        .i_clock(r_clock), .i_raddr(dut.w_target_ex[9:2]),
        .o_rdata(w_probe_data), .i_we(r_probe_we),
        .i_waddr(r_probe_addr), .i_wdata(r_probe_data)
    );

    always #5 r_clock = ~r_clock;

    task automatic check_word(input [31:0] got, input [31:0] expected,
                              input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL tb_branch_execute: scenario=%0d %s expected=%08h got=%08h",
                         scenario, label, expected, got);
            end
        end
    endtask

    task automatic isolated(input bit valid, input bit branch, input bit jump,
                            input bit jalr, input [2:0] funct3,
                            input [31:0] pc, input [31:0] immediate,
                            input [31:0] a, input [31:0] b,
                            input bit take, input [31:0] target);
        begin
            @(negedge r_clock);
            r_valid = valid;
            r_branch = branch;
            r_jump = jump;
            r_jalr = jalr;
            r_funct3 = funct3;
            r_pc = pc;
            r_imm = immediate;
            r_a = a;
            r_b = b;
            #1;
            check_word(dut.w_take_ex, take, "isolated take");
            check_word(dut.w_target_ex, target, "isolated byte target");
            if (jump) check_word(dut.w_result_ex, pc + 32'd4, "link separate from target");
        end
    endtask

    task automatic check_operation;
        begin
            check_word(dut.w_take_ex, r_expected_take, "pipeline take");
            check_word(dut.w_target_ex, r_expected_target, "pipeline target");
            check_word(dut.w_forward_a_ex, r_expected_forward_a, "forwarding A");
            check_word(dut.w_forward_b_ex, r_expected_forward_b, "forwarding B");
            if (dut.w_jump_ex)
                check_word(dut.w_result_ex, r_expected_link, "pipeline link");
            if (scenario < 4) begin
                check_word(dut.w_rs1_data_ex, 32'd0, "captured A differs from forwarded A");
                check_word(dut.w_rs2_data_ex, 32'd0, "captured B differs from forwarded B");
                check_word(dut.w_rs1_fwd_ex, 32'd7, "forwarded A value");
                check_word(dut.w_rs2_fwd_ex, scenario == 1 || scenario == 2 ? 32'd9 : 32'd7,
                           "forwarded B value");
            end
        end
    endtask

    initial begin
        #100000;
        $fatal(1, "FAIL tb_branch_execute: watchdog");
    end

    initial begin
        scenario = -1;
        for (index = 0; index < 256; index = index + 1)
            r_program[index] = 32'h00000013;
        force dut.w_valid_ex = r_valid;
        force dut.w_branch_ex = r_branch;
        force dut.w_jump_ex = r_jump;
        force dut.w_jalr_ex = r_jalr;
        force dut.w_funct3_ex = r_funct3;
        force dut.w_pc_ex = r_pc;
        force dut.w_imm_ex = r_imm;
        force dut.w_rs1_fwd_ex = r_a;
        force dut.w_rs2_fwd_ex = r_b;

        isolated(1, 1, 0, 0, 0, 32'h40, -32'd4, 7, 7, 1, 32'h3c);
        isolated(1, 1, 0, 0, 0, 32'h40, 8, 7, 9, 0, 32'h48);
        isolated(1, 1, 0, 0, 1, 32'h40, -32'd4, 7, 9, 1, 32'h3c);
        isolated(1, 1, 0, 0, 1, 32'h40, 8, 7, 7, 0, 32'h48);
        isolated(0, 1, 0, 0, 0, 32'h40, 8, 7, 7, 0, 32'h48);
        isolated(0, 1, 0, 0, 1, 32'h40, 8, 7, 9, 0, 32'h48);
        isolated(0, 0, 1, 0, 0, 32'h40, 8, 0, 0, 0, 32'h48);
        isolated(0, 0, 1, 1, 0, 32'h40, 0, 32'h41, 0, 0, 32'h40);
        isolated(1, 0, 0, 0, 0, 32'h40, 0, 7, 7, 0, 32'h40);
        for (index = 2; index < 8; index = index + 1)
            isolated(1, 1, 0, 0, index[2:0], 32'h40, 8, 7, 9, 0, 32'h48);
        isolated(1, 1, 0, 0, 0, 0, -32'd4096, 32'hffffffff, 32'hffffffff, 1, 32'hfffff000);
        isolated(1, 1, 0, 0, 1, 32'hfffffffc, 4094, 32'h80000000, 0, 1, 32'h00000ffa);
        isolated(1, 0, 1, 0, 0, 32'h40, 1048574, 0, 0, 1, 32'h0010003e);
        isolated(1, 0, 1, 0, 0, 0, -32'd1048576, 0, 0, 1, 32'hfff00000);
        isolated(1, 0, 1, 0, 0, 32'hfffffffc, 8, 0, 0, 1, 4);
        isolated(1, 0, 1, 1, 0, 32'h40, 0, 32'h41, 0, 1, 32'h40);
        isolated(1, 0, 1, 1, 0, 32'h40, 0, 32'h43, 0, 1, 32'h42);
        isolated(1, 0, 1, 1, 0, 32'h40, -32'd2048, 32'h1001, 0, 1, 32'h800);
        isolated(1, 0, 1, 1, 0, 32'h40, 2047, 32'hfffffffe, 0, 1, 32'h7fc);
        isolated(1, 0, 1, 1, 0, 32'h40, -32'd1, 0, 0, 1, 32'hfffffffe);

        @(negedge r_clock);
        r_probe_we = 1'b1;
        r_probe_addr = 8'd16;
        r_probe_data = 32'h123450b7;
        @(negedge r_clock);
        r_probe_addr = 8'd255;
        r_probe_data = 32'hfff00093;
        @(negedge r_clock);
        r_probe_we = 1'b0;
        isolated(1, 0, 1, 1, 0, 32'h40, 0, 32'h41, 0, 1, 32'h40);
        check_word(w_probe_data, 32'h123450b7, "target index 16");
        isolated(1, 0, 1, 1, 0, 32'h40, 0, 32'h443, 0, 1, 32'h442);
        check_word(w_probe_data, 32'h123450b7, "high bits and bit 1 ignored only by imem index");
        isolated(1, 0, 1, 1, 0, 32'h40, 0, 32'hffffffff, 0, 1, 32'hfffffffe);
        check_word(w_probe_data, 32'hfff00093, "wrapped index 255");

        @(negedge r_clock);
        release dut.w_valid_ex;
        release dut.w_branch_ex;
        release dut.w_jump_ex;
        release dut.w_jalr_ex;
        release dut.w_funct3_ex;
        release dut.w_pc_ex;
        release dut.w_imm_ex;
        release dut.w_rs1_fwd_ex;
        release dut.w_rs2_fwd_ex;

        for (scenario = 0; scenario < 12; scenario = scenario + 1) begin
            @(negedge r_clock);
            r_reset = 1'b1;
            r_en = 1'b0;
            for (index = 0; index < 256; index = index + 1)
                r_program[index] = 32'h00000013;
            r_operation_pc = 8;
            r_expected_link = 12;
            r_expected_forward_a = 2'b01;
            r_expected_forward_b = 2'b10;
            r_expected_take = 1'b1;
            casez (scenario)
                0, 1, 2, 3: begin
                    r_program[0] = 32'h00700093;
                    r_program[1] = scenario == 1 || scenario == 2 ? 32'h00900113 : 32'h00700113;
                    casez (scenario)
                        0: r_program[2] = 32'hfe208ee3;
                        1: r_program[2] = 32'h00208463;
                        2: r_program[2] = 32'hfe209ce3;
                        3: r_program[2] = 32'h00209463;
                    endcase
                    r_expected_take = scenario == 0 || scenario == 2;
                    r_expected_target = scenario == 0 ? 4 : scenario == 2 ? 0 : 16;
                end
                4, 5: begin
                    r_program[scenario == 4 ? 0 : 1] = scenario == 4 ? 32'h04100093 : 32'h04300093;
                    r_program[2] = 32'h000082e7;
                    r_expected_forward_a = scenario == 4 ? 2'b01 : 2'b10;
                    r_expected_forward_b = 2'b00;
                    r_expected_target = scenario == 4 ? 64 : 66;
                end
                6, 7: begin
                    r_program[2] = scenario == 6 ? 32'hffdff2ef : 32'h0080006f;
                    r_expected_forward_a = 2'b00;
                    r_expected_forward_b = 2'b00;
                    r_expected_target = scenario == 6 ? 4 : 16;
                end
                8, 9: begin
                    r_program[0] = 32'h04100093;
                    r_program[1] = 32'h00102023;
                    r_program[2] = 32'h00002083;
                    r_program[3] = scenario == 8 ? 32'h000082e7 : 32'h00008463;
                    r_operation_pc = 12;
                    r_expected_link = 16;
                    r_expected_forward_a = 2'b01;
                    r_expected_forward_b = 2'b00;
                    r_expected_target = scenario == 8 ? 64 : 20;
                    r_expected_take = scenario == 8;
                end
                10: begin
                    r_program[0] = 32'h00700093;
                    r_program[1] = 32'h00900093;
                    r_program[2] = 32'hfe008ee3;
                    r_expected_forward_a = 2'b10;
                    r_expected_forward_b = 2'b00;
                    r_expected_target = 4;
                    r_expected_take = 1'b0;
                end
                11: begin
                    r_program[1] = 32'h04100013;
                    r_program[2] = 32'h001002e7;
                    r_expected_forward_a = 2'b00;
                    r_expected_forward_b = 2'b00;
                    r_expected_target = 0;
                end
            endcase
            @(posedge r_clock);
            #1;
            check_word(dut.w_take_ex, 0, "reset invalidates branch");
            @(negedge r_clock);
            r_reset = 1'b0;
            r_en = 1'b1;
            stalls = 0;
            observations = 0;
            for (cycle = 0; cycle < 12 && observations == 0; cycle = cycle + 1) begin
                #1;
                if (dut.w_load_use_stall) stalls = stalls + 1;
                @(posedge r_clock);
                #1;
                check_word(w_dbg_pc, (cycle + 1 - stalls)*4, "sequential IF before first control transfer");
                if (dut.w_valid_ex && dut.w_pc_ex == r_operation_pc) begin
                    observations = observations + 1;
                    check_operation();
                    @(negedge r_clock);
                    r_en = 1'b0;
                    repeat (2) begin
                        @(posedge r_clock);
                        #1;
                        check_operation();
                        check_word(w_dbg_pc, (cycle + 1 - stalls)*4, "paused IF");
                    end
                    @(negedge r_clock);
                    r_en = 1'b1;
                end else @(negedge r_clock);
            end
            repeat (4) begin
                @(posedge r_clock);
                #1;
                @(negedge r_clock);
            end
            check_word(observations, 1, "operation observed exactly once");
            check_word(stalls, scenario == 8 || scenario == 9 ? 1 : 0, "load-use count");
            check_word(w_dbg_reg_data, scenario == 4 || scenario == 5 || scenario == 6 || scenario == 11 ? 12 :
                       scenario == 8 ? 16 : 0, "WB stores link instead of target");
        end
        if (errors != 0)
            $fatal(1, "FAIL tb_branch_execute: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_branch_execute: %0d checks, isolated evaluation and 12 pipeline scenarios", checks);
        $finish;
    end
endmodule

`default_nettype wire

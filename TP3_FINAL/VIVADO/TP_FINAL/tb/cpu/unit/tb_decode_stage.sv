`timescale 1ns/1ps
`default_nettype none

module tb_decode_stage;
    reg r_clock, r_reset, r_en, r_flush, r_stall, r_valid_id;
    reg [31:0] r_pc_id, r_instr_id;
    reg r_valid_wb, r_reg_write_wb;
    reg [4:0] r_rd_wb, r_dbg_reg_addr;
    reg [31:0] r_wdata_wb;
    wire [31:0] w_dbg_reg_data;
    wire w_valid_ex;
    wire [31:0] w_pc_ex;
    wire [31:0] w_rs1_data_ex;
    wire [31:0] w_rs2_data_ex;
    wire [31:0] w_imm_ex;
    wire [4:0] w_rd_ex;
    wire [4:0] w_rs1_ex;
    wire [4:0] w_rs2_ex;
    wire [2:0] w_funct3_ex;
    wire [3:0] w_alu_op_ex;
    wire w_alu_src_b_ex;
    wire w_mem_read_ex;
    wire w_mem_write_ex;
    wire w_mem_to_reg_ex;
    wire w_reg_write_ex;
    wire w_branch_ex;
    wire w_jump_ex;
    wire w_jalr_ex;
    wire w_lui_ex;
    wire w_halt_ex;
    wire w_uses_rs1_ex;
    wire w_uses_rs2_ex;
    wire [31:0] w_info_ex;
    wire [15:0] w_controls_ex;
    reg [31:0] r_model [0:31];
    reg [31:0] r_imm_id_expected;
    reg [15:0] r_controls_id_expected;
    reg [31:0] r_pc_expected, r_instr_expected, r_imm_expected;
    reg [31:0] r_rs1_expected, r_rs2_expected;
    reg [15:0] r_controls_expected;
    reg r_valid_expected;
    integer checks, errors, index, cycles;
    reg [31:0] r_seed;

    decode_stage dut (
        .i_clock(r_clock),
        .i_reset(r_reset),
        .i_en(r_en),
        .i_flush(r_flush),
        .i_stall(r_stall),
        .i_valid_id(r_valid_id),
        .i_pc_id(r_pc_id),
        .i_instr_id(r_instr_id),
        .i_valid_wb(r_valid_wb),
        .i_reg_write_wb(r_reg_write_wb),
        .i_rd_wb(r_rd_wb),
        .i_wdata_wb(r_wdata_wb),
        .i_dbg_reg_addr(r_dbg_reg_addr),
        .o_valid_ex(w_valid_ex),
        .o_pc_ex(w_pc_ex),
        .o_rs1_data_ex(w_rs1_data_ex),
        .o_rs2_data_ex(w_rs2_data_ex),
        .o_imm_ex(w_imm_ex),
        .o_rd_ex(w_rd_ex),
        .o_rs1_ex(w_rs1_ex),
        .o_rs2_ex(w_rs2_ex),
        .o_funct3_ex(w_funct3_ex),
        .o_alu_op_ex(w_alu_op_ex),
        .o_alu_src_b_ex(w_alu_src_b_ex),
        .o_mem_read_ex(w_mem_read_ex),
        .o_mem_write_ex(w_mem_write_ex),
        .o_mem_to_reg_ex(w_mem_to_reg_ex),
        .o_reg_write_ex(w_reg_write_ex),
        .o_branch_ex(w_branch_ex),
        .o_jump_ex(w_jump_ex),
        .o_jalr_ex(w_jalr_ex),
        .o_lui_ex(w_lui_ex),
        .o_halt_ex(w_halt_ex),
        .o_uses_rs1_ex(w_uses_rs1_ex),
        .o_uses_rs2_ex(w_uses_rs2_ex),
        .o_info_ex(w_info_ex),
        .o_dbg_reg_data(w_dbg_reg_data)
    );

    assign w_controls_ex = {
        w_alu_op_ex, w_alu_src_b_ex, w_mem_read_ex, w_mem_write_ex, w_mem_to_reg_ex, w_reg_write_ex, w_branch_ex, w_jump_ex, w_jalr_ex, w_lui_ex, w_halt_ex, w_uses_rs1_ex, w_uses_rs2_ex
    };

    function automatic [31:0] expected_info;
        input [31:0] instruction;
        input [15:0] controls;
        integer bit_position;
        begin
            expected_info = 32'd0;
            expected_info[4:0] = instruction[11:7];
            expected_info[9:5] = instruction[19:15];
            expected_info[14:10] = instruction[24:20];
            expected_info[17:15] = instruction[14:12];
            expected_info[21:18] = controls[15:12];
            for (bit_position = 0; bit_position < 10; bit_position = bit_position + 1)
                expected_info[22 + bit_position] = controls[11 - bit_position];
        end
    endfunction

    function automatic [31:0] read_operand(input [4:0] address);
        begin
            if (address == 5'd0)
                read_operand = 32'd0;
            else if (r_en && !r_reset && r_valid_wb && r_reg_write_wb && r_rd_wb == address)
                read_operand = r_wdata_wb;
            else
                read_operand = r_model[address];
        end
    endfunction

    task automatic check_word(input [31:0] got, input [31:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL decode_stage: cycle=%0d %s expected=%08h got=%08h", cycles, label, expected, got);
            end
        end
    endtask

    task automatic check_outputs;
        begin
            check_word({31'd0, w_valid_ex}, {31'd0, r_valid_expected}, "valid");
            check_word(w_pc_ex, r_pc_expected, "instruction PC");
            check_word(w_rs1_data_ex, r_rs1_expected, "rs1 captured");
            check_word(w_rs2_data_ex, r_rs2_expected, "rs2 captured");
            check_word(w_imm_ex, r_imm_expected, "immediate");
            check_word({27'd0, w_rd_ex}, {27'd0, r_instr_expected[11:7]}, "rd");
            check_word({27'd0, w_rs1_ex}, {27'd0, r_instr_expected[19:15]}, "rs1");
            check_word({27'd0, w_rs2_ex}, {27'd0, r_instr_expected[24:20]}, "rs2");
            check_word({29'd0, w_funct3_ex}, {29'd0, r_instr_expected[14:12]}, "funct3");
            check_word({16'd0, w_controls_ex}, {16'd0, r_controls_expected}, "controls and consumption");
            check_word(w_info_ex, expected_info(r_instr_expected, r_controls_expected), "info layout");
            check_word(w_dbg_reg_data, r_model[r_dbg_reg_addr], "debug stored data");
        end
    endtask

    task automatic tick;
        begin
            @(posedge r_clock);
            cycles = cycles + 1;
            if (r_reset) begin
                r_pc_expected = 32'd0;
                r_instr_expected = 32'd0;
                r_imm_expected = 32'd0;
                r_rs1_expected = 32'd0;
                r_rs2_expected = 32'd0;
                r_controls_expected = 16'd0;
                r_valid_expected = 1'b0;
            end else if (r_en) begin
                if (r_flush) begin
                    r_valid_expected = 1'b0;
                    r_controls_expected = 16'd0;
                end else if (!r_stall) begin
                    r_pc_expected = r_pc_id;
                    r_instr_expected = r_instr_id;
                    r_imm_expected = r_imm_id_expected;
                    r_rs1_expected = read_operand(r_instr_id[19:15]);
                    r_rs2_expected = read_operand(r_instr_id[24:20]);
                    r_valid_expected = r_valid_id;
                    r_controls_expected = r_valid_id ? r_controls_id_expected : 16'd0;
                end
            end
            if (r_reset)
                for (index = 0; index < 32; index = index + 1)
                    r_model[index] = 32'd0;
            else if (r_en && r_valid_wb && r_reg_write_wb && r_rd_wb != 5'd0)
                r_model[r_rd_wb] = r_wdata_wb;
            #1;
            check_outputs();
        end
    endtask

    task automatic drive_instruction(input [31:0] instruction, input [31:0] immediate,
                                      input [15:0] controls, input valid);
        begin
            @(negedge r_clock);
            r_instr_id = instruction;
            r_imm_id_expected = immediate;
            r_controls_id_expected = controls;
            r_valid_id = valid;
            r_pc_id = r_pc_id + 32'd4;
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #10 r_clock = ~r_clock;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL tb_decode_stage: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        cycles = 0;
        r_seed = 32'h14de_c0de;
        r_reset = 1'b1;
        r_en = 1'b0;
        r_flush = 1'b1;
        r_stall = 1'b1;
        r_valid_id = 1'b0;
        r_pc_id = 32'h8000_0100;
        r_instr_id = 32'd0;
        r_imm_id_expected = 32'd0;
        r_controls_id_expected = 16'd0;
        r_valid_wb = 1'b0;
        r_reg_write_wb = 1'b0;
        r_rd_wb = 5'd0;
        r_wdata_wb = 32'd0;
        r_dbg_reg_addr = 5'd0;
        tick();
        @(negedge r_clock);
        r_reset = 1'b0;
        r_en = 1'b1;
        r_flush = 1'b0;
        r_stall = 1'b0;
        r_valid_wb = 1'b1;
        r_reg_write_wb = 1'b1;
        repeat (31) begin
            r_rd_wb = r_rd_wb + 5'd1;
            r_wdata_wb = 32'h5100_0000 + {27'd0, r_rd_wb};
            tick();
            @(negedge r_clock);
        end
        r_valid_wb = 1'b0;
        r_reg_write_wb = 1'b0;

        drive_instruction(32'h002081b3, 32'h00000000, 16'h0083, 1'b1);
        tick();
        drive_instruction(32'h402081b3, 32'h00000000, 16'h1083, 1'b1);
        tick();
        drive_instruction(32'h002091b3, 32'h00000000, 16'h2083, 1'b1);
        tick();
        drive_instruction(32'h0020a1b3, 32'h00000000, 16'h8083, 1'b1);
        tick();
        drive_instruction(32'h0020b1b3, 32'h00000000, 16'h9083, 1'b1);
        tick();
        drive_instruction(32'h0020c1b3, 32'h00000000, 16'h7083, 1'b1);
        tick();
        drive_instruction(32'h0020d1b3, 32'h00000000, 16'h3083, 1'b1);
        tick();
        drive_instruction(32'h4020d1b3, 32'h00000000, 16'h4083, 1'b1);
        tick();
        drive_instruction(32'h0020e1b3, 32'h00000000, 16'h6083, 1'b1);
        tick();
        drive_instruction(32'h0020f1b3, 32'h00000000, 16'h5083, 1'b1);
        tick();
        drive_instruction(32'hfff08193, 32'hffffffff, 16'h0882, 1'b1);
        tick();
        drive_instruction(32'hfff0a193, 32'hffffffff, 16'h8882, 1'b1);
        tick();
        drive_instruction(32'hfff0b193, 32'hffffffff, 16'h9882, 1'b1);
        tick();
        drive_instruction(32'hfff0c193, 32'hffffffff, 16'h7882, 1'b1);
        tick();
        drive_instruction(32'hfff0e193, 32'hffffffff, 16'h6882, 1'b1);
        tick();
        drive_instruction(32'hfff0f193, 32'hffffffff, 16'h5882, 1'b1);
        tick();
        drive_instruction(32'h01f09193, 32'h0000001f, 16'h2882, 1'b1);
        tick();
        drive_instruction(32'h01f0d193, 32'h0000001f, 16'h3882, 1'b1);
        tick();
        drive_instruction(32'h41f0d193, 32'h0000041f, 16'h4882, 1'b1);
        tick();
        drive_instruction(32'hffc08183, 32'hfffffffc, 16'h0d82, 1'b1);
        tick();
        drive_instruction(32'hffc09183, 32'hfffffffc, 16'h0d82, 1'b1);
        tick();
        drive_instruction(32'hffc0a183, 32'hfffffffc, 16'h0d82, 1'b1);
        tick();
        drive_instruction(32'hffc0c183, 32'hfffffffc, 16'h0d82, 1'b1);
        tick();
        drive_instruction(32'hffc0d183, 32'hfffffffc, 16'h0d82, 1'b1);
        tick();
        drive_instruction(32'hfe208823, 32'hfffffff0, 16'h0a03, 1'b1);
        tick();
        drive_instruction(32'hfe209823, 32'hfffffff0, 16'h0a03, 1'b1);
        tick();
        drive_instruction(32'hfe20a823, 32'hfffffff0, 16'h0a03, 1'b1);
        tick();
        drive_instruction(32'hfe208ee3, 32'hfffffffc, 16'h0043, 1'b1);
        tick();
        drive_instruction(32'hfe209ee3, 32'hfffffffc, 16'h0043, 1'b1);
        tick();
        drive_instruction(32'h008000ef, 32'h00000008, 16'h00a0, 1'b1);
        tick();
        drive_instruction(32'h004081e7, 32'h00000004, 16'h08b2, 1'b1);
        tick();
        drive_instruction(32'h123450b7, 32'h12345000, 16'h0888, 1'b1);
        tick();
        drive_instruction(32'h00000073, 32'h00000000, 16'h0004, 1'b1);
        tick();
        drive_instruction(32'h00000000, 32'h00000000, 16'h0000, 1'b1);
        tick();
        drive_instruction(32'h022081b3, 32'h00000000, 16'h0000, 1'b1);
        tick();
        drive_instruction(32'h0040b183, 32'h00000004, 16'h0000, 1'b1);
        tick();
        drive_instruction(32'h00100073, 32'h00000000, 16'h0000, 1'b1);
        tick();
        drive_instruction(32'h0020c063, 32'h00000000, 16'h0000, 1'b1);
        tick();
        drive_instruction(32'h002081b3, 32'h00000000, 16'h0083, 1'b0);
        tick();
        drive_instruction(32'h0020a023, 32'h00000000, 16'h0a03, 1'b0);
        tick();
        drive_instruction(32'h00000073, 32'h00000000, 16'h0004, 1'b0);
        tick();

        drive_instruction(32'h002081b3, 32'd0, 16'h0083, 1'b1);
        r_valid_wb = 1'b1;
        r_reg_write_wb = 1'b1;
        r_rd_wb = 5'd1;
        r_wdata_wb = 32'hdead_0011;
        r_dbg_reg_addr = 5'd1;
        #1;
        check_word(w_dbg_reg_data, 32'h5100_0001, "debug before WB edge");
        tick();
        check_word(w_rs1_data_ex, 32'hdead_0011, "WB rs1 bypass");
        drive_instruction(32'h002081b3, 32'd0, 16'h0083, 1'b1);
        r_rd_wb = 5'd2;
        r_wdata_wb = 32'hbeef_0022;
        tick();
        check_word(w_rs2_data_ex, 32'hbeef_0022, "WB rs2 bypass");
        drive_instruction(32'h00528333, 32'd0, 16'h0083, 1'b1);
        r_rd_wb = 5'd5;
        r_wdata_wb = 32'hfeed_0055;
        tick();
        check_word(w_rs1_data_ex, 32'hfeed_0055, "both sources WB bypass");
        check_word(w_rs2_data_ex, 32'hfeed_0055, "both sources WB bypass");
        drive_instruction(32'h00528333, 32'd0, 16'h0083, 1'b1);
        r_valid_wb = 1'b0;
        r_wdata_wb = 32'hbad0_0000;
        tick();
        check_word(w_rs1_data_ex, 32'hfeed_0055, "invalid WB does not bypass");
        drive_instruction(32'h00528333, 32'd0, 16'h0083, 1'b1);
        r_valid_wb = 1'b1;
        r_reg_write_wb = 1'b0;
        tick();
        check_word(w_rs2_data_ex, 32'hfeed_0055, "disabled WB does not bypass");
        drive_instruction(32'h00000333, 32'd0, 16'h0083, 1'b1);
        r_reg_write_wb = 1'b1;
        r_rd_wb = 5'd0;
        r_wdata_wb = 32'hffff_ffff;
        tick();
        check_word(w_rs1_data_ex, 32'd0, "x0 rs1");
        check_word(w_rs2_data_ex, 32'd0, "x0 rs2");

        drive_instruction(32'h00000073, 32'd0, 16'h0004, 1'b1);
        r_flush = 1'b1;
        r_stall = 1'b1;
        r_rd_wb = 5'd5;
        r_wdata_wb = 32'h1234_5678;
        tick();
        check_word({31'd0, w_valid_ex}, 32'd0, "flush beats stall");
        check_word({16'd0, w_controls_ex}, 32'd0, "flush suppresses HALT");
        drive_instruction(32'h00528333, 32'd0, 16'h0083, 1'b1);
        r_flush = 1'b0;
        r_wdata_wb = 32'h8765_4321;
        tick();
        drive_instruction(32'h00528333, 32'd0, 16'h0083, 1'b1);
        r_stall = 1'b0;
        r_reg_write_wb = 1'b0;
        tick();
        check_word(w_rs1_data_ex, 32'h8765_4321, "older WB progresses during ID stall");

        drive_instruction(32'h00528333, 32'd0, 16'h0083, 1'b1);
        r_en = 1'b0;
        r_flush = 1'b1;
        r_stall = 1'b1;
        r_reg_write_wb = 1'b1;
        r_wdata_wb = 32'hbad0_1111;
        repeat (100) begin
            tick();
            @(negedge r_clock);
        end
        r_dbg_reg_addr = 5'd5;
        #1;
        check_word(w_dbg_reg_data, 32'h8765_4321, "pause blocks WB");
        r_en = 1'b0;
        r_flush = 1'b0;
        r_stall = 1'b0;
        r_valid_wb = 1'b0;

        repeat (128) begin
            r_seed = r_seed * 32'd1664525 + 32'd1013904223;
            drive_instruction(32'h00528333, 32'd0, 16'h0083, r_seed[31]);
            r_en = r_seed[30];
            r_flush = r_seed[29];
            r_stall = r_seed[28];
            r_valid_wb = r_seed[27];
            r_reg_write_wb = r_seed[26];
            r_rd_wb = r_seed[4:0];
            r_wdata_wb = r_seed;
            tick();
        end
        @(negedge r_clock);
        r_reset = 1'b1;
        r_en = 1'b0;
        r_valid_wb = 1'b1;
        r_reg_write_wb = 1'b1;
        r_rd_wb = 5'd1;
        r_wdata_wb = 32'hffff_ffff;
        tick();
        @(negedge r_clock);
        r_valid_wb = 1'b0;
        r_reg_write_wb = 1'b0;
        for (index = 0; index < 32; index = index + 1) begin
            r_dbg_reg_addr = index[4:0];
            #1;
            check_word(w_dbg_reg_data, 32'd0, "reset clears stored registers");
        end
        if (errors != 0)
            $fatal(1, "FAIL tb_decode_stage: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_decode_stage: %0d checks, seed=14dec0de", checks);
        $finish;
    end
endmodule

`default_nettype wire

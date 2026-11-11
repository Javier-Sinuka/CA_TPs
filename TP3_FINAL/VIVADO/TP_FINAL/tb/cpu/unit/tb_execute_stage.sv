`timescale 1ns/1ps
`default_nettype none

module tb_execute_stage;
    reg r_clock;
    reg r_reset;
    reg r_en;
    reg r_flush;
    reg r_stall;
    reg r_valid_ex;
    reg [31:0] r_pc_ex;
    reg [31:0] r_rs1_data_ex;
    reg [31:0] r_rs2_data_ex;
    reg [31:0] r_imm_ex;
    reg [4:0] r_rd_ex;
    reg [2:0] r_funct3_ex;
    reg [3:0] r_alu_op_ex;
    reg r_alu_src_b_ex;
    reg r_jump_ex;
    reg r_lui_ex;
    reg r_mem_read_ex;
    reg r_mem_write_ex;
    reg r_mem_to_reg_ex;
    reg r_reg_write_ex;
    reg r_halt_ex;
    wire [31:0] w_result_ex;
    wire w_valid_mem;
    wire [31:0] w_pc_mem;
    wire [31:0] w_result_mem;
    wire [31:0] w_store_data_mem;
    wire [4:0] w_rd_mem;
    wire [2:0] w_funct3_mem;
    wire w_mem_read_mem;
    wire w_mem_write_mem;
    wire w_mem_to_reg_mem;
    wire w_reg_write_mem;
    wire w_halt_mem;
    wire [31:0] w_info_mem;
    reg [31:0] r_expected_pc, r_expected_result, r_expected_store;
    reg [4:0] r_expected_rd;
    reg [2:0] r_expected_funct3;
    reg [4:0] r_expected_controls;
    reg r_expected_valid;
    reg [31:0] r_reference_result_ex;
    reg [31:0] r_seed;
    reg [63:0] r_reference_sum;
    integer checks, errors, cycles, index;

    execute_stage dut (
        .i_clock(r_clock),
        .i_reset(r_reset),
        .i_en(r_en),
        .i_flush(r_flush),
        .i_stall(r_stall),
        .i_valid_ex(r_valid_ex),
        .i_pc_ex(r_pc_ex),
        .i_rs1_data_ex(r_rs1_data_ex),
        .i_rs2_data_ex(r_rs2_data_ex),
        .i_imm_ex(r_imm_ex),
        .i_rd_ex(r_rd_ex),
        .i_funct3_ex(r_funct3_ex),
        .i_alu_op_ex(r_alu_op_ex),
        .i_alu_src_b_ex(r_alu_src_b_ex),
        .i_jump_ex(r_jump_ex),
        .i_lui_ex(r_lui_ex),
        .i_mem_read_ex(r_mem_read_ex),
        .i_mem_write_ex(r_mem_write_ex),
        .i_mem_to_reg_ex(r_mem_to_reg_ex),
        .i_reg_write_ex(r_reg_write_ex),
        .i_halt_ex(r_halt_ex),
        .o_result_ex(w_result_ex),
        .o_valid_mem(w_valid_mem),
        .o_pc_mem(w_pc_mem),
        .o_result_mem(w_result_mem),
        .o_store_data_mem(w_store_data_mem),
        .o_rd_mem(w_rd_mem),
        .o_funct3_mem(w_funct3_mem),
        .o_mem_read_mem(w_mem_read_mem),
        .o_mem_write_mem(w_mem_write_mem),
        .o_mem_to_reg_mem(w_mem_to_reg_mem),
        .o_reg_write_mem(w_reg_write_mem),
        .o_halt_mem(w_halt_mem),
        .o_info_mem(w_info_mem)
    );

    function automatic [31:0] expected_info;
        input [4:0] rd;
        input [2:0] funct3;
        input [4:0] controls;
        begin
            expected_info = {27'd0, rd} | ({29'd0, funct3} << 15);
            expected_info[23] = controls[4];
            expected_info[24] = controls[3];
            expected_info[25] = controls[2];
            expected_info[26] = controls[1];
            expected_info[31] = controls[0];
        end
    endfunction

    task automatic check_word(input [31:0] got, input [31:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL execute_stage: cycle=%0d %s expected=%08h got=%08h", cycles, label, expected, got);
            end
        end
    endtask

    task automatic check_outputs;
        begin
            check_word({31'd0, w_valid_mem}, {31'd0, r_expected_valid}, "valid MEM");
            check_word(w_pc_mem, r_expected_pc, "instruction PC");
            check_word(w_result_mem, r_expected_result, "architectural result");
            check_word(w_store_data_mem, r_expected_store, "store source before immediate mux");
            check_word({27'd0, w_rd_mem}, {27'd0, r_expected_rd}, "rd");
            check_word({29'd0, w_funct3_mem}, {29'd0, r_expected_funct3}, "funct3");
            check_word({27'd0, w_mem_read_mem, w_mem_write_mem, w_mem_to_reg_mem, w_reg_write_mem, w_halt_mem},
                       {27'd0, r_expected_controls}, "MEM controls");
            check_word(w_info_mem, expected_info(r_expected_rd, r_expected_funct3, r_expected_controls), "info MEM");
            check_word(w_info_mem & 32'h787c_7fe0, 32'd0, "fields absent from MEM");
        end
    endtask

    task automatic tick;
        begin
            #1;
            check_word(w_result_ex, r_reference_result_ex, "combinational result");
            @(posedge r_clock);
            cycles = cycles + 1;
            if (r_reset) begin
                r_expected_pc = 32'd0;
                r_expected_result = 32'd0;
                r_expected_store = 32'd0;
                r_expected_rd = 5'd0;
                r_expected_funct3 = 3'd0;
                r_expected_controls = 5'd0;
                r_expected_valid = 1'b0;
            end else if (r_en) begin
                if (r_flush) begin
                    r_expected_valid = 1'b0;
                    r_expected_controls = 5'd0;
                end else if (!r_stall) begin
                    r_expected_valid = r_valid_ex;
                    r_expected_pc = r_pc_ex;
                    r_expected_result = r_reference_result_ex;
                    r_expected_store = r_rs2_data_ex;
                    r_expected_rd = r_rd_ex;
                    r_expected_funct3 = r_funct3_ex;
                    r_expected_controls = r_valid_ex ? {r_mem_read_ex, r_mem_write_ex, r_mem_to_reg_ex, r_reg_write_ex, r_halt_ex} : 5'd0;
                end
            end
            #1;
            check_outputs();
        end
    endtask

    task automatic drive;
        input [31:0] pc, a, b, immediate;
        input [3:0] operation;
        input [7:0] controls;
        input [31:0] result;
        input valid;
        begin
            @(negedge r_clock);
            r_pc_ex = pc;
            r_rs1_data_ex = a;
            r_rs2_data_ex = b;
            r_imm_ex = immediate;
            r_alu_op_ex = operation;
            {r_alu_src_b_ex, r_jump_ex, r_lui_ex, r_mem_read_ex, r_mem_write_ex, r_mem_to_reg_ex, r_reg_write_ex, r_halt_ex} = controls;
            r_valid_ex = valid;
            r_rd_ex = pc[6:2];
            r_funct3_ex = pc[9:7];
            r_reference_result_ex = result;
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #10 r_clock = ~r_clock;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL tb_execute_stage: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        cycles = 0;
        r_seed = 32'h15e0_5eed;
        r_reset = 1'b1;
        r_en = 1'b0;
        r_flush = 1'b1;
        r_stall = 1'b1;
        r_valid_ex = 1'b0;
        r_pc_ex = 32'd0;
        r_rs1_data_ex = 32'd0;
        r_rs2_data_ex = 32'd0;
        r_imm_ex = 32'd0;
        r_rd_ex = 5'd0;
        r_funct3_ex = 3'd0;
        r_alu_op_ex = 4'd0;
        {r_alu_src_b_ex, r_jump_ex, r_lui_ex, r_mem_read_ex, r_mem_write_ex, r_mem_to_reg_ex, r_reg_write_ex, r_halt_ex} = 8'd0;
        r_reference_result_ex = 32'd0;
        tick();
        @(negedge r_clock);
        r_reset = 1'b0;
        r_en = 1'b1;
        r_flush = 1'b0;
        r_stall = 1'b0;

        drive(32'h00000100, 32'h00000007, 32'hffffffff, 32'h00000000, 4'd0, 8'h02, 32'h00000006, 1'b1);
        tick();
        drive(32'h00000104, 32'h00000000, 32'h00000001, 32'h00000000, 4'd1, 8'h02, 32'hffffffff, 1'b1);
        tick();
        drive(32'h00000108, 32'h00000001, 32'h0000001f, 32'h00000002, 4'd2, 8'h02, 32'h80000000, 1'b1);
        tick();
        drive(32'h0000010c, 32'h80000000, 32'h00000001, 32'h0000001f, 4'd3, 8'h02, 32'h40000000, 1'b1);
        tick();
        drive(32'h00000110, 32'h80000000, 32'h00000001, 32'h0000001f, 4'd4, 8'h02, 32'hc0000000, 1'b1);
        tick();
        drive(32'h00000114, 32'hf0f0aa55, 32'h0ff00f0f, 32'h00000000, 4'd5, 8'h02, 32'h00f00a05, 1'b1);
        tick();
        drive(32'h00000118, 32'hf0f0aa55, 32'h0ff00f0f, 32'h00000000, 4'd6, 8'h02, 32'hfff0af5f, 1'b1);
        tick();
        drive(32'h0000011c, 32'hf0f0aa55, 32'h0ff00f0f, 32'h00000000, 4'd7, 8'h02, 32'hff00a55a, 1'b1);
        tick();
        drive(32'h00000120, 32'hffffffff, 32'h00000001, 32'h00000000, 4'd8, 8'h02, 32'h00000001, 1'b1);
        tick();
        drive(32'h00000124, 32'hffffffff, 32'h00000001, 32'h00000000, 4'd9, 8'h02, 32'h00000000, 1'b1);
        tick();
        drive(32'h00000128, 32'hffffffff, 32'hdeadbeef, 32'h00000001, 4'd0, 8'h82, 32'h00000000, 1'b1);
        tick();
        drive(32'h0000012c, 32'h80000000, 32'hdeadbeef, 32'h0000041f, 4'd4, 8'h82, 32'hffffffff, 1'b1);
        tick();
        drive(32'h00000130, 32'h00000000, 32'hffffffff, 32'h00000000, 4'd15, 8'h02, 32'h00000000, 1'b1);
        tick();
        drive(32'h00000134, 32'haaaa5555, 32'hdeadbeef, 32'h12345000, 4'd0, 8'ha2, 32'h12345000, 1'b1);
        tick();
        drive(32'h00000138, 32'hffffffff, 32'hdeadbeef, 32'h80000000, 4'd0, 8'ha2, 32'h80000000, 1'b1);
        tick();
        drive(32'h00000040, 32'h00001001, 32'h76543210, 32'h00000080, 4'd0, 8'h42, 32'h00000044, 1'b1);
        tick();
        drive(32'h00000040, 32'h00001001, 32'h76543210, 32'hfffffffc, 4'd0, 8'hc2, 32'h00000044, 1'b1);
        tick();
        check_word(dut.w_alu_result_ex, 32'h0000_0ffd, "JALR base plus immediate remains separate from link");
        drive(32'hfffffffc, 32'h00000000, 32'h00000000, 32'h00000100, 4'd0, 8'h42, 32'h00000000, 1'b1);
        tick();
        drive(32'h00000042, 32'hffffffff, 32'h0000001f, 32'h00000100, 4'd0, 8'hc2, 32'h00000046, 1'b1);
        tick();
        drive(32'h00000140, 32'h00000020, 32'hdeadbeef, 32'hfffffffc, 4'd0, 8'h96, 32'h0000001c, 1'b1);
        tick();
        drive(32'h00000144, 32'h00000100, 32'hcafebabe, 32'hfffffff0, 4'd0, 8'h88, 32'h000000f0, 1'b1);
        tick();
        drive(32'h00000148, 32'h00000000, 32'h00000000, 32'h00000000, 4'd0, 8'h01, 32'h00000000, 1'b1);
        tick();
        drive(32'h0000014c, 32'hffffffff, 32'h12345678, 32'h00000100, 4'd0, 8'hff, 32'h00000150, 1'b0);
        tick();

        drive(32'h0000_0200, 32'd10, 32'h1122_3344, 32'd2, 4'd0, 8'h88, 32'd12, 1'b1);
        r_en = 1'b0;
        r_flush = 1'b1;
        r_stall = 1'b1;
        repeat (100) begin
            tick();
            @(negedge r_clock);
        end
        r_en = 1'b1;
        tick();
        check_word({31'd0, w_valid_mem}, 32'd0, "flush wins over stall");
        @(negedge r_clock);
        r_flush = 1'b0;
        tick();
        @(negedge r_clock);
        r_stall = 1'b0;
        tick();
        check_word(w_store_data_mem, 32'h1122_3344, "resume store source");

        for (index = 0; index < 256; index = index + 1) begin
            @(negedge r_clock);
            r_seed = r_seed * 32'd1664525 + 32'd1013904223;
            r_rs1_data_ex = r_seed;
            r_seed = r_seed * 32'd1664525 + 32'd1013904223;
            r_rs2_data_ex = r_seed;
            r_seed = r_seed * 32'd1664525 + 32'd1013904223;
            r_imm_ex = r_seed;
            r_pc_ex = r_seed ^ 32'h8123_4567;
            r_rd_ex = r_seed[4:0];
            r_funct3_ex = r_seed[7:5];
            r_alu_src_b_ex = r_seed[8];
            r_jump_ex = 1'b0;
            r_lui_ex = 1'b0;
            r_alu_op_ex = 4'd0;
            {r_mem_read_ex, r_mem_write_ex, r_mem_to_reg_ex, r_reg_write_ex, r_halt_ex} = r_seed[13:9];
            r_valid_ex = r_seed[14];
            r_en = r_seed[15];
            r_flush = r_seed[16];
            r_stall = r_seed[17];
            r_reference_sum = {32'd0, r_rs1_data_ex};
            if (r_alu_src_b_ex)
                r_reference_sum = r_reference_sum + {32'd0, r_imm_ex};
            else
                r_reference_sum = r_reference_sum + {32'd0, r_rs2_data_ex};
            r_reference_result_ex = r_reference_sum[31:0];
            tick();
        end
        @(negedge r_clock);
        r_en = 1'b0;
        r_reset = 1'b1;
        r_flush = 1'b1;
        r_stall = 1'b1;
        tick();
        check_word({31'd0, w_valid_mem}, 32'd0, "paused reset valid");
        check_word(w_result_mem, 32'd0, "paused reset result");
        check_word(w_info_mem, 32'd0, "paused reset info");
        if (errors != 0)
            $fatal(1, "FAIL tb_execute_stage: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_execute_stage: %0d checks, seed=15e05eed", checks);
        $finish;
    end
endmodule

`default_nettype wire

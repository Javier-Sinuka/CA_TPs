`timescale 1ns/1ps
`default_nettype none

module tb_pipeline_regs;
    reg r_clock;
    reg [3:0] r_reset, r_en, r_flush, r_stall, r_valid;
    reg [31:0] r_seed;
    integer checks, errors, step, bit_index, combination, stage_index;
    reg [31:0] r_if_id_pc;
    reg [31:0] r_if_id_instr;
    wire w_if_id_valid;
    wire [31:0] w_if_id_pc;
    wire [31:0] w_if_id_instr;
    reg [64:0] r_if_id_expected;
    reg [31:0] r_id_ex_pc;
    reg [31:0] r_id_ex_rs1_data;
    reg [31:0] r_id_ex_rs2_data;
    reg [31:0] r_id_ex_imm;
    reg [4:0] r_id_ex_rd;
    reg [4:0] r_id_ex_rs1;
    reg [4:0] r_id_ex_rs2;
    reg [2:0] r_id_ex_funct3;
    reg [3:0] r_id_ex_alu_op;
    reg r_id_ex_alu_src_b;
    reg r_id_ex_mem_read;
    reg r_id_ex_mem_write;
    reg r_id_ex_mem_to_reg;
    reg r_id_ex_reg_write;
    reg r_id_ex_branch;
    reg r_id_ex_jump;
    reg r_id_ex_jalr;
    reg r_id_ex_lui;
    reg r_id_ex_halt;
    reg r_id_ex_uses_rs1;
    reg r_id_ex_uses_rs2;
    wire w_id_ex_valid;
    wire [31:0] w_id_ex_pc;
    wire [31:0] w_id_ex_rs1_data;
    wire [31:0] w_id_ex_rs2_data;
    wire [31:0] w_id_ex_imm;
    wire [4:0] w_id_ex_rd;
    wire [4:0] w_id_ex_rs1;
    wire [4:0] w_id_ex_rs2;
    wire [2:0] w_id_ex_funct3;
    wire [3:0] w_id_ex_alu_op;
    wire w_id_ex_alu_src_b;
    wire w_id_ex_mem_read;
    wire w_id_ex_mem_write;
    wire w_id_ex_mem_to_reg;
    wire w_id_ex_reg_write;
    wire w_id_ex_branch;
    wire w_id_ex_jump;
    wire w_id_ex_jalr;
    wire w_id_ex_lui;
    wire w_id_ex_halt;
    wire w_id_ex_uses_rs1;
    wire w_id_ex_uses_rs2;
    reg [162:0] r_id_ex_expected;
    wire [31:0] w_id_ex_info;
    reg [31:0] r_ex_mem_pc;
    reg [31:0] r_ex_mem_result;
    reg [31:0] r_ex_mem_store_data;
    reg [4:0] r_ex_mem_rd;
    reg [2:0] r_ex_mem_funct3;
    reg r_ex_mem_mem_read;
    reg r_ex_mem_mem_write;
    reg r_ex_mem_mem_to_reg;
    reg r_ex_mem_reg_write;
    reg r_ex_mem_halt;
    wire w_ex_mem_valid;
    wire [31:0] w_ex_mem_pc;
    wire [31:0] w_ex_mem_result;
    wire [31:0] w_ex_mem_store_data;
    wire [4:0] w_ex_mem_rd;
    wire [2:0] w_ex_mem_funct3;
    wire w_ex_mem_mem_read;
    wire w_ex_mem_mem_write;
    wire w_ex_mem_mem_to_reg;
    wire w_ex_mem_reg_write;
    wire w_ex_mem_halt;
    reg [109:0] r_ex_mem_expected;
    wire [31:0] w_ex_mem_info;
    reg [31:0] r_mem_wb_pc;
    reg [31:0] r_mem_wb_result;
    reg [31:0] r_mem_wb_load_data;
    reg [4:0] r_mem_wb_rd;
    reg r_mem_wb_mem_to_reg;
    reg r_mem_wb_reg_write;
    reg r_mem_wb_halt;
    wire w_mem_wb_valid;
    wire [31:0] w_mem_wb_pc;
    wire [31:0] w_mem_wb_result;
    wire [31:0] w_mem_wb_load_data;
    wire [4:0] w_mem_wb_rd;
    wire w_mem_wb_mem_to_reg;
    wire w_mem_wb_reg_write;
    wire w_mem_wb_halt;
    reg [104:0] r_mem_wb_expected;
    wire [31:0] w_mem_wb_info;

    if_id u_if_id (
        .i_clock(r_clock),
        .i_reset(r_reset[0]),
        .i_en(r_en[0]),
        .i_flush(r_flush[0]),
        .i_stall(r_stall[0]),
        .i_valid(r_valid[0]),
        .i_pc(r_if_id_pc),
        .i_instr(r_if_id_instr),
        .o_valid(w_if_id_valid),
        .o_pc(w_if_id_pc),
        .o_instr(w_if_id_instr)
    );

    id_ex u_id_ex (
        .i_clock(r_clock),
        .i_reset(r_reset[1]),
        .i_en(r_en[1]),
        .i_flush(r_flush[1]),
        .i_stall(r_stall[1]),
        .i_valid(r_valid[1]),
        .i_pc(r_id_ex_pc),
        .i_rs1_data(r_id_ex_rs1_data),
        .i_rs2_data(r_id_ex_rs2_data),
        .i_imm(r_id_ex_imm),
        .i_rd(r_id_ex_rd),
        .i_rs1(r_id_ex_rs1),
        .i_rs2(r_id_ex_rs2),
        .i_funct3(r_id_ex_funct3),
        .i_alu_op(r_id_ex_alu_op),
        .i_alu_src_b(r_id_ex_alu_src_b),
        .i_mem_read(r_id_ex_mem_read),
        .i_mem_write(r_id_ex_mem_write),
        .i_mem_to_reg(r_id_ex_mem_to_reg),
        .i_reg_write(r_id_ex_reg_write),
        .i_branch(r_id_ex_branch),
        .i_jump(r_id_ex_jump),
        .i_jalr(r_id_ex_jalr),
        .i_lui(r_id_ex_lui),
        .i_halt(r_id_ex_halt),
        .i_uses_rs1(r_id_ex_uses_rs1),
        .i_uses_rs2(r_id_ex_uses_rs2),
        .o_valid(w_id_ex_valid),
        .o_pc(w_id_ex_pc),
        .o_rs1_data(w_id_ex_rs1_data),
        .o_rs2_data(w_id_ex_rs2_data),
        .o_imm(w_id_ex_imm),
        .o_rd(w_id_ex_rd),
        .o_rs1(w_id_ex_rs1),
        .o_rs2(w_id_ex_rs2),
        .o_funct3(w_id_ex_funct3),
        .o_alu_op(w_id_ex_alu_op),
        .o_alu_src_b(w_id_ex_alu_src_b),
        .o_mem_read(w_id_ex_mem_read),
        .o_mem_write(w_id_ex_mem_write),
        .o_mem_to_reg(w_id_ex_mem_to_reg),
        .o_reg_write(w_id_ex_reg_write),
        .o_branch(w_id_ex_branch),
        .o_jump(w_id_ex_jump),
        .o_jalr(w_id_ex_jalr),
        .o_lui(w_id_ex_lui),
        .o_halt(w_id_ex_halt),
        .o_uses_rs1(w_id_ex_uses_rs1),
        .o_uses_rs2(w_id_ex_uses_rs2),
        .o_info(w_id_ex_info)
    );

    ex_mem u_ex_mem (
        .i_clock(r_clock),
        .i_reset(r_reset[2]),
        .i_en(r_en[2]),
        .i_flush(r_flush[2]),
        .i_stall(r_stall[2]),
        .i_valid(r_valid[2]),
        .i_pc(r_ex_mem_pc),
        .i_result(r_ex_mem_result),
        .i_store_data(r_ex_mem_store_data),
        .i_rd(r_ex_mem_rd),
        .i_funct3(r_ex_mem_funct3),
        .i_mem_read(r_ex_mem_mem_read),
        .i_mem_write(r_ex_mem_mem_write),
        .i_mem_to_reg(r_ex_mem_mem_to_reg),
        .i_reg_write(r_ex_mem_reg_write),
        .i_halt(r_ex_mem_halt),
        .o_valid(w_ex_mem_valid),
        .o_pc(w_ex_mem_pc),
        .o_result(w_ex_mem_result),
        .o_store_data(w_ex_mem_store_data),
        .o_rd(w_ex_mem_rd),
        .o_funct3(w_ex_mem_funct3),
        .o_mem_read(w_ex_mem_mem_read),
        .o_mem_write(w_ex_mem_mem_write),
        .o_mem_to_reg(w_ex_mem_mem_to_reg),
        .o_reg_write(w_ex_mem_reg_write),
        .o_halt(w_ex_mem_halt),
        .o_info(w_ex_mem_info)
    );

    mem_wb u_mem_wb (
        .i_clock(r_clock),
        .i_reset(r_reset[3]),
        .i_en(r_en[3]),
        .i_flush(r_flush[3]),
        .i_stall(r_stall[3]),
        .i_valid(r_valid[3]),
        .i_pc(r_mem_wb_pc),
        .i_result(r_mem_wb_result),
        .i_load_data(r_mem_wb_load_data),
        .i_rd(r_mem_wb_rd),
        .i_mem_to_reg(r_mem_wb_mem_to_reg),
        .i_reg_write(r_mem_wb_reg_write),
        .i_halt(r_mem_wb_halt),
        .o_valid(w_mem_wb_valid),
        .o_pc(w_mem_wb_pc),
        .o_result(w_mem_wb_result),
        .o_load_data(w_mem_wb_load_data),
        .o_rd(w_mem_wb_rd),
        .o_mem_to_reg(w_mem_wb_mem_to_reg),
        .o_reg_write(w_mem_wb_reg_write),
        .o_halt(w_mem_wb_halt),
        .o_info(w_mem_wb_info)
    );

    function automatic [31:0] next_random(input [31:0] state);
        reg [31:0] value;
        begin
            value = state ^ (state << 13);
            value = value ^ (value >> 17);
            next_random = value ^ (value << 5);
        end
    endfunction

    task automatic random_payload;
        begin
            r_seed = next_random(r_seed);
            r_if_id_pc = r_seed;
            r_seed = next_random(r_seed);
            r_if_id_instr = r_seed;
            r_seed = next_random(r_seed);
            r_id_ex_pc = r_seed;
            r_seed = next_random(r_seed);
            r_id_ex_rs1_data = r_seed;
            r_seed = next_random(r_seed);
            r_id_ex_rs2_data = r_seed;
            r_seed = next_random(r_seed);
            r_id_ex_imm = r_seed;
            r_seed = next_random(r_seed);
            r_id_ex_rd = r_seed[4:0];
            r_seed = next_random(r_seed);
            r_id_ex_rs1 = r_seed[4:0];
            r_seed = next_random(r_seed);
            r_id_ex_rs2 = r_seed[4:0];
            r_seed = next_random(r_seed);
            r_id_ex_funct3 = r_seed[2:0];
            r_seed = next_random(r_seed);
            r_id_ex_alu_op = r_seed[3:0];
            r_seed = next_random(r_seed);
            r_id_ex_alu_src_b = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_mem_read = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_mem_write = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_mem_to_reg = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_reg_write = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_branch = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_jump = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_jalr = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_lui = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_halt = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_uses_rs1 = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_id_ex_uses_rs2 = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_ex_mem_pc = r_seed;
            r_seed = next_random(r_seed);
            r_ex_mem_result = r_seed;
            r_seed = next_random(r_seed);
            r_ex_mem_store_data = r_seed;
            r_seed = next_random(r_seed);
            r_ex_mem_rd = r_seed[4:0];
            r_seed = next_random(r_seed);
            r_ex_mem_funct3 = r_seed[2:0];
            r_seed = next_random(r_seed);
            r_ex_mem_mem_read = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_ex_mem_mem_write = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_ex_mem_mem_to_reg = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_ex_mem_reg_write = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_ex_mem_halt = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_mem_wb_pc = r_seed;
            r_seed = next_random(r_seed);
            r_mem_wb_result = r_seed;
            r_seed = next_random(r_seed);
            r_mem_wb_load_data = r_seed;
            r_seed = next_random(r_seed);
            r_mem_wb_rd = r_seed[4:0];
            r_seed = next_random(r_seed);
            r_mem_wb_mem_to_reg = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_mem_wb_reg_write = r_seed[0:0];
            r_seed = next_random(r_seed);
            r_mem_wb_halt = r_seed[0:0];
        end
    endtask

    task automatic set_info_pattern(input [31:0] value);
        begin
            r_id_ex_rd = value[0 +: 5];
            r_id_ex_rs1 = value[5 +: 5];
            r_id_ex_rs2 = value[10 +: 5];
            r_id_ex_funct3 = value[15 +: 3];
            r_id_ex_alu_op = value[18 +: 4];
            r_id_ex_alu_src_b = value[22 +: 1];
            r_id_ex_mem_read = value[23 +: 1];
            r_id_ex_mem_write = value[24 +: 1];
            r_id_ex_mem_to_reg = value[25 +: 1];
            r_id_ex_reg_write = value[26 +: 1];
            r_id_ex_branch = value[27 +: 1];
            r_id_ex_jump = value[28 +: 1];
            r_id_ex_jalr = value[29 +: 1];
            r_id_ex_lui = value[30 +: 1];
            r_id_ex_halt = value[31 +: 1];
            r_ex_mem_rd = value[0 +: 5];
            r_ex_mem_funct3 = value[15 +: 3];
            r_ex_mem_mem_read = value[23 +: 1];
            r_ex_mem_mem_write = value[24 +: 1];
            r_ex_mem_mem_to_reg = value[25 +: 1];
            r_ex_mem_reg_write = value[26 +: 1];
            r_ex_mem_halt = value[31 +: 1];
            r_mem_wb_rd = value[0 +: 5];
            r_mem_wb_mem_to_reg = value[25 +: 1];
            r_mem_wb_reg_write = value[26 +: 1];
            r_mem_wb_halt = value[31 +: 1];
            r_id_ex_uses_rs1 = 1'b0;
            r_id_ex_uses_rs2 = 1'b0;
        end
    endtask

    task automatic check_word(input [31:0] got, input [31:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL pipeline_regs: step=%0d %s expected=%08h got=%08h", step, label, expected, got);
            end
        end
    endtask

    task automatic check_outputs;
        begin
            check_word({31'd0, w_if_id_valid}, {31'd0, r_if_id_expected[64 +: 1]}, "if_id.valid");
            check_word(w_if_id_pc, r_if_id_expected[32 +: 32], "if_id.pc");
            check_word(w_if_id_instr, r_if_id_expected[0 +: 32], "if_id.instr");
            check_word({31'd0, w_id_ex_valid}, {31'd0, r_id_ex_expected[162 +: 1]}, "id_ex.valid");
            check_word(w_id_ex_pc, r_id_ex_expected[130 +: 32], "id_ex.pc");
            check_word(w_id_ex_rs1_data, r_id_ex_expected[98 +: 32], "id_ex.rs1_data");
            check_word(w_id_ex_rs2_data, r_id_ex_expected[66 +: 32], "id_ex.rs2_data");
            check_word(w_id_ex_imm, r_id_ex_expected[34 +: 32], "id_ex.imm");
            check_word({27'd0, w_id_ex_rd}, {27'd0, r_id_ex_expected[29 +: 5]}, "id_ex.rd");
            check_word({27'd0, w_id_ex_rs1}, {27'd0, r_id_ex_expected[24 +: 5]}, "id_ex.rs1");
            check_word({27'd0, w_id_ex_rs2}, {27'd0, r_id_ex_expected[19 +: 5]}, "id_ex.rs2");
            check_word({29'd0, w_id_ex_funct3}, {29'd0, r_id_ex_expected[16 +: 3]}, "id_ex.funct3");
            check_word({28'd0, w_id_ex_alu_op}, {28'd0, r_id_ex_expected[12 +: 4]}, "id_ex.alu_op");
            check_word({31'd0, w_id_ex_alu_src_b}, {31'd0, r_id_ex_expected[11 +: 1]}, "id_ex.alu_src_b");
            check_word({31'd0, w_id_ex_mem_read}, {31'd0, r_id_ex_expected[10 +: 1]}, "id_ex.mem_read");
            check_word({31'd0, w_id_ex_mem_write}, {31'd0, r_id_ex_expected[9 +: 1]}, "id_ex.mem_write");
            check_word({31'd0, w_id_ex_mem_to_reg}, {31'd0, r_id_ex_expected[8 +: 1]}, "id_ex.mem_to_reg");
            check_word({31'd0, w_id_ex_reg_write}, {31'd0, r_id_ex_expected[7 +: 1]}, "id_ex.reg_write");
            check_word({31'd0, w_id_ex_branch}, {31'd0, r_id_ex_expected[6 +: 1]}, "id_ex.branch");
            check_word({31'd0, w_id_ex_jump}, {31'd0, r_id_ex_expected[5 +: 1]}, "id_ex.jump");
            check_word({31'd0, w_id_ex_jalr}, {31'd0, r_id_ex_expected[4 +: 1]}, "id_ex.jalr");
            check_word({31'd0, w_id_ex_lui}, {31'd0, r_id_ex_expected[3 +: 1]}, "id_ex.lui");
            check_word({31'd0, w_id_ex_halt}, {31'd0, r_id_ex_expected[2 +: 1]}, "id_ex.halt");
            check_word({31'd0, w_id_ex_uses_rs1}, {31'd0, r_id_ex_expected[1 +: 1]}, "id_ex.uses_rs1");
            check_word({31'd0, w_id_ex_uses_rs2}, {31'd0, r_id_ex_expected[0 +: 1]}, "id_ex.uses_rs2");
            check_word(w_id_ex_info, {w_id_ex_halt, w_id_ex_lui, w_id_ex_jalr, w_id_ex_jump, w_id_ex_branch, w_id_ex_reg_write, w_id_ex_mem_to_reg, w_id_ex_mem_write, w_id_ex_mem_read, w_id_ex_alu_src_b, w_id_ex_alu_op, w_id_ex_funct3, w_id_ex_rs2, w_id_ex_rs1, w_id_ex_rd}, "id_ex.info");
            check_word({31'd0, w_ex_mem_valid}, {31'd0, r_ex_mem_expected[109 +: 1]}, "ex_mem.valid");
            check_word(w_ex_mem_pc, r_ex_mem_expected[77 +: 32], "ex_mem.pc");
            check_word(w_ex_mem_result, r_ex_mem_expected[45 +: 32], "ex_mem.result");
            check_word(w_ex_mem_store_data, r_ex_mem_expected[13 +: 32], "ex_mem.store_data");
            check_word({27'd0, w_ex_mem_rd}, {27'd0, r_ex_mem_expected[8 +: 5]}, "ex_mem.rd");
            check_word({29'd0, w_ex_mem_funct3}, {29'd0, r_ex_mem_expected[5 +: 3]}, "ex_mem.funct3");
            check_word({31'd0, w_ex_mem_mem_read}, {31'd0, r_ex_mem_expected[4 +: 1]}, "ex_mem.mem_read");
            check_word({31'd0, w_ex_mem_mem_write}, {31'd0, r_ex_mem_expected[3 +: 1]}, "ex_mem.mem_write");
            check_word({31'd0, w_ex_mem_mem_to_reg}, {31'd0, r_ex_mem_expected[2 +: 1]}, "ex_mem.mem_to_reg");
            check_word({31'd0, w_ex_mem_reg_write}, {31'd0, r_ex_mem_expected[1 +: 1]}, "ex_mem.reg_write");
            check_word({31'd0, w_ex_mem_halt}, {31'd0, r_ex_mem_expected[0 +: 1]}, "ex_mem.halt");
            check_word(w_ex_mem_info, {w_ex_mem_halt, 1'd0, 1'd0, 1'd0, 1'd0, w_ex_mem_reg_write, w_ex_mem_mem_to_reg, w_ex_mem_mem_write, w_ex_mem_mem_read, 1'd0, 4'd0, w_ex_mem_funct3, 5'd0, 5'd0, w_ex_mem_rd}, "ex_mem.info");
            check_word(w_ex_mem_info & 32'h787c7fe0, 32'd0, "ex_mem.absent fields");
            check_word({31'd0, w_mem_wb_valid}, {31'd0, r_mem_wb_expected[104 +: 1]}, "mem_wb.valid");
            check_word(w_mem_wb_pc, r_mem_wb_expected[72 +: 32], "mem_wb.pc");
            check_word(w_mem_wb_result, r_mem_wb_expected[40 +: 32], "mem_wb.result");
            check_word(w_mem_wb_load_data, r_mem_wb_expected[8 +: 32], "mem_wb.load_data");
            check_word({27'd0, w_mem_wb_rd}, {27'd0, r_mem_wb_expected[3 +: 5]}, "mem_wb.rd");
            check_word({31'd0, w_mem_wb_mem_to_reg}, {31'd0, r_mem_wb_expected[2 +: 1]}, "mem_wb.mem_to_reg");
            check_word({31'd0, w_mem_wb_reg_write}, {31'd0, r_mem_wb_expected[1 +: 1]}, "mem_wb.reg_write");
            check_word({31'd0, w_mem_wb_halt}, {31'd0, r_mem_wb_expected[0 +: 1]}, "mem_wb.halt");
            check_word(w_mem_wb_info, {w_mem_wb_halt, 1'd0, 1'd0, 1'd0, 1'd0, w_mem_wb_reg_write, w_mem_wb_mem_to_reg, 1'd0, 1'd0, 1'd0, 4'd0, 3'd0, 5'd0, 5'd0, w_mem_wb_rd}, "mem_wb.info");
            check_word(w_mem_wb_info & 32'h79ffffe0, 32'd0, "mem_wb.absent fields");
        end
    endtask

    task automatic tick;
        begin
            @(posedge r_clock);
            step = step + 1;
            if (r_reset[0])
                r_if_id_expected = 65'd0;
            else if (r_en[0]) begin
                if (r_flush[0])
                    r_if_id_expected = r_if_id_expected & 65'hffffffffffffffff;
                else if (!r_stall[0]) begin
                    r_if_id_expected = {r_valid[0], r_if_id_pc, r_if_id_instr};
                    if (!r_valid[0])
                        r_if_id_expected = r_if_id_expected & 65'hffffffffffffffff;
                end
            end
            if (r_reset[1])
                r_id_ex_expected = 163'd0;
            else if (r_en[1]) begin
                if (r_flush[1])
                    r_id_ex_expected = r_id_ex_expected & 163'h3ffffffffffffffffffffffffffffffffffff0000;
                else if (!r_stall[1]) begin
                    r_id_ex_expected = {r_valid[1], r_id_ex_pc, r_id_ex_rs1_data, r_id_ex_rs2_data, r_id_ex_imm, r_id_ex_rd, r_id_ex_rs1, r_id_ex_rs2, r_id_ex_funct3, r_id_ex_alu_op, r_id_ex_alu_src_b, r_id_ex_mem_read, r_id_ex_mem_write, r_id_ex_mem_to_reg, r_id_ex_reg_write, r_id_ex_branch, r_id_ex_jump, r_id_ex_jalr, r_id_ex_lui, r_id_ex_halt, r_id_ex_uses_rs1, r_id_ex_uses_rs2};
                    if (!r_valid[1])
                        r_id_ex_expected = r_id_ex_expected & 163'h3ffffffffffffffffffffffffffffffffffff0000;
                end
            end
            if (r_reset[2])
                r_ex_mem_expected = 110'd0;
            else if (r_en[2]) begin
                if (r_flush[2])
                    r_ex_mem_expected = r_ex_mem_expected & 110'h1fffffffffffffffffffffffffe0;
                else if (!r_stall[2]) begin
                    r_ex_mem_expected = {r_valid[2], r_ex_mem_pc, r_ex_mem_result, r_ex_mem_store_data, r_ex_mem_rd, r_ex_mem_funct3, r_ex_mem_mem_read, r_ex_mem_mem_write, r_ex_mem_mem_to_reg, r_ex_mem_reg_write, r_ex_mem_halt};
                    if (!r_valid[2])
                        r_ex_mem_expected = r_ex_mem_expected & 110'h1fffffffffffffffffffffffffe0;
                end
            end
            if (r_reset[3])
                r_mem_wb_expected = 105'd0;
            else if (r_en[3]) begin
                if (r_flush[3])
                    r_mem_wb_expected = r_mem_wb_expected & 105'hfffffffffffffffffffffffff8;
                else if (!r_stall[3]) begin
                    r_mem_wb_expected = {r_valid[3], r_mem_wb_pc, r_mem_wb_result, r_mem_wb_load_data, r_mem_wb_rd, r_mem_wb_mem_to_reg, r_mem_wb_reg_write, r_mem_wb_halt};
                    if (!r_valid[3])
                        r_mem_wb_expected = r_mem_wb_expected & 105'hfffffffffffffffffffffffff8;
                end
            end
            #1;
            check_outputs();
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #5 r_clock = ~r_clock;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL tb_pipeline_regs: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        step = 0;
        r_seed = 32'h12ab_5eed;
        r_reset = 4'hf;
        r_en = 4'd0;
        r_flush = 4'hf;
        r_stall = 4'hf;
        r_valid = 4'd0;
        random_payload();
        tick();

        for (combination = 0; combination < 16; combination = combination + 1) begin
            @(negedge r_clock);
            r_reset = 4'd0;
            r_en = 4'hf;
            r_flush = 4'd0;
            r_stall = 4'd0;
            r_valid = 4'hf;
            random_payload();
            tick();
            @(negedge r_clock);
            r_reset = {4{combination[3]}};
            r_en = {4{combination[2]}};
            r_flush = {4{combination[1]}};
            r_stall = {4{combination[0]}};
            random_payload();
            #1;
            check_outputs();
            tick();
        end

        for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
            @(negedge r_clock);
            r_reset = 4'd0;
            r_en = 4'hf;
            r_flush = 4'd0;
            r_stall = 4'd0;
            r_valid = 4'hf;
            r_if_id_pc = 32'd1 << ((bit_index + 0) % 32);
            r_if_id_instr = 32'd1 << ((bit_index + 1) % 32);
            r_id_ex_pc = 32'd1 << ((bit_index + 0) % 32);
            r_id_ex_rs1_data = 32'd1 << ((bit_index + 1) % 32);
            r_id_ex_rs2_data = 32'd1 << ((bit_index + 2) % 32);
            r_id_ex_imm = 32'd1 << ((bit_index + 3) % 32);
            r_id_ex_rd = 5'd1 << ((bit_index + 4) % 5);
            r_id_ex_rs1 = 5'd1 << ((bit_index + 5) % 5);
            r_id_ex_rs2 = 5'd1 << ((bit_index + 6) % 5);
            r_id_ex_funct3 = 3'd1 << ((bit_index + 7) % 3);
            r_id_ex_alu_op = 4'd1 << ((bit_index + 8) % 4);
            r_id_ex_alu_src_b = 1'd1 << ((bit_index + 9) % 1);
            r_id_ex_mem_read = 1'd1 << ((bit_index + 10) % 1);
            r_id_ex_mem_write = 1'd1 << ((bit_index + 11) % 1);
            r_id_ex_mem_to_reg = 1'd1 << ((bit_index + 12) % 1);
            r_id_ex_reg_write = 1'd1 << ((bit_index + 13) % 1);
            r_id_ex_branch = 1'd1 << ((bit_index + 14) % 1);
            r_id_ex_jump = 1'd1 << ((bit_index + 15) % 1);
            r_id_ex_jalr = 1'd1 << ((bit_index + 16) % 1);
            r_id_ex_lui = 1'd1 << ((bit_index + 17) % 1);
            r_id_ex_halt = 1'd1 << ((bit_index + 18) % 1);
            r_id_ex_uses_rs1 = 1'd1 << ((bit_index + 19) % 1);
            r_id_ex_uses_rs2 = 1'd1 << ((bit_index + 20) % 1);
            r_ex_mem_pc = 32'd1 << ((bit_index + 0) % 32);
            r_ex_mem_result = 32'd1 << ((bit_index + 1) % 32);
            r_ex_mem_store_data = 32'd1 << ((bit_index + 2) % 32);
            r_ex_mem_rd = 5'd1 << ((bit_index + 3) % 5);
            r_ex_mem_funct3 = 3'd1 << ((bit_index + 4) % 3);
            r_ex_mem_mem_read = 1'd1 << ((bit_index + 5) % 1);
            r_ex_mem_mem_write = 1'd1 << ((bit_index + 6) % 1);
            r_ex_mem_mem_to_reg = 1'd1 << ((bit_index + 7) % 1);
            r_ex_mem_reg_write = 1'd1 << ((bit_index + 8) % 1);
            r_ex_mem_halt = 1'd1 << ((bit_index + 9) % 1);
            r_mem_wb_pc = 32'd1 << ((bit_index + 0) % 32);
            r_mem_wb_result = 32'd1 << ((bit_index + 1) % 32);
            r_mem_wb_load_data = 32'd1 << ((bit_index + 2) % 32);
            r_mem_wb_rd = 5'd1 << ((bit_index + 3) % 5);
            r_mem_wb_mem_to_reg = 1'd1 << ((bit_index + 4) % 1);
            r_mem_wb_reg_write = 1'd1 << ((bit_index + 5) % 1);
            r_mem_wb_halt = 1'd1 << ((bit_index + 6) % 1);
            tick();
        end

        for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
            @(negedge r_clock);
            random_payload();
            set_info_pattern(32'h0000_0001 << bit_index);
            tick();
            check_word(w_id_ex_info, 32'h0000_0001 << bit_index, "EX walking info bit");
            check_word(w_ex_mem_info, (32'h0000_0001 << bit_index) & 32'h8783_801f, "MEM walking info bit");
            check_word(w_mem_wb_info, (32'h0000_0001 << bit_index) & 32'h8600_001f, "WB walking info bit");
        end

        for (stage_index = 0; stage_index < 4; stage_index = stage_index + 1) begin
            @(negedge r_clock);
            r_valid = 4'hf ^ (4'd1 << stage_index);
            random_payload();
            tick();
        end

        for (combination = 0; combination < 256; combination = combination + 1) begin
            @(negedge r_clock);
            r_seed = next_random(r_seed);
            r_reset = (combination % 17 == 0) ? r_seed[3:0] : 4'd0;
            r_en = r_seed[7:4];
            r_flush = r_seed[11:8];
            r_stall = r_seed[15:12];
            r_valid = r_seed[19:16];
            random_payload();
            #1;
            check_outputs();
            tick();
        end

        if (errors != 0)
            $fatal(1, "FAIL tb_pipeline_regs: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_pipeline_regs: %0d checks, seed=12ab5eed", checks);
        $finish;
    end
endmodule

`default_nettype wire

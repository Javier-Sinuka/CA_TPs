`timescale 1ns/1ps
`default_nettype none

module tb_fetch;
    reg r_clock;
    reg r_reset;
    reg r_en;
    reg r_imem_we;
    reg [7:0] r_imem_waddr;
    reg [31:0] r_imem_wdata;
    reg [3:0] r_dbg_latch_sel;
    reg [4:0] r_dbg_reg_addr;
    reg [7:0] r_dbg_mem_addr;
    wire w_halted;
    wire [31:0] w_imem_addr;
    wire [31:0] w_imem_data;
    wire [31:0] w_dbg_pc;
    wire [31:0] w_dbg_latch_word;
    wire [31:0] w_dbg_reg_data;
    wire [31:0] w_dbg_mem_data;
    wire w_dbg_mem_dirty;
    reg [31:0] r_program [0:255];
    reg [31:0] r_expected_pc;
    reg [31:0] r_expected_pc_id;
    reg [31:0] r_expected_instr_id;
    reg r_expected_valid_id;
    reg r_expected_valid_ex;
    reg r_expected_valid_mem;
    reg r_expected_valid_wb;
    reg [31:0] r_expected_pc_wb, r_expected_instr_wb;
    reg [31:0] r_expected_result_wb, r_expected_load_wb;
    reg [31:0] r_expected_result_mem, r_expected_store_mem;
    reg [31:0] r_expected_rs1_ex, r_expected_rs2_ex;
    reg [31:0] r_model_regs [0:31];
    reg [31:0] r_model_mem [0:255];
    reg r_model_dirty [0:255];
    reg [31:0] r_reference_info, r_reference_data;
    reg [31:0] r_reference_a, r_reference_b;
    reg [31:0] r_golden_register;
    integer model_index;
    reg [31:0] r_expected_pc_mem, r_expected_instr_mem;
    reg [31:0] r_expected_pc_ex, r_expected_instr_ex;
    reg [31:0] r_seed;
    integer checks;
    integer errors;
    integer index;
    integer cycles;

    cpu u_cpu (
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

    imem u_imem (
        .i_clock(r_clock),
        .i_raddr(w_imem_addr[9:2]),
        .o_rdata(w_imem_data),
        .i_we(r_imem_we),
        .i_waddr(r_imem_waddr),
        .i_wdata(r_imem_wdata)
    );

    function automatic [31:0] expected_decode_imm(input [31:0] instruction);
        begin
            expected_decode_imm = 32'd0;
            casez (instruction)
                32'h0050_0093: expected_decode_imm = 32'd5;
                32'h00a0_0113: expected_decode_imm = 32'd10;
                32'h0ff0_0213: expected_decode_imm = 32'd255;
                32'h0080_02ef: expected_decode_imm = 32'd8;
                32'h0040_8367: expected_decode_imm = 32'd4;
                32'hfff0_0393, 32'hfff4_0493: expected_decode_imm = 32'hffff_ffff;
                32'h0090_2223, 32'h0040_2503: expected_decode_imm = 32'd4;
                32'h0630_0013: expected_decode_imm = 32'd99;
                32'h1234_50b7: expected_decode_imm = 32'h1234_5000;
                default: begin end
            endcase
        end
    endfunction

    function automatic [31:0] expected_decode_info(input [31:0] instruction, input valid);
        reg [31:0] controls;
        begin
            controls = 32'd0;
            if (valid) begin
                casez (instruction)
                    32'h0050_0093, 32'h00a0_0113, 32'h0ff0_0213, 32'hfff0_0393, 32'hfff4_0493, 32'h0630_0013, 32'h0000_0013: controls = 32'h0440_0000;
                    32'h0020_81b3: controls = 32'h0400_0000;
                    32'h0030_2023, 32'h0090_2223: controls = 32'h0140_0000;
                    32'h1234_50b7: controls = 32'h4440_0000;
                    32'h0000_2403, 32'h0040_2503: controls = 32'h06c0_0000;
                    32'h0000_0073: controls = 32'h8000_0000;
                    32'h0080_02ef: controls = 32'h1400_0000;
                    32'h0040_8367: controls = 32'h3440_0000;
                    default: begin end
                endcase
            end
            expected_decode_info = controls | {14'd0, instruction[14:12], instruction[24:20], instruction[19:15], instruction[11:7]};
        end
    endfunction

    function automatic [31:0] expected_execute_result(input [31:0] instruction, input [31:0] pc,
                                                       input [31:0] a, input [31:0] b);
        begin
            expected_execute_result = 32'd0;
            casez (instruction)
                32'h0050_0093: expected_execute_result = a + 32'd5;
                32'h00a0_0113: expected_execute_result = a + 32'd10;
                32'h0ff0_0213: expected_execute_result = a + 32'd255;
                32'hfff0_0393, 32'hfff4_0493: expected_execute_result = a - 32'd1;
                32'h0020_81b3: expected_execute_result = a + b;
                32'h0030_2023, 32'h0000_2403: expected_execute_result = a;
                32'h0090_2223, 32'h0040_2503: expected_execute_result = a + 32'd4;
                32'h0630_0013: expected_execute_result = a + 32'd99;
                32'h1234_50b7: expected_execute_result = 32'h1234_5000;
                32'h0080_02ef, 32'h0040_8367: expected_execute_result = pc + 32'd4;
                default: begin end
            endcase
        end
    endfunction

    function automatic expected_uses_rs1(input [31:0] instruction);
        begin
            expected_uses_rs1 = 1'b0;
            casez (instruction)
                32'h0050_0093, 32'h00a0_0113, 32'h0ff0_0213,
                32'hfff0_0393, 32'hfff4_0493, 32'h0630_0013,
                32'h0000_0013, 32'h0020_81b3, 32'h0030_2023,
                32'h0090_2223, 32'h0000_2403, 32'h0040_2503,
                32'h0040_8367: expected_uses_rs1 = 1'b1;
                default: begin end
            endcase
        end
    endfunction

    function automatic expected_uses_rs2(input [31:0] instruction);
        begin
            expected_uses_rs2 = 1'b0;
            casez (instruction)
                32'h0020_81b3, 32'h0030_2023,
                32'h0090_2223: expected_uses_rs2 = 1'b1;
                default: begin end
            endcase
        end
    endfunction

    task automatic expected_forward(input [4:0] source, input [31:0] captured,
                                    input used, output [31:0] resolved);
        reg [31:0] mem_info;
        reg [31:0] wb_info;
        begin
            resolved = captured;
            mem_info = expected_decode_info(r_expected_instr_mem, r_expected_valid_mem);
            wb_info = expected_decode_info(r_expected_instr_wb, r_expected_valid_wb);
            if (r_expected_valid_ex && used && source != 5'd0) begin
                if (r_expected_valid_mem && mem_info[26] && mem_info[4:0] == source) begin
                    if (!mem_info[23]) resolved = r_expected_result_mem;
                end else if (r_expected_valid_wb && wb_info[26] && wb_info[4:0] == source) begin
                    resolved = wb_info[25] ? r_expected_load_wb : r_expected_result_wb;
                end
            end
        end
    endtask

    function automatic [31:0] model_load(input [31:0] address, input [2:0] funct3);
        reg [31:0] word_value;
        reg [7:0] byte_value;
        reg [15:0] half_value;
        begin
            word_value = r_model_dirty[address[9:2]] ? r_model_mem[address[9:2]] : 32'd0;
            byte_value = word_value[address[1:0]*8 +: 8];
            half_value = word_value[address[1]*16 +: 16];
            model_load = 32'd0;
            casez (funct3)
                3'd0: model_load = {{24{byte_value[7]}}, byte_value};
                3'd1: model_load = {{16{half_value[15]}}, half_value};
                3'd2: model_load = word_value;
                3'd4: model_load = {24'd0, byte_value};
                3'd5: model_load = {16'd0, half_value};
                default: begin end
            endcase
        end
    endfunction

    task automatic model_store(input [31:0] address, input [2:0] funct3, input [31:0] data);
        begin
            if (funct3 <= 3'd2) begin
                if (!r_model_dirty[address[9:2]]) r_model_mem[address[9:2]] = 32'd0;
                casez (funct3)
                    3'd0: r_model_mem[address[9:2]][address[1:0]*8 +: 8] = data[7:0];
                    3'd1: r_model_mem[address[9:2]][address[1]*16 +: 16] = data[15:0];
                    3'd2: r_model_mem[address[9:2]] = data;
                    default: begin end
                endcase
                r_model_dirty[address[9:2]] = 1'b1;
            end
        end
    endtask

    task automatic check_word(input [31:0] got, input [31:0] expected,
                              input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL fetch: cycle=%0d %s expected=%08h got=%08h",
                         cycles, label, expected, got);
            end
        end
    endtask

    task automatic check_state;
        begin
            check_word(w_imem_addr, r_expected_pc, "byte address");
            check_word(w_dbg_pc, r_expected_pc, "debug byte PC");
            check_word(u_cpu.w_pc_id, r_expected_pc_id, "ID PC");
            check_word(u_cpu.w_instr_id, r_expected_instr_id, "ID instruction");
            check_word({31'd0, u_cpu.w_valid_id},
                       {31'd0, r_expected_valid_id}, "ID valid");
            check_word(u_cpu.w_pc_ex, r_expected_pc_ex, "EX PC from previous ID");
            check_word({31'd0, u_cpu.w_valid_ex}, {31'd0, r_expected_valid_ex}, "EX valid");
            check_word(u_cpu.w_imm_ex, expected_decode_imm(r_expected_instr_ex), "EX immediate");
            check_word(u_cpu.w_info_ex, expected_decode_info(r_expected_instr_ex, r_expected_valid_ex), "EX controls and metadata");
            check_word(u_cpu.w_rs1_data_ex, r_expected_rs1_ex, "EX captured rs1");
            check_word(u_cpu.w_rs2_data_ex, r_expected_rs2_ex, "EX captured rs2");
            check_word(u_cpu.w_pc_mem, r_expected_pc_mem, "MEM PC from previous EX");
            check_word({31'd0, u_cpu.w_valid_mem}, {31'd0, r_expected_valid_mem}, "MEM valid");
            check_word(u_cpu.w_result_mem, r_expected_result_mem, "MEM result and link from EX PC");
            check_word(u_cpu.w_store_data_mem, r_expected_store_mem, "MEM store data");
            check_word(u_cpu.w_info_mem, expected_decode_info(r_expected_instr_mem, r_expected_valid_mem) & 32'h8783_801f, "MEM controls and metadata");
            check_word(u_cpu.w_pc_wb, r_expected_pc_wb, "WB PC");
            check_word({31'd0, u_cpu.w_valid_wb}, {31'd0, r_expected_valid_wb}, "WB valid");
            check_word(u_cpu.w_result_wb, r_expected_result_wb, "WB result or address");
            check_word(u_cpu.w_load_data_wb, r_expected_load_wb, "WB captured load");
            check_word(u_cpu.w_info_wb, expected_decode_info(r_expected_instr_wb, r_expected_valid_wb) & 32'h8600_001f, "WB info");
            check_word(w_dbg_reg_data, r_model_regs[r_dbg_reg_addr], "committed register debug");
            check_word(w_dbg_mem_data, r_model_dirty[r_dbg_mem_addr] ? r_model_mem[r_dbg_mem_addr] : 32'd0, "committed memory debug");
            check_word({31'd0, w_dbg_mem_dirty}, {31'd0, r_model_dirty[r_dbg_mem_addr]}, "committed dirty");
            check_word(w_imem_data, r_program[(r_expected_pc / 4) % 256],
                       "asynchronous imem");
            check_word({31'd0, w_halted}, 32'd0, "HALT not implemented yet");
        end
    endtask

    task automatic tick;
        begin
            @(posedge r_clock);
            cycles = cycles + 1;
            if (r_reset) begin
                r_expected_pc = 32'd0;
                r_expected_pc_id = 32'd0;
                r_expected_instr_id = 32'd0;
                r_expected_valid_id = 1'b0;
                r_expected_valid_ex = 1'b0;
                r_expected_pc_ex = 32'd0;
                r_expected_instr_ex = 32'd0;
                r_expected_valid_mem = 1'b0;
                r_expected_pc_mem = 32'd0;
                r_expected_instr_mem = 32'd0;
                r_expected_valid_wb = 1'b0;
                r_expected_pc_wb = 32'd0;
                r_expected_instr_wb = 32'd0;
                r_expected_result_wb = 32'd0;
                r_expected_load_wb = 32'd0;
                r_expected_result_mem = 32'd0;
                r_expected_store_mem = 32'd0;
                r_expected_rs1_ex = 32'd0;
                r_expected_rs2_ex = 32'd0;
                for (model_index = 0; model_index < 32; model_index = model_index + 1) r_model_regs[model_index] = 32'd0;
                for (model_index = 0; model_index < 256; model_index = model_index + 1) r_model_dirty[model_index] = 1'b0;
            end else if (r_en) begin
                r_reference_info = expected_decode_info(r_expected_instr_wb, r_expected_valid_wb);
                if (r_expected_valid_wb && r_reference_info[26] && r_reference_info[4:0] != 5'd0)
                    r_model_regs[r_reference_info[4:0]] = r_reference_info[25] ? r_expected_load_wb : r_expected_result_wb;
                r_reference_info = expected_decode_info(r_expected_instr_mem, r_expected_valid_mem);
                r_reference_data = (r_expected_valid_mem && r_reference_info[23]) ? model_load(r_expected_result_mem, r_expected_instr_mem[14:12]) : 32'd0;
                if (r_expected_valid_mem && r_reference_info[24])
                    model_store(r_expected_result_mem, r_expected_instr_mem[14:12], r_expected_store_mem);
                expected_forward(r_expected_instr_ex[19:15], r_expected_rs1_ex,
                                 expected_uses_rs1(r_expected_instr_ex), r_reference_a);
                expected_forward(r_expected_instr_ex[24:20], r_expected_rs2_ex,
                                 expected_uses_rs2(r_expected_instr_ex), r_reference_b);
                r_expected_pc_wb = r_expected_pc_mem;
                r_expected_instr_wb = r_expected_instr_mem;
                r_expected_valid_wb = r_expected_valid_mem;
                r_expected_result_wb = r_expected_result_mem;
                r_expected_load_wb = r_reference_data;
                r_expected_result_mem = expected_execute_result(r_expected_instr_ex, r_expected_pc_ex, r_reference_a, r_reference_b);
                r_expected_store_mem = r_reference_b;
                r_expected_pc_mem = r_expected_pc_ex;
                r_expected_instr_mem = r_expected_instr_ex;
                r_expected_valid_mem = r_expected_valid_ex;
                r_expected_rs1_ex = r_model_regs[r_expected_instr_id[19:15]];
                r_expected_rs2_ex = r_model_regs[r_expected_instr_id[24:20]];
                r_expected_pc_ex = r_expected_pc_id;
                r_expected_instr_ex = r_expected_instr_id;
                r_expected_valid_ex = r_expected_valid_id;
                r_expected_pc_id = r_expected_pc;
                r_expected_instr_id = r_program[(r_expected_pc / 4) % 256];
                r_expected_valid_id = 1'b1;
                r_expected_pc = r_expected_pc + 32'd4;
            end
            if (r_imem_we)
                r_program[r_imem_waddr] = r_imem_wdata;
            #1;
            check_state();
        end
    endtask

    task automatic write_instruction(input [7:0] address, input [31:0] data);
        begin
            @(negedge r_clock);
            r_imem_we = 1'b1;
            r_imem_waddr = address;
            r_imem_wdata = data;
            tick();
            @(negedge r_clock);
            r_imem_we = 1'b0;
        end
    endtask

    task automatic check_debug;
        begin
            r_dbg_latch_sel = 4'd0;
            #1;
            check_word(w_dbg_latch_word, r_expected_pc_id, "selector 0");
            r_dbg_latch_sel = 4'd1;
            #1;
            check_word(w_dbg_latch_word, r_expected_instr_id, "selector 1");
            r_dbg_latch_sel = 4'd2;
            #1;
            check_word(w_dbg_latch_word, r_expected_pc_ex, "selector 2");
            r_dbg_latch_sel = 4'd3;
            #1;
            check_word(w_dbg_latch_word, r_expected_rs1_ex, "selector 3 captured rs1");
            r_dbg_latch_sel = 4'd4;
            #1;
            check_word(w_dbg_latch_word, r_expected_rs2_ex, "selector 4 captured rs2");
            r_dbg_latch_sel = 4'd5;
            #1;
            check_word(w_dbg_latch_word, expected_decode_imm(r_expected_instr_ex), "selector 5");
            r_dbg_latch_sel = 4'd6;
            #1;
            check_word(w_dbg_latch_word, expected_decode_info(r_expected_instr_ex, r_expected_valid_ex), "selector 6");
            r_dbg_latch_sel = 4'd15;
            #1;
            check_word(w_dbg_latch_word, {28'd0, r_expected_valid_wb, r_expected_valid_mem, r_expected_valid_ex, r_expected_valid_id}, "selector 15");
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #10 r_clock = ~r_clock;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL tb_fetch: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        cycles = 0;
        r_seed = 32'h13fe_7c01;
        r_reset = 1'b1;
        r_en = 1'b0;
        r_imem_we = 1'b0;
        r_imem_waddr = 8'd0;
        r_imem_wdata = 32'd0;
        r_dbg_latch_sel = 4'd0;
        r_dbg_reg_addr = 5'd0;
        r_dbg_mem_addr = 8'd0;
        for (index = 0; index < 256; index = index + 1)
            r_program[index] = 32'h0000_0073;
        tick();
        check_debug();

        write_instruction(8'd0, 32'h0050_0093);
        write_instruction(8'd1, 32'h00a0_0113);
        write_instruction(8'd2, 32'h0020_81b3);
        write_instruction(8'd3, 32'h0030_2023);
        write_instruction(8'd255, 32'h1234_50b7);
        write_instruction(8'd4, 32'h0000_0013);
        write_instruction(8'd5, 32'h0000_0013);
        write_instruction(8'd6, 32'hfff0_0393);
        check_word(w_imem_data, 32'h0050_0093, "load while reset asserted");

        @(negedge r_clock);
        r_reset = 1'b0;
        repeat (3) begin
            tick();
            @(negedge r_clock);
        end
        check_word(w_imem_addr, 32'd0, "pause before first fetch");
        check_word({31'd0, u_cpu.w_valid_id}, 32'd0, "no capture while paused");

        r_en = 1'b1;
        tick();
        check_word(u_cpu.w_pc_id, 32'd0, "first PC");
        check_word(u_cpu.w_instr_id, 32'h0050_0093, "first instruction");
        check_word(w_imem_addr, 32'd4, "next fetch address");
        $display("TRACE tb_fetch: IF=%08h ID=%08h instruction=%08h",
                 w_imem_addr, u_cpu.w_pc_id, u_cpu.w_instr_id);

        @(negedge r_clock);
        r_en = 1'b0;
        repeat (100) begin
            r_dbg_reg_addr = r_dbg_reg_addr + 5'd1;
            r_dbg_mem_addr = r_dbg_mem_addr + 8'd1;
            check_debug();
            tick();
            @(negedge r_clock);
        end
        r_en = 1'b1;
        tick();
        check_word(u_cpu.w_pc_id, 32'd4, "second PC");
        check_word(u_cpu.w_instr_id, 32'h00a0_0113, "second instruction");
        $display("TRACE tb_fetch: IF=%08h ID=%08h instruction=%08h",
                 w_imem_addr, u_cpu.w_pc_id, u_cpu.w_instr_id);
        @(negedge r_clock);
        tick();
        check_word(u_cpu.w_pc_id, 32'd8, "third PC");
        check_word(u_cpu.w_instr_id, 32'h0020_81b3, "third instruction");
        $display("TRACE tb_fetch: IF=%08h ID=%08h instruction=%08h",
                 w_imem_addr, u_cpu.w_pc_id, u_cpu.w_instr_id);

        @(negedge r_clock);
        r_en = 1'b0;
        write_instruction(8'd3, 32'h0ff0_0213);
        check_word(w_imem_data, 32'h0ff0_0213, "paused program write visible");
        check_word(u_cpu.w_instr_id, 32'h0020_81b3, "paused IFID unchanged by imem write");
        r_reset = 1'b1;
        #1;
        check_word(w_dbg_pc, 32'd12, "reset remains synchronous");
        tick();
        check_debug();
        check_word(w_imem_data, 32'h0050_0093, "reset preserves program");
        @(negedge r_clock);
        r_reset = 1'b0;
        r_en = 1'b1;
        repeat (258) begin
            tick();
            @(negedge r_clock);
        end
        check_word(w_imem_addr, 32'd1032, "full byte PC after wrap");
        check_word(u_cpu.w_pc_id, 32'd1028, "full ID PC after wrap");
        check_word(u_cpu.w_instr_id, 32'h00a0_0113, "wrapped instruction index 1");

        for (index = 0; index < 128; index = index + 1) begin
            r_seed = r_seed * 32'd1664525 + 32'd1013904223;
            r_en = r_seed[31];
            check_state();
            tick();
            @(negedge r_clock);
        end
        r_en = 1'b1;
        r_reset = 1'b1;
        tick();
        @(negedge r_clock);
        r_reset = 1'b0;
        repeat (4) begin
            tick();
            @(negedge r_clock);
        end
        check_word(u_cpu.w_instr_id, 32'h0ff0_0213, "new program word survives reset");
        r_en = 1'b0;
        r_dbg_latch_sel = 4'd7;
        #1;
        check_word(w_dbg_latch_word, r_expected_pc_mem, "selector 7");
        r_dbg_latch_sel = 4'd8;
        #1;
        check_word(w_dbg_latch_word, r_expected_result_mem, "selector 8");
        r_dbg_latch_sel = 4'd9;
        #1;
        check_word(w_dbg_latch_word, r_expected_store_mem, "selector 9 store data");
        r_dbg_latch_sel = 4'd10;
        #1;
        check_word(w_dbg_latch_word, expected_decode_info(r_expected_instr_mem, r_expected_valid_mem) & 32'h8783_801f, "selector 10");
        r_dbg_latch_sel = 4'd11;
        #1;
        check_word(w_dbg_latch_word, r_expected_pc_wb, "selector 11");
        r_dbg_latch_sel = 4'd12;
        #1;
        check_word(w_dbg_latch_word, r_expected_result_wb, "selector 12");
        r_dbg_latch_sel = 4'd13;
        #1;
        check_word(w_dbg_latch_word, r_expected_load_wb, "selector 13");
        r_dbg_latch_sel = 4'd14;
        #1;
        check_word(w_dbg_latch_word, expected_decode_info(r_expected_instr_wb, r_expected_valid_wb) & 32'h8600_001f, "selector 14");
        r_dbg_latch_sel = 4'bzzzz;
        #1;
        check_word(w_dbg_latch_word, 32'd0, "unknown selector");
        r_dbg_latch_sel = 4'bxxxx;
        #1;
        check_word(w_dbg_latch_word, 32'd0, "unknown selector");
        check_state();

        @(negedge r_clock);
        r_reset = 1'b1;
        r_en = 1'b0;
        tick();
        for (index = 0; index < 32; index = index + 1) begin
            casez (index)
                0: r_reference_data = 32'h0050_0093;
                4: r_reference_data = 32'h00a0_0113;
                8: r_reference_data = 32'h0020_81b3;
                12: r_reference_data = 32'h0030_2023;
                13: r_reference_data = 32'h0000_2403;
                17: r_reference_data = 32'hfff4_0493;
                21: r_reference_data = 32'h0090_2223;
                22: r_reference_data = 32'h0040_2503;
                26: r_reference_data = 32'h0630_0013;
                default: r_reference_data = 32'h0000_0013;
            endcase
            write_instruction(index[7:0], r_reference_data);
        end
        r_reset = 1'b0;
        r_en = 1'b1;
        repeat (36) begin
            tick();
            @(negedge r_clock);
        end
        r_en = 1'b0;
        for (index = 0; index < 32; index = index + 1) begin
            r_dbg_reg_addr = index[4:0];
            r_golden_register = 32'd0;
            casez (index)
                1: r_golden_register = 32'd5;
                2: r_golden_register = 32'd10;
                3, 8: r_golden_register = 32'd15;
                9, 10: r_golden_register = 32'd14;
                default: begin end
            endcase
            #1;
            check_word(w_dbg_reg_data, r_golden_register, "independent no-hazard program golden");
        end
        r_dbg_mem_addr = 8'd0;
        #1;
        check_word(w_dbg_mem_data, 32'd15, "program stores first result");
        check_word({31'd0, w_dbg_mem_dirty}, 32'd1, "program first word dirty");
        r_dbg_mem_addr = 8'd1;
        #1;
        check_word(w_dbg_mem_data, 32'd14, "program stores loaded arithmetic result");
        check_word({31'd0, w_dbg_mem_dirty}, 32'd1, "program second word dirty");
        r_dbg_mem_addr = 8'd2;
        #1;
        check_word(w_dbg_mem_data, 32'd0, "program leaves next word clean");
        check_word({31'd0, w_dbg_mem_dirty}, 32'd0, "program next word not dirty");

        if (errors != 0)
            $fatal(1, "FAIL tb_fetch: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_fetch: %0d checks, seed=13fe7c01", checks);
        $finish;
    end
endmodule

`default_nettype wire

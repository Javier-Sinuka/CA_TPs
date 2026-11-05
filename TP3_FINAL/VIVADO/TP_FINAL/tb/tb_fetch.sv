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
            end else if (r_en) begin
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
            r_dbg_latch_sel = 4'd15;
            #1;
            check_word(w_dbg_latch_word, {31'd0, r_expected_valid_id}, "selector 15");
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
        for (index = 2; index < 15; index = index + 1) begin
            r_dbg_latch_sel = index[3:0];
            #1;
            check_word(w_dbg_latch_word, 32'd0, "unimplemented selector");
        end
        r_dbg_latch_sel = 4'bzzzz;
        #1;
        check_word(w_dbg_latch_word, 32'd0, "unknown selector");
        r_dbg_latch_sel = 4'bxxxx;
        #1;
        check_word(w_dbg_latch_word, 32'd0, "unknown selector");
        check_state();

        if (errors != 0)
            $fatal(1, "FAIL tb_fetch: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_fetch: %0d checks, seed=13fe7c01", checks);
        $finish;
    end
endmodule

`default_nettype wire

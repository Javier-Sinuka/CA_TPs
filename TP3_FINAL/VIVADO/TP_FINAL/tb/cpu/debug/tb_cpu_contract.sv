`timescale 1ns/1ps
`default_nettype none

module tb_cpu_contract;
    reg r_clock = 0;
    reg r_reset = 0;
    reg r_en = 0;
    reg r_imem_we = 0;
    reg [7:0] r_imem_waddr = 0;
    reg [31:0] r_imem_wdata = 0;
    reg [4:0] r_dbg_reg_addr = 0;
    reg [3:0] r_dbg_latch_sel = 0;
    reg [7:0] r_dbg_mem_addr = 0;
    wire [31:0] w_imem_addr, w_imem_data;
    wire [31:0] w_dbg_pc, w_dbg_reg_data, w_dbg_latch_word, w_dbg_mem_data;
    wire w_halted, w_dbg_mem_dirty;
    reg [31:0] r_program [0:255];
    reg [31:0] r_expected_regs [0:31];
    reg [31:0] r_expected_mem [0:255];
    reg [255:0] r_expected_dirty = 0;
    reg [31:0] r_snapshot [0:562];
    integer checks = 0;
    integer errors = 0;
    integer cycles = 0;
    integer scenario = 0;
    integer n, count;

`ifdef CPU_STUB
    cpu_stub #(.HALT_AT(20)) u_cpu (
`else
    cpu u_cpu (
`endif
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .o_halted(w_halted), .o_imem_addr(w_imem_addr), .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr), .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel), .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr), .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty), .o_dbg_pc(w_dbg_pc)
    );

    imem u_imem (
        .i_clock(r_clock), .i_raddr(w_imem_addr[9:2]), .o_rdata(w_imem_data),
        .i_we(r_imem_we), .i_waddr(r_imem_waddr), .i_wdata(r_imem_wdata)
    );

    task automatic check_word(input [31:0] got, input [31:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL tb_cpu_contract: scenario=%0d cycles=%0d %s expected=%08h got=%08h",
                         scenario, cycles, label, expected, got);
                if ($test$plusargs("FAIL_FAST")) $fatal(1, "FAIL tb_cpu_contract: first discrepancy");
            end
        end
    endtask

    task automatic pulse(input bit enable, input bit reset);
        reg advance;
        begin
            r_en = enable;
            r_reset = reset;
            #2;
            check_word(w_dbg_pc, w_imem_addr, "public PC and instruction byte address");
            check_word(w_imem_data, r_program[w_imem_addr[9:2]], "external instruction word");
            advance = enable && !reset && !w_halted;
            r_clock = 1;
            #1;
            if (reset) cycles = 0;
            else if (advance) cycles = cycles + 1;
            r_clock = 0;
            #1;
        end
    endtask

    task automatic scan(input bit compare_snapshot, input bit check_architecture);
        integer i;
        reg [31:0] value;
        begin
            check_word(r_en, 0, "debug scans require pause");
            for (i = 0; i < 563; i = i + 1) begin
                if (i >= 3 && i < 35) r_dbg_reg_addr = i - 3;
                else if (i >= 35 && i < 51) r_dbg_latch_sel = i - 35;
                else if (i >= 51) r_dbg_mem_addr = (i - 51) / 2;
                #1;
                casez (i)
                    0: value = w_dbg_pc;
                    1: value = w_imem_addr;
                    2: value = {31'd0, w_halted};
                    default: begin
                        if (i < 35) value = w_dbg_reg_data;
                        else if (i < 51) value = w_dbg_latch_word;
                        else if (i[0]) value = {31'd0, w_dbg_mem_dirty};
                        else value = w_dbg_mem_data;
                    end
                endcase
                if (compare_snapshot) check_word(value, r_snapshot[i], "paused complete public state");
                else r_snapshot[i] = value;
`ifdef CPU_STUB
                if (i < 2) check_word(value, cycles * 4, "stub byte PC");
                else if (i == 2) check_word(value, cycles == 20, "stub HALT");
                else if (i < 35)
                    check_word(value, i == 3 ? 0 : (cycles * 256) + i - 3, "independent stub register");
                else if (i < 51)
                    check_word(value, 32'h1a000000 + ((i-35)*65536) + cycles, "independent stub latch");
                else if (i[0])
                    check_word(value, cycles != 0 && ((i-51)/2 == 4 || (i-51)/2 == 16 || (i-51)/2 == 63), "independent stub dirty");
                else begin
                    if (cycles != 0 && ((i-51)/2 == 4 || (i-51)/2 == 16 || (i-51)/2 == 63))
                        check_word(value, 32'hd0000000 + (i-51)/2, "independent stub memory");
                    else check_word(value, 0, "clean stub memory");
                end
`else
                if (check_architecture) begin
                    if (i >= 3 && i < 35) check_word(value, r_expected_regs[i-3], "independent CPU register");
                    else if (i >= 51 && i[0]) check_word(value, r_expected_dirty[(i-51)/2], "independent CPU dirty");
                    else if (i >= 51) check_word(value, r_expected_mem[(i-51)/2], "independent CPU memory");
                    if (scenario == 0 && i >= 35 && i < 51) check_word(value, 0, "reset CPU latches");
                end
                if (i == 45) check_word(value & ~32'h8783801f, 0, "MEM absent info fields");
                if (i == 49) check_word(value & ~32'h8600001f, 0, "WB absent info fields");
                if (i == 50) check_word(value & 32'hffffff00, 0, "reserved flags");
`endif
            end
            for (i = 0; i < 256; i = i + 1)
                check_word(u_imem.r_mem[i], r_program[i], "program unchanged by CPU reset or debug reads");
        end
    endtask

    task automatic freeze(input bit check_architecture);
        begin
            r_en = 0;
            #1;
            scan(0, check_architecture);
            pulse(0, 0);
            scan(1, check_architecture);
            pulse(0, 0);
            scan(1, check_architecture);
        end
    endtask

    task automatic write_program_word(input [7:0] address, input [31:0] value);
        begin
            r_imem_we = 1;
            r_imem_waddr = address;
            r_imem_wdata = value;
            pulse(0, r_reset);
            r_program[address] = value;
            r_imem_we = 0;
            #1;
        end
    endtask

    task automatic clear_expectations;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1) r_expected_regs[i] = 0;
            for (i = 0; i < 256; i = i + 1) r_expected_mem[i] = 0;
            r_expected_dirty = 0;
        end
    endtask

    task automatic reset_cpu;
        begin
            scenario = 0;
            pulse(0, 1);
            r_reset = 0;
            clear_expectations();
            check_word(w_halted, 0, "reset clears HALT despite enable zero");
            check_word(w_dbg_pc, 0, "reset clears byte PC");
            freeze(1);
        end
    endtask

`ifndef CPU_STUB
    task automatic run_cpu(input integer limit, input integer halt_pc);
        integer enabled;
        begin
            enabled = 0;
            while (!w_halted && enabled < limit) begin
                pulse(1, 0);
                enabled = enabled + 1;
                if (enabled % 37 == 0) freeze(0);
            end
            r_en = 0;
            #1;
            check_word(w_halted, 1, "CPU program reaches HALT");
            r_dbg_latch_sel = 11;
            #1;
            check_word(w_dbg_latch_word, halt_pc, "public WB HALT PC");
            check_word(w_dbg_pc, halt_pc + 4, "public IF byte PC after HALT");
            r_dbg_latch_sel = 15;
            #1;
            check_word(w_dbg_latch_word, 32'h98, "HALT flags and drained pipeline");
        end
    endtask
`endif

    initial begin
        #10000000;
        $fatal(1, "FAIL tb_cpu_contract: watchdog");
    end

    initial begin
        clear_expectations();
        for (n = 0; n < 256; n = n + 1) r_program[n] = 32'h00000073;
        #1;
        for (n = 0; n < 256; n = n + 1)
            check_word(u_imem.r_mem[n], 32'h00000073, "external imem initially HALT");
        reset_cpu();
`ifdef CPU_STUB
        write_program_word(0, 32'hffffffff);
        write_program_word(255, 32'h12345678);
        freeze(1);
        for (count = 0; count < 20; count = count + 1) begin
            pulse(1, 0);
            freeze(1);
        end
        check_word(w_halted, 1, "stub stops at its synthetic cycle limit");
        repeat (3) pulse(1, 0);
        r_en = 0;
        #1;
        scan(1, 1);
        freeze(1);
        reset_cpu();
        pulse(1, 0);
        freeze(1);
`else
        r_reset = 1;
        write_program_word(0, 32'h00000093);
        write_program_word(1, 32'h10100113);
        write_program_word(2, 32'h00100193);
        write_program_word(3, 32'h0030a023);
        write_program_word(4, 32'h00408093);
        write_program_word(5, 32'h00118193);
        write_program_word(6, 32'hfe219ae3);
        write_program_word(7, 32'h3e002e23);
        for (n = 1; n < 32; n = n + 1)
            write_program_word(n + 7, ((n*17+1) << 20) | (n << 7) | 32'h13);
        write_program_word(39, 32'h00000073);
        reset_cpu();
        scenario = 1;
        run_cpu(1700, 156);
        for (n = 1; n < 32; n = n + 1) r_expected_regs[n] = n*17+1;
        for (n = 0; n < 256; n = n + 1) r_expected_mem[n] = n == 255 ? 0 : n+1;
        r_expected_dirty = {256{1'b1}};
        freeze(1);
        write_program_word(254, 32'h13579bdf);
        scan(1, 1);
        repeat (3) pulse(1, 0);
        r_en = 0;
        #1;
        scan(1, 1);
        freeze(1);
        reset_cpu();
        r_reset = 1;
        write_program_word(0, 32'h05a00093);
        write_program_word(1, 32'h001000a3);
        write_program_word(2, 32'hfff00113);
        write_program_word(3, 32'h1e201f23);
        write_program_word(4, 32'h20002023);
        write_program_word(5, 32'h3e102fa3);
        write_program_word(6, 32'h40102823);
        write_program_word(7, 32'h00002183);
        write_program_word(8, 32'h1fc02203);
        write_program_word(9, 32'h20002283);
        write_program_word(10, 32'h3fc02303);
        write_program_word(11, 32'h01002383);
        write_program_word(12, 32'h1f802403);
        write_program_word(13, 32'h00000073);
        reset_cpu();
        scenario = 2;
        run_cpu(64, 52);
        r_expected_regs[1] = 32'h5a;
        r_expected_regs[2] = 32'hffffffff;
        r_expected_regs[3] = 32'h00005a00;
        r_expected_regs[4] = 32'hffff0000;
        r_expected_regs[6] = 32'h5a;
        r_expected_regs[7] = 32'h5a;
        r_expected_mem[0] = 32'h00005a00;
        r_expected_mem[4] = 32'h5a;
        r_expected_mem[127] = 32'hffff0000;
        r_expected_mem[128] = 0;
        r_expected_mem[255] = 32'h5a;
        r_expected_dirty[0] = 1;
        r_expected_dirty[4] = 1;
        r_expected_dirty[127] = 1;
        r_expected_dirty[128] = 1;
        r_expected_dirty[255] = 1;
        freeze(1);
        reset_cpu();
        r_reset = 1;
        write_program_word(0, 32'h4080006f);
        write_program_word(2, 32'h07b00093);
        write_program_word(3, 32'h00000073);
        reset_cpu();
        scenario = 3;
        run_cpu(32, 1036);
        r_expected_regs[1] = 123;
        freeze(1);
        reset_cpu();
`endif
        if (errors != 0) $fatal(1, "FAIL tb_cpu_contract: %0d errors in %0d checks", errors, checks);
`ifdef CPU_STUB
        $display("PASS tb_cpu_contract: %0d checks, stub, common public wiring and complete paused scans", checks);
`else
        $display("PASS tb_cpu_contract: %0d checks, real CPU, 256 dirty words, reset, partial stores and external imem", checks);
`endif
        $finish;
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_system_cpu_smoke;
    localparam integer CLOCK_FREQ = 50000000;
    localparam integer BAUD_RATE = 1562500;
    localparam integer RUN_LIMIT = 1000;
    reg r_clock = 0;
    reg r_reset = 1;
    reg bfm_rx = 1;
    wire bfm_tx;
    wire [7:0] w_leds;
    reg [31:0] r_program [0:255];
    reg [31:0] r_golden [0:4479];
    reg [31:0] r_cpu_snapshot [0:562];
    reg [7:0] r_frame [0:2257];
    reg [7:0] r_previous [0:2257];
    reg r_edge_advance, r_edge_reset, r_edge_enable;
    integer checks = 0;
    integer errors = 0;
    integer observed_cycles = 0;
    integer enable_edges = 0;
    integer reset_edges = 0;
    integer imem_writes = 0;
    integer frame_length, previous_length, dirty_count, saved_cycles;
    integer n, step_index, before_enable, before_cycles, before_reset, before_writes;
    integer log_file;
    reg r_seen_stall = 0;
    reg r_seen_take = 0;
    string r_root, r_output, r_label;

    system #(
        .CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(BAUD_RATE),
        .BYTE_TIMEOUT(20000), .RUN_TIMEOUT(RUN_LIMIT)
    ) dut (
        .i_clock(r_clock), .i_reset(r_reset), .i_rx(bfm_rx), .o_tx(bfm_tx), .o_leds(w_leds)
    );

    `include "uart_bfm.svh"

    initial begin
        forever #10 r_clock = ~r_clock;
    end

    initial begin
        forever begin
            @(negedge r_clock);
            r_edge_reset = dut.w_cpu_reset;
            r_edge_enable = dut.w_cpu_en;
            r_edge_advance = dut.w_cpu_en && !dut.w_cpu_halted && !dut.w_cpu_reset;
            if (dut.w_imem_we && !dut.w_cpu_reset)
                $fatal(1, "FAIL tb_system_cpu_smoke: instruction write without CPU reset");
            if (dut.w_cpu_reset && dut.w_cpu_en)
                $fatal(1, "FAIL tb_system_cpu_smoke: CPU enabled while held in reset");
            if (dut.w_imem_we) imem_writes = imem_writes + 1;
            @(posedge r_clock);
            #1;
            if (r_edge_reset) begin
                observed_cycles = 0;
                reset_edges = reset_edges + 1;
            end else if (r_edge_advance) observed_cycles = observed_cycles + 1;
            if (r_edge_enable) enable_edges = enable_edges + 1;
        end
    end

    function automatic [31:0] latch_word(input integer selector);
        begin
            casez (selector)
                0: latch_word = dut.u_cpu.w_pc_id;
                1: latch_word = dut.u_cpu.w_instr_id;
                2: latch_word = dut.u_cpu.w_pc_ex;
                3: latch_word = dut.u_cpu.w_rs1_data_ex;
                4: latch_word = dut.u_cpu.w_rs2_data_ex;
                5: latch_word = dut.u_cpu.w_imm_ex;
                6: latch_word = dut.u_cpu.w_info_ex;
                7: latch_word = dut.u_cpu.w_pc_mem;
                8: latch_word = dut.u_cpu.w_result_mem;
                9: latch_word = dut.u_cpu.w_store_data_mem;
                10: latch_word = dut.u_cpu.w_info_mem;
                11: latch_word = dut.u_cpu.w_pc_wb;
                12: latch_word = dut.u_cpu.w_result_wb;
                13: latch_word = dut.u_cpu.w_load_data_wb;
                14: latch_word = dut.u_cpu.w_info_wb;
                15: latch_word = {
                    24'd0, dut.u_cpu.w_stop_fetch, dut.u_cpu.w_take_ex,
                    dut.u_cpu.w_load_use_stall, dut.w_cpu_halted,
                    dut.u_cpu.w_valid_wb, dut.u_cpu.w_valid_mem,
                    dut.u_cpu.w_valid_ex, dut.u_cpu.w_valid_id
                };
                default: latch_word = 0;
            endcase
        end
    endfunction

    function automatic [31:0] cpu_word(input integer index);
        begin
            casez (index)
                0: cpu_word = dut.w_dbg_pc;
                1: cpu_word = dut.w_imem_addr;
                2: cpu_word = {31'd0, dut.w_cpu_halted};
                default: begin
                    if (index < 35)
                        cpu_word = index == 3 ? 0 : dut.u_cpu.u_decode.u_regfile.r_regs[index-3];
                    else if (index < 51) cpu_word = latch_word(index-35);
                    else if (index[0]) cpu_word = {31'd0, dut.u_cpu.u_memory.u_dmem.r_dirty[(index-51)/2]};
                    else cpu_word = dut.u_cpu.u_memory.u_dmem.r_dirty[(index-51)/2]
                                  ? dut.u_cpu.u_memory.u_dmem.r_mem[(index-51)/2] : 0;
                end
            endcase
        end
    endfunction

    function automatic [31:0] frame_word(input integer index);
        integer offset;
        begin
            offset = 1 + 4*index;
            frame_word = {r_frame[offset+3], r_frame[offset+2], r_frame[offset+1], r_frame[offset]};
        end
    endfunction

    task check_word(input [31:0] got, input [31:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL tb_system_cpu_smoke: case=%s %s expected=%08h got=%08h", r_label, label, expected, got);
                if ($test$plusargs("FAIL_FAST")) $fatal(1, "FAIL tb_system_cpu_smoke: first discrepancy");
            end
        end
    endtask

    task send_byte(input [7:0] value);
        begin
            $fdisplay(log_file, "> %02x", value);
            bfm_send_byte(value);
        end
    endtask

    task receive_byte(output reg [7:0] value);
        reg ok;
        begin
            bfm_recv_byte(value, ok);
            if (!ok) $fatal(1, "FAIL tb_system_cpu_smoke: UART timeout/framing case=%s", r_label);
            $fdisplay(log_file, "< %02x", value);
        end
    endtask

    task short_command(input [7:0] command, input integer length, input [47:0] expected);
        integer i;
        reg [7:0] value;
        begin
            fork
                send_byte(command);
                begin
                    for (i = 0; i < length; i = i + 1) begin
                        receive_byte(value);
                        check_word(value, (expected >> (8*i)) & 255, "short response byte");
                    end
                end
            join
            #(bfm_bit_ns);
        end
    endtask

    task load_program(input string name, input integer length);
        integer fd, i, j;
        reg [7:0] value;
        string path;
        begin
            r_label = {"load_", name};
            $display("TRACE tb_system_cpu_smoke: %s", r_label);
            path = {r_root, "TP3_FINAL/programs/cpu/", name, ".hex"};
            fd = $fopen(path, "r");
            if (!fd) begin
                path = {name, ".hex"};
                fd = $fopen(path, "r");
            end
            if (!fd) $fatal(1, "FAIL tb_system_cpu_smoke: missing program %s", name);
            $fclose(fd);
            $readmemh(path, r_program);
            before_writes = imem_writes;
            fork
                begin
                    send_byte(8'h4c);
                    send_byte(length[7:0]);
                    send_byte(length[15:8]);
                end
                begin
                    receive_byte(value);
                    check_word(value, 8'h4b, "LOAD first ACK");
                    check_word(dut.w_cpu_reset, 1, "LOAD holds CPU reset");
                end
            join
            #(bfm_bit_ns);
            fork
                begin
                    for (i = 0; i < length; i = i + 1)
                        for (j = 0; j < 4; j = j + 1)
                            send_byte((r_program[i] >> (8*j)) & 255);
                end
                begin
                    receive_byte(value);
                    check_word(value, 8'h4b, "LOAD final ACK");
                end
            join
            #(bfm_bit_ns);
            for (i = length; i < 256; i = i + 1) r_program[i] = 32'h73;
            check_image();
            check_word(imem_writes - before_writes, 256, "LOAD writes program and HALT tail once");
            check_word(observed_cycles, 0, "LOAD clears cycle count");
            check_word(dut.w_cpu_reset, 0, "LOAD releases reset after completion");
            check_word(dut.w_cpu_en, 0, "LOAD leaves CPU paused");
        end
    endtask

    task check_image;
        integer i;
        begin
            for (i = 0; i < 256; i = i + 1)
                check_word(dut.u_imem.r_mem[i], r_program[i], "program image and HALT tail");
        end
    endtask

    task receive_dump(input integer status);
        integer i, cursor, pair_count, fd;
        reg [7:0] value, checksum;
        reg extra_byte;
        real saved_timeout;
        string path;
        begin
            receive_byte(value);
            r_frame[0] = value;
            check_word(value, 8'ha5, "dump header");
            check_word(dut.w_cpu_en, 0, "CPU paused before dump serialization");
            saved_cycles = observed_cycles;
            for (i = 0; i < 563; i = i + 1) r_cpu_snapshot[i] = cpu_word(i);
            for (i = 1; i <= 208; i = i + 1) receive_byte(r_frame[i]);
            dirty_count = frame_word(51);
            if (dirty_count < 0 || dirty_count > 256)
                $fatal(1, "FAIL tb_system_cpu_smoke: invalid memory count %0d", dirty_count);
            frame_length = 210 + 8*dirty_count;
            for (i = 209; i < frame_length; i = i + 1) receive_byte(r_frame[i]);
            checksum = 0;
            for (i = 1; i < frame_length-1; i = i + 1) checksum = checksum + r_frame[i];
            check_word(r_frame[frame_length-1], checksum, "dump checksum");
            check_word(frame_word(0), 32'h100 | status, "version and stop cause");
            check_word(frame_word(1), saved_cycles, "W1 counts enabled non-halted clocks");
            check_word(frame_word(2), r_cpu_snapshot[0], "IF byte PC");
            for (i = 3; i < 51; i = i + 1)
                check_word(frame_word(i), r_cpu_snapshot[i], "serialized registers and latches match frozen CPU");
            check_word(frame_word(45) & ~32'h8783801f, 0, "MEM info absent fields");
            check_word(frame_word(49) & ~32'h8600001f, 0, "WB info absent fields");
            check_word(frame_word(50) & 32'hffffff00, 0, "reserved flags");
            cursor = 52;
            pair_count = 0;
            for (i = 0; i < 256; i = i + 1) begin
                if (r_cpu_snapshot[51+2*i] != 0) begin
                    check_word(frame_word(cursor), i*4, "memory pair byte address in ascending order");
                    check_word(frame_word(cursor+1), r_cpu_snapshot[52+2*i], "memory pair matches dirty CPU word");
                    cursor = cursor + 2;
                    pair_count = pair_count + 1;
                end
            end
            check_word(dirty_count, pair_count, "all and only dirty words serialized");
            check_word(observed_cycles, saved_cycles, "dump does not advance CPU");
            for (i = 0; i < 563; i = i + 1)
                check_word(cpu_word(i), r_cpu_snapshot[i], "CPU stable during complete serial response");
            path = {r_output, "a32_", r_label, ".dump.hex"};
            fd = $fopen(path, "w");
            if (!fd) $fatal(1, "FAIL tb_system_cpu_smoke: cannot save frame %s", path);
            for (i = 0; i < frame_length; i = i + 1) $fdisplay(fd, "%02x", r_frame[i]);
            $fclose(fd);
            $display("TRACE tb_system_cpu_smoke: case=%s cycles=%0d status=%0d bytes=%0d dirty=%0d",
                     r_label, saved_cycles, status, frame_length, dirty_count);
            #(bfm_bit_ns);
            saved_timeout = bfm_timeout_ns;
            bfm_timeout_ns = 12800.0;
            bfm_recv_byte(value, extra_byte);
            bfm_timeout_ns = saved_timeout;
            check_word(extra_byte, 0, "no extra UART bytes after checksum");
        end
    endtask

    task dump_command(input [7:0] command, input string name, input integer status);
        begin
            r_label = name;
            fork
                send_byte(command);
                receive_dump(status);
            join
        end
    endtask

    task check_reset_dump;
        integer i;
        begin
            check_word(frame_word(0), 32'h100, "reset dump status");
            check_word(frame_word(1), 0, "reset dump cycles");
            check_word(frame_word(2), 0, "reset dump IF PC");
            for (i = 3; i < 52; i = i + 1) check_word(frame_word(i), 0, "reset architectural and latch state");
        end
    endtask

    task check_architecture(input integer base);
        integer i;
        begin
            check_word(frame_word(1), r_golden[base+1], "independent program pipeline advances");
            check_word(frame_word(46), r_golden[base], "independent canonical HALT PC");
            check_word(frame_word(50), 32'h98, "HALT WB and drained younger stages");
            for (i = 0; i < 32; i = i + 1)
                check_word(frame_word(3+i), r_golden[base+7+i], "independent final register");
            for (i = 0; i < 256; i = i + 1) begin
                check_word(r_cpu_snapshot[51+2*i], r_golden[base+295+i], "independent final dirty word");
                check_word(r_cpu_snapshot[52+2*i], r_golden[base+39+i], "independent final memory word");
            end
        end
    endtask

    task save_frame;
        integer i;
        begin
            previous_length = frame_length;
            for (i = 0; i < frame_length; i = i + 1) r_previous[i] = r_frame[i];
        end
    endtask

    task same_frame;
        integer i;
        begin
            check_word(frame_length, previous_length, "repeat response length");
            for (i = 0; i < frame_length; i = i + 1)
                check_word(r_frame[i], r_previous[i], "repeat response exact bytes");
        end
    endtask

    task check_no_halt_state;
        integer i;
        begin
            check_word(dut.w_cpu_halted, 0, "infinite loop never asserts HALT");
            check_word(dirty_count, 0, "infinite loop has no stores");
            for (i = 0; i < 32; i = i + 1) check_word(frame_word(3+i), 0, "independent infinite loop registers");
        end
    endtask

    initial begin
        #100000000;
        $fatal(1, "FAIL tb_system_cpu_smoke: watchdog case=%s", r_label);
    end

    initial begin
        r_root = "";
        if ($value$plusargs("ROOT=%s", r_root)) begin end
        if (!$value$plusargs("OUT=%s", r_output))
            r_output = {r_root, "TP3_FINAL/build/"};
        log_file = $fopen({r_output, "a32_uart.bytes.log"}, "w");
        if (!log_file) begin
            r_output = "";
            log_file = $fopen("a32_uart.bytes.log", "w");
        end
        if (!log_file) $fatal(1, "FAIL tb_system_cpu_smoke: cannot open UART log");
        begin : read_golden
            integer fd;
            string path;
            path = {r_root, "TP3_FINAL/programs/cpu/halt_suite.expected.hex"};
            fd = $fopen(path, "r");
            if (!fd) begin path = "halt_suite.expected.hex"; fd = $fopen(path, "r"); end
            if (!fd) $fatal(1, "FAIL tb_system_cpu_smoke: missing golden state");
            $fclose(fd);
            $readmemh(path, r_golden);
        end
        bfm_bit_ns = 640.0;
        bfm_timeout_ns = 2000000.0;
        repeat (10) @(negedge r_clock);
        r_reset = 0;
        repeat (10) @(negedge r_clock);
        r_label = "version";
        short_command(8'h56, 6, 48'h010001000156);
        load_program("branch_load_use", 35);
        dump_command(8'h44, "branch_reset", 0);
        check_reset_dump();
        for (step_index = 1; step_index <= 10; step_index = step_index + 1) begin
            before_enable = enable_edges;
            before_cycles = observed_cycles;
            dump_command(8'h53, $sformatf("step_%0d", step_index), 0);
            check_word(enable_edges-before_enable, 1, "STEP produces one enable clock");
            check_word(observed_cycles-before_cycles, 1, "STEP produces one pipeline advance");
            check_word(frame_word(1), step_index, "STEP accumulates W1");
            if (step_index == 7) begin
                check_word(frame_word(50) & 32'h20, 32'h20, "STEP captures current load-use stall");
                r_seen_stall = 1;
            end
            if (step_index == 9) begin
                check_word(frame_word(50) & 32'h40, 32'h40, "STEP captures current taken branch");
                r_seen_take = 1;
            end
            save_frame();
            before_enable = enable_edges;
            dump_command(8'h44, $sformatf("paused_%0d", step_index), 0);
            same_frame();
            check_word(enable_edges-before_enable, 0, "D never enables CPU");
        end
        dump_command(8'h52, "branch_run", 1);
        check_architecture(560*5);
        save_frame();
        dump_command(8'h44, "branch_halted_dump", 1);
        same_frame();
        before_enable = enable_edges;
        dump_command(8'h53, "branch_halted_step", 1);
        same_frame();
        check_word(enable_edges-before_enable, 1, "STEP still pulses enable on halted CPU");
        before_enable = enable_edges;
        dump_command(8'h52, "branch_halted_run", 1);
        same_frame();
        check_word(enable_edges-before_enable, 0, "RUN on halted CPU does not enable");
        r_label = "reset_command";
        before_reset = reset_edges;
        short_command(8'h58, 1, 48'h4b);
        check_word(reset_edges-before_reset, 1, "X asserts one CPU reset clock");
        check_image();
        dump_command(8'h44, "after_x", 0);
        check_reset_dump();
        dump_command(8'h52, "branch_rerun", 1);
        check_architecture(560*5);
        load_program("suma", 9);
        dump_command(8'h52, "suma_run", 1);
        check_architecture(560*3);
        load_program("no_halt", 1);
        r_label = "abort_run";
        fork
            begin
                send_byte(8'h52);
                repeat (20) @(negedge r_clock);
                send_byte(8'h41);
            end
            receive_dump(4);
        join
        check_no_halt_state();
        check_word(frame_word(1) > 0 && frame_word(1) < RUN_LIMIT, 1, "abort occurs before run timeout");
        save_frame();
        dump_command(8'h44, "abort_dump", 4);
        same_frame();
        r_label = "reset_after_abort";
        short_command(8'h58, 1, 48'h4b);
        check_image();
        dump_command(8'h52, "timeout_run", 2);
        check_no_halt_state();
        check_word(frame_word(1), RUN_LIMIT, "first RUN timeout count");
        dump_command(8'h52, "timeout_again", 2);
        check_no_halt_state();
        check_word(frame_word(1), 2*RUN_LIMIT, "RUN budget separate from cumulative W1");
        dump_command(8'h53, "step_after_timeout", 0);
        check_no_halt_state();
        check_word(frame_word(1), 2*RUN_LIMIT+1, "STEP clears cause and advances after timeout");
        load_program("flush_halt", 7);
        dump_command(8'h52, "recovery_run", 1);
        check_architecture(560*6);
        check_word(r_seen_stall && r_seen_take, 1, "paused hazard and redirect dumps covered");
        check_word(w_leds[2:1], 0, "no framing or overrun errors");
        $fclose(log_file);
        if (errors != 0) $fatal(1, "FAIL tb_system_cpu_smoke: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_system_cpu_smoke: %0d checks, real UART LOAD STEP RUN DUMP RESET ABORT timeout and recovery", checks);
        $finish;
    end
endmodule

`default_nettype wire

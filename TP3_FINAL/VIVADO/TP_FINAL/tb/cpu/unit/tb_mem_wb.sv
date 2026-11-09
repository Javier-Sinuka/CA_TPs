`timescale 1ns/1ps
`default_nettype none

module tb_mem_wb;
    reg r_clock;
    reg r_reset;
    reg r_en;
    reg r_valid_mem;
    reg [31:0] r_pc_mem;
    reg [31:0] r_result_mem;
    reg [31:0] r_store_data_mem;
    reg [4:0] r_rd_mem;
    reg [2:0] r_funct3_mem;
    reg r_mem_read_mem;
    reg r_mem_write_mem;
    reg r_mem_to_reg_mem;
    reg r_reg_write_mem;
    reg r_halt_mem;
    reg [7:0] r_dbg_mem_addr;
    wire w_valid_wb;
    wire [31:0] w_pc_wb;
    wire [31:0] w_result_wb;
    wire [31:0] w_load_data_wb;
    wire [4:0] w_rd_wb;
    wire w_mem_to_reg_wb;
    wire w_reg_write_wb;
    wire w_halt_wb;
    wire [31:0] w_info_wb;
    wire [31:0] w_wb_data, w_dbg_mem_data, w_dbg_reg_data;
    wire w_regfile_we, w_dmem_we, w_dbg_mem_dirty;
    reg [4:0] r_dbg_reg_addr;
    reg [31:0] r_regs [0:31];
    reg [7:0] r_bytes [0:1023];
    reg r_dirty [0:255];
    reg [31:0] r_expected_pc, r_expected_result, r_expected_load;
    reg [4:0] r_expected_rd;
    reg [2:0] r_expected_controls;
    reg r_expected_valid;
    reg r_observed_reg_we, r_observed_store_we;
    reg [31:0] r_seed;
    integer checks, errors, cycles, index;
    integer expected_reg_writes, observed_reg_writes;
    integer expected_stores, observed_stores;

    memory_stage dut (
        .i_clock(r_clock),
        .i_reset(r_reset),
        .i_en(r_en),
        .i_valid_mem(r_valid_mem),
        .i_pc_mem(r_pc_mem),
        .i_result_mem(r_result_mem),
        .i_store_data_mem(r_store_data_mem),
        .i_rd_mem(r_rd_mem),
        .i_funct3_mem(r_funct3_mem),
        .i_mem_read_mem(r_mem_read_mem),
        .i_mem_write_mem(r_mem_write_mem),
        .i_mem_to_reg_mem(r_mem_to_reg_mem),
        .i_reg_write_mem(r_reg_write_mem),
        .i_halt_mem(r_halt_mem),
        .i_dbg_mem_addr(r_dbg_mem_addr),
        .o_valid_wb(w_valid_wb),
        .o_pc_wb(w_pc_wb),
        .o_result_wb(w_result_wb),
        .o_load_data_wb(w_load_data_wb),
        .o_rd_wb(w_rd_wb),
        .o_mem_to_reg_wb(w_mem_to_reg_wb),
        .o_reg_write_wb(w_reg_write_wb),
        .o_halt_wb(w_halt_wb),
        .o_info_wb(w_info_wb),
        .o_wb_data(w_wb_data),
        .o_regfile_we(w_regfile_we),
        .o_dmem_we(w_dmem_we),
        .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty)
    );

    regfile u_regfile (
        .i_clock(r_clock), .i_reset(r_reset), .i_en(r_en),
        .i_reg_write(w_regfile_we), .i_rd(w_rd_wb), .i_wdata(w_wb_data),
        .i_rs1(5'd0), .i_rs2(5'd0), .o_rs1_data(), .o_rs2_data(),
        .i_dbg_addr(r_dbg_reg_addr), .o_dbg_data(w_dbg_reg_data)
    );

    function automatic [31:0] model_word(input [7:0] word_index);
        integer base;
        begin
            base = word_index * 4;
            model_word = r_dirty[word_index] ? {r_bytes[base+3], r_bytes[base+2], r_bytes[base+1], r_bytes[base]} : 32'd0;
        end
    endfunction

    function automatic [31:0] model_load(input [31:0] address, input [2:0] funct3);
        integer base;
        reg [7:0] byte_value;
        reg [15:0] half_value;
        begin
            base = address[9:2] * 4;
            model_load = 32'd0;
            if (r_dirty[address[9:2]]) begin
                byte_value = r_bytes[base + address[1:0]];
                half_value = {r_bytes[base + (address[1] ? 3 : 1)], r_bytes[base + (address[1] ? 2 : 0)]};
                casez (funct3)
                    3'd0: model_load = {{24{byte_value[7]}}, byte_value};
                    3'd1: model_load = {{16{half_value[15]}}, half_value};
                    3'd2: model_load = model_word(address[9:2]);
                    3'd4: model_load = {24'd0, byte_value};
                    3'd5: model_load = {16'd0, half_value};
                    default: begin end
                endcase
            end
        end
    endfunction

    task automatic model_store(input [31:0] address, input [2:0] funct3, input [31:0] data);
        integer base, lane;
        begin
            base = address[9:2] * 4;
            if (funct3 <= 3'd2) begin
                if (!r_dirty[address[9:2]])
                    for (lane = 0; lane < 4; lane = lane + 1)
                        r_bytes[base + lane] = 8'd0;
                casez (funct3)
                    3'd0: r_bytes[base + address[1:0]] = data[7:0];
                    3'd1: begin
                        r_bytes[base + (address[1] ? 2 : 0)] = data[7:0];
                        r_bytes[base + (address[1] ? 3 : 1)] = data[15:8];
                    end
                    3'd2: begin
                        for (lane = 0; lane < 4; lane = lane + 1)
                            r_bytes[base + lane] = data[lane*8 +: 8];
                    end
                    default: begin end
                endcase
                r_dirty[address[9:2]] = 1'b1;
            end
        end
    endtask

    task automatic check_word(input [31:0] got, input [31:0] expected, input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL mem_wb: cycle=%0d %s expected=%08h got=%08h", cycles, label, expected, got);
            end
        end
    endtask

    task automatic check_outputs;
        reg [31:0] info;
        begin
            info = {27'd0, r_expected_rd} | ({31'd0, r_expected_controls[2]} << 25) |
                   ({31'd0, r_expected_controls[1]} << 26) | ({31'd0, r_expected_controls[0]} << 31);
            check_word({31'd0, w_valid_wb}, {31'd0, r_expected_valid}, "valid WB");
            check_word(w_pc_wb, r_expected_pc, "PC WB");
            check_word(w_result_wb, r_expected_result, "result or load address");
            check_word(w_load_data_wb, r_expected_load, "captured load data");
            check_word({27'd0, w_rd_wb}, {27'd0, r_expected_rd}, "rd WB");
            check_word({29'd0, w_mem_to_reg_wb, w_reg_write_wb, w_halt_wb}, {29'd0, r_expected_controls}, "WB controls");
            check_word(w_info_wb, info, "WB info");
            check_word(w_info_wb & 32'h79ff_ffe0, 32'd0, "WB absent fields");
            check_word(w_wb_data, r_expected_controls[2] ? r_expected_load : r_expected_result, "selected WB value");
            check_word(w_dbg_mem_data, model_word(r_dbg_mem_addr), "debug memory");
            check_word({31'd0, w_dbg_mem_dirty}, {31'd0, r_dirty[r_dbg_mem_addr]}, "dirty");
            check_word(w_dbg_reg_data, r_regs[r_dbg_reg_addr], "committed register");
            check_word(observed_reg_writes, expected_reg_writes, "accepted register writes");
            check_word(observed_stores, expected_stores, "accepted physical stores");
        end
    endtask

    task automatic tick;
        begin
            #1;
            check_word({31'd0, w_dmem_we}, {31'd0, (r_en && !r_reset && r_valid_mem && r_mem_write_mem)}, "store enable before edge");
            check_word({31'd0, w_regfile_we}, {31'd0, (r_en && !r_reset && r_expected_valid && r_expected_controls[1] && r_expected_rd != 0)}, "commit enable before edge");
            r_observed_reg_we = w_regfile_we;
            r_observed_store_we = dut.u_dmem.w_we;
            @(posedge r_clock);
            cycles = cycles + 1;
            if (r_reset) begin
                r_expected_pc = 32'd0;
                r_expected_result = 32'd0;
                r_expected_load = 32'd0;
                r_expected_rd = 5'd0;
                r_expected_valid = 1'b0;
                r_expected_controls = 3'd0;
                expected_reg_writes = 0;
                observed_reg_writes = 0;
                expected_stores = 0;
                observed_stores = 0;
                for (index = 0; index < 32; index = index + 1) r_regs[index] = 32'd0;
                for (index = 0; index < 256; index = index + 1) r_dirty[index] = 1'b0;
            end else begin
                if (r_observed_reg_we) observed_reg_writes = observed_reg_writes + 1;
                if (r_observed_store_we) observed_stores = observed_stores + 1;
                if (r_en) begin
                    if (r_expected_valid && r_expected_controls[1] && r_expected_rd != 5'd0) begin
                        r_regs[r_expected_rd] = r_expected_controls[2] ? r_expected_load : r_expected_result;
                        expected_reg_writes = expected_reg_writes + 1;
                    end
                    r_expected_pc = r_pc_mem;
                    r_expected_result = r_result_mem;
                    r_expected_load = (r_valid_mem && r_mem_read_mem) ? model_load(r_result_mem, r_funct3_mem) : 32'd0;
                    r_expected_rd = r_rd_mem;
                    r_expected_valid = r_valid_mem;
                    r_expected_controls = r_valid_mem ? {r_mem_to_reg_mem, r_reg_write_mem, r_halt_mem} : 3'd0;
                    if (r_valid_mem && r_mem_write_mem && r_funct3_mem <= 3'd2) begin
                        model_store(r_result_mem, r_funct3_mem, r_store_data_mem);
                        expected_stores = expected_stores + 1;
                    end
                end
            end
            #1;
            check_outputs();
        end
    endtask

    task automatic drive(input [31:0] address_or_result, input [31:0] data,
                          input [4:0] rd, input [2:0] funct3, input [4:0] controls, input valid);
        begin
            @(negedge r_clock);
            r_pc_mem = r_pc_mem + 32'd4;
            r_result_mem = address_or_result;
            r_store_data_mem = data;
            r_rd_mem = rd;
            r_funct3_mem = funct3;
            {r_mem_read_mem, r_mem_write_mem, r_mem_to_reg_mem, r_reg_write_mem, r_halt_mem} = controls;
            r_valid_mem = valid;
            r_dbg_mem_addr = address_or_result[9:2];
            r_dbg_reg_addr = rd;
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #10 r_clock = ~r_clock;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL tb_mem_wb: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        cycles = 0;
        r_seed = 32'h16ab_cdef;
        r_reset = 1'b1;
        r_en = 1'b0;
        r_valid_mem = 1'b0;
        r_pc_mem = 32'd0;
        r_result_mem = 32'd0;
        r_store_data_mem = 32'd0;
        r_rd_mem = 5'd0;
        r_funct3_mem = 3'd2;
        {r_mem_read_mem, r_mem_write_mem, r_mem_to_reg_mem, r_reg_write_mem, r_halt_mem} = 5'd0;
        r_dbg_mem_addr = 8'd0;
        r_dbg_reg_addr = 5'd0;
        tick();
        @(negedge r_clock);
        r_reset = 1'b0;
        r_en = 1'b1;
        drive(32'h1234_5678, 32'd0, 5'd1, 3'd2, 5'b00010, 1'b1);
        tick();
        drive(32'd0, 32'h89ab_80ff, 5'd0, 3'd2, 5'b01000, 1'b1);
        r_en = 1'b0;
        repeat (100) begin
            tick();
            @(negedge r_clock);
        end
        check_word(expected_reg_writes, 32'd0, "pending WB not committed while paused");
        check_word(expected_stores, 32'd0, "pending store not accepted while paused");
        r_en = 1'b1;
        tick();
        check_word(expected_reg_writes, 32'd1, "one WB after resume");
        check_word(expected_stores, 32'd1, "one store after resume");
        drive(32'd4, 32'hdead_beef, 5'd2, 3'd2, 5'b11111, 1'b0);
        tick();
        check_word(w_dbg_mem_data, 32'd0, "invalid store leaves word clean");
        check_word({31'd0, w_dbg_mem_dirty}, 32'd0, "invalid store leaves dirty clear");
        drive(32'd0, 32'hdead_beef, 5'd2, 3'd2, 5'b11111, 1'b0);
        tick();
        check_word(w_load_data_wb, 32'd0, "invalid load data is normalized");
        check_word(w_dbg_mem_data, 32'h89ab_80ff, "invalid store preserves dirty word");

        drive(32'h00000000, 32'h00000000, 5'd2, 3'd2, 5'b10110, 1'b1);
        tick();
        drive(32'hfedcba98, 32'h00000000, 5'd3, 3'd2, 5'b00010, 1'b1);
        tick();
        drive(32'h00000000, 32'h00000000, 5'd4, 3'd0, 5'b10110, 1'b1);
        tick();
        drive(32'h00000000, 32'h00000000, 5'd5, 3'd4, 5'b10110, 1'b1);
        tick();
        drive(32'h00000001, 32'h00000000, 5'd6, 3'd1, 5'b10110, 1'b1);
        tick();
        drive(32'h00000001, 32'h00000000, 5'd7, 3'd5, 5'b10110, 1'b1);
        tick();
        drive(32'h00000005, 32'h000000aa, 5'd0, 3'd0, 5'b01000, 1'b1);
        tick();
        drive(32'h00000007, 32'h0000beef, 5'd0, 3'd1, 5'b01000, 1'b1);
        tick();
        drive(32'h00000404, 32'h00000000, 5'd8, 3'd2, 5'b10110, 1'b1);
        tick();
        drive(32'h00000008, 32'h00000000, 5'd0, 3'd2, 5'b01000, 1'b1);
        tick();
        drive(32'hffffffff, 32'h00000000, 5'd0, 3'd2, 5'b00010, 1'b1);
        tick();
        drive(32'h0000000c, 32'hffffffff, 5'd0, 3'd7, 5'b01000, 1'b1);
        tick();
        drive(32'h99009900, 32'h00000000, 5'd9, 3'd2, 5'b00010, 1'b1);
        tick();
        drive(32'd12, 32'hffff_ffff, 5'd10, 3'd2, 5'b11111, 1'b1);
        r_reset = 1'b1;
        r_en = 1'b0;
        tick();
        check_word(w_dbg_mem_data, 32'd0, "reset cancels pending store");
        check_word(w_dbg_reg_data, 32'd0, "reset cancels pending register write");
        drive(32'd12, 32'hffff_ffff, 5'd10, 3'd2, 5'b11111, 1'b1);
        r_en = 1'b1;
        tick();
        check_word(w_dbg_mem_data, 32'd0, "enabled reset blocks store");
        drive(32'd1, 32'h0000_0022, 5'd0, 3'd0, 5'b01000, 1'b1);
        r_reset = 1'b0;
        r_en = 1'b1;
        tick();
        check_word(w_dbg_mem_data, 32'h0000_2200, "partial store after reset starts from zero");
        drive(32'd0, 32'd0, 5'd10, 3'd2, 5'b10110, 1'b1);
        tick();
        check_word(w_wb_data, 32'h0000_2200, "load selects data not address");
        drive(32'd0, 32'd0, 5'd0, 3'd2, 5'd0, 1'b0);
        tick();
        for (index = 0; index < 128; index = index + 1) begin
            @(negedge r_clock);
            r_seed = r_seed * 32'd1664525 + 32'd1013904223;
            r_en = r_seed[31];
            r_valid_mem = r_seed[30];
            r_result_mem = {22'd0, r_seed[9:0]};
            r_store_data_mem = r_seed ^ 32'h55aa_33cc;
            r_rd_mem = r_seed[14:10];
            r_funct3_mem = r_seed[17:15];
            {r_mem_read_mem, r_mem_write_mem, r_mem_to_reg_mem, r_reg_write_mem, r_halt_mem} = r_seed[22:18];
            r_pc_mem = r_seed;
            r_dbg_mem_addr = r_result_mem[9:2];
            r_dbg_reg_addr = r_rd_mem;
            tick();
        end
        drive(32'd0, 32'd0, 5'd0, 3'd2, 5'd0, 1'b0);
        r_en = 1'b1;
        tick();
        @(negedge r_clock);
        r_en = 1'b0;
        for (index = 0; index < 32; index = index + 1) begin
            r_dbg_reg_addr = index[4:0];
            #1;
            check_word(w_dbg_reg_data, r_regs[index], "register sweep");
        end
        for (index = 0; index < 256; index = index + 1) begin
            r_dbg_mem_addr = index[7:0];
            #1;
            check_word(w_dbg_mem_data, model_word(index[7:0]), "memory sweep");
            check_word({31'd0, w_dbg_mem_dirty}, {31'd0, r_dirty[index]}, "dirty sweep");
        end
        check_outputs();
        if (errors != 0)
            $fatal(1, "FAIL tb_mem_wb: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_mem_wb: %0d checks, seed=16abcdef", checks);
        $finish;
    end
endmodule

`default_nettype wire

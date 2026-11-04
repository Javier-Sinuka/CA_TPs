`timescale 1ns/1ps
`default_nettype none

module tb_dmem;
    reg r_clock;
    reg r_reset;
    reg r_en;
    reg r_we;
    reg [31:0] r_addr;
    reg [31:0] r_store_data;
    reg [2:0] r_funct3;
    reg [7:0] r_dbg_addr;
    wire [31:0] w_load_data;
    wire [31:0] w_dbg_data;
    wire w_dbg_dirty;
    reg [7:0] r_model_bytes [0:1023];
    reg r_model_dirty [0:255];
    reg [31:0] r_seed;
    reg [31:0] r_random_addr;
    reg [31:0] r_random_data;
    reg [2:0] r_random_kind;
    integer checks;
    integer errors;
    integer index;
    integer offset;

    dmem dut (
        .i_clock(r_clock),
        .i_reset(r_reset),
        .i_en(r_en),
        .i_we(r_we),
        .i_addr(r_addr),
        .i_store_data(r_store_data),
        .i_funct3(r_funct3),
        .o_load_data(w_load_data),
        .i_dbg_addr(r_dbg_addr),
        .o_dbg_data(w_dbg_data),
        .o_dbg_dirty(w_dbg_dirty)
    );

    function automatic [31:0] model_word(input [7:0] word_index);
        integer base;
        begin
            base = word_index * 4;
            if (!r_model_dirty[word_index])
                model_word = 32'd0;
            else
                model_word = {r_model_bytes[base + 3], r_model_bytes[base + 2],
                              r_model_bytes[base + 1], r_model_bytes[base]};
        end
    endfunction

    function automatic [31:0] model_load(input [31:0] addr, input [2:0] funct3);
        integer base;
        reg [7:0] byte_value;
        reg [15:0] half_value;
        begin
            base = addr[9:2] * 4;
            model_load = 32'd0;
            if (r_model_dirty[addr[9:2]]) begin
                byte_value = r_model_bytes[base + addr[1:0]];
                half_value = {r_model_bytes[base + (addr[1] ? 3 : 1)],
                              r_model_bytes[base + (addr[1] ? 2 : 0)]};
                case (funct3)
                    3'b000: model_load = {{24{byte_value[7]}}, byte_value};
                    3'b001: model_load = {{16{half_value[15]}}, half_value};
                    3'b010: model_load = model_word(addr[9:2]);
                    3'b100: model_load = {24'd0, byte_value};
                    3'b101: model_load = {16'd0, half_value};
                    default: model_load = 32'd0;
                endcase
            end
        end
    endfunction

    task automatic model_store(input [31:0] addr, input [2:0] funct3,
                               input [31:0] data);
        integer base;
        begin
            base = addr[9:2] * 4;
            if (!r_model_dirty[addr[9:2]]) begin
                r_model_bytes[base] = 8'd0;
                r_model_bytes[base + 1] = 8'd0;
                r_model_bytes[base + 2] = 8'd0;
                r_model_bytes[base + 3] = 8'd0;
            end
            case (funct3)
                3'b000: begin
                    r_model_bytes[base + addr[1:0]] = data[7:0];
                    r_model_dirty[addr[9:2]] = 1'b1;
                end
                3'b001: begin
                    r_model_bytes[base + (addr[1] ? 2 : 0)] = data[7:0];
                    r_model_bytes[base + (addr[1] ? 3 : 1)] = data[15:8];
                    r_model_dirty[addr[9:2]] = 1'b1;
                end
                3'b010: begin
                    r_model_bytes[base] = data[7:0];
                    r_model_bytes[base + 1] = data[15:8];
                    r_model_bytes[base + 2] = data[23:16];
                    r_model_bytes[base + 3] = data[31:24];
                    r_model_dirty[addr[9:2]] = 1'b1;
                end
                default: begin end
            endcase
        end
    endtask

    task automatic check_word(input [31:0] got, input [31:0] expected,
                              input [127:0] label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL dmem: %0s check=%0d addr=%08h f3=%b expected=%08h got=%08h",
                         label, checks, r_addr, r_funct3, expected, got);
            end
        end
    endtask

    task automatic check_load(input [31:0] addr, input [2:0] funct3);
        begin
            r_addr = addr;
            r_funct3 = funct3;
            #1;
            check_word(w_load_data, model_load(addr, funct3), "model load");
        end
    endtask

    task automatic check_debug(input [7:0] word_index);
        begin
            r_dbg_addr = word_index;
            #1;
            check_word(w_dbg_data, model_word(word_index), "model debug");
            check_word({31'd0, w_dbg_dirty}, {31'd0, r_model_dirty[word_index]},
                       "model dirty");
        end
    endtask

    task automatic write_word(input [31:0] addr, input [2:0] funct3,
                              input [31:0] data, input enable, input write_request);
        begin
            @(negedge r_clock);
            r_addr = addr;
            r_funct3 = funct3;
            r_store_data = data;
            r_en = enable;
            r_we = write_request;
            @(posedge r_clock);
            #1;
            if (enable && write_request)
                model_store(addr, funct3, data);
            r_we = 1'b0;
            check_debug(addr[9:2]);
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #5 r_clock = ~r_clock;
    end

    initial begin
        #200000;
        $fatal(1, "FAIL tb_dmem: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        r_reset = 1'b1;
        r_en = 1'b0;
        r_we = 1'b0;
        r_addr = 32'd0;
        r_store_data = 32'd0;
        r_funct3 = 3'b010;
        r_dbg_addr = 8'd0;
        r_seed = 32'h5eed_0923;
        for (index = 0; index < 1024; index = index + 1)
            r_model_bytes[index] = 8'd0;
        for (index = 0; index < 256; index = index + 1)
            r_model_dirty[index] = 1'b0;

        @(posedge r_clock);
        #1;
        check_load(32'd0, 3'b010);
        check_debug(8'd0);
        @(negedge r_clock);
        r_reset = 1'b0;

        write_word(32'd0, 3'b010, 32'h1122_3344, 1'b1, 1'b1);
        for (offset = 0; offset < 4; offset = offset + 1) begin
            check_load(offset, 3'b000);
            check_load(offset, 3'b100);
        end
        check_load(32'd3, 3'b010);
        check_load(32'd1024, 3'b010);
        check_load(32'd1, 3'b101);
        check_word(w_load_data, 32'h0000_3344, "unaligned LHU low");
        check_load(32'd3, 3'b101);
        check_word(w_load_data, 32'h0000_1122, "unaligned LHU high");

        write_word(32'd3, 3'b010, 32'h1122_3344, 1'b1, 1'b1);
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'h1122_3344, "unaligned SW ignores offset");
        for (offset = 0; offset < 4; offset = offset + 1)
            write_word(32'd80 + offset, 3'b000, 32'h0000_00a0 + offset,
                       1'b1, 1'b1);
        check_load(32'd80, 3'b010);
        check_word(w_load_data, 32'ha3a2_a1a0, "all SB lanes");

        write_word(32'd1, 3'b000, 32'h0000_00aa, 1'b1, 1'b1);
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'h1122_aa44, "SB keeps neighbors");
        write_word(32'd0, 3'b010, 32'h1122_3344, 1'b1, 1'b1);
        write_word(32'd3, 3'b001, 32'h0000_beef, 1'b1, 1'b1);
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'hbeef_3344, "SH high no crossing");
        write_word(32'd0, 3'b001, 32'h0000_cafe, 1'b1, 1'b1);
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'hbeef_cafe, "SH low");

        write_word(32'd12, 3'b010, 32'h8000_0080, 1'b1, 1'b1);
        check_load(32'd12, 3'b000);
        check_word(w_load_data, 32'hffff_ff80, "LB sign");
        check_load(32'd12, 3'b100);
        check_word(w_load_data, 32'h0000_0080, "LBU zero");
        check_load(32'd15, 3'b001);
        check_word(w_load_data, 32'hffff_8000, "LH sign unaligned");
        check_load(32'd15, 3'b101);
        check_word(w_load_data, 32'h0000_8000, "LHU zero unaligned");

        write_word(32'd1020, 3'b010, 32'h89ab_cdef, 1'b1, 1'b1);
        write_word(32'd1023, 3'b001, 32'h0000_1234, 1'b1, 1'b1);
        check_load(32'd1020, 3'b010);
        check_word(w_load_data, 32'h1234_cdef, "word 255 no crossing");
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'hbeef_cafe, "word 0 unchanged");
        write_word(32'h8000_0401, 3'b000, 32'h0000_00aa, 1'b1, 1'b1);
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'hbeef_aafe, "high address wrap");

        write_word(32'd0, 3'b000, 32'h0000_00ff, 1'b0, 1'b1);
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'hbeef_aafe, "pause blocks store");
        write_word(32'd0, 3'b000, 32'h0000_00ff, 1'b1, 1'b0);
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'hbeef_aafe, "write request blocks store");
        write_word(32'd0, 3'b111, 32'hffff_ffff, 1'b1, 1'b1);
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'hbeef_aafe, "invalid store size");
        check_load(32'd0, 3'b111);
        check_word(w_load_data, 32'd0, "invalid load size");

        for (index = 0; index < 128; index = index + 1) begin
            r_seed = r_seed * 32'd1664525 + 32'd1013904223;
            r_random_addr = r_seed;
            r_seed = r_seed * 32'd1664525 + 32'd1013904223;
            r_random_data = r_seed;
            r_random_kind = index % 3;
            write_word(r_random_addr, r_random_kind, r_random_data, 1'b1, 1'b1);
            for (offset = 0; offset < 4; offset = offset + 1) begin
                check_load((r_random_addr & 32'hffff_fffc) | offset, 3'b000);
                check_load((r_random_addr & 32'hffff_fffc) | offset, 3'b001);
                check_load((r_random_addr & 32'hffff_fffc) | offset, 3'b010);
                check_load((r_random_addr & 32'hffff_fffc) | offset, 3'b100);
                check_load((r_random_addr & 32'hffff_fffc) | offset, 3'b101);
            end
        end

        @(negedge r_clock);
        r_reset = 1'b1;
        r_en = 1'b1;
        r_we = 1'b1;
        r_addr = 32'd0;
        r_funct3 = 3'b010;
        r_store_data = 32'hffff_ffff;
        @(posedge r_clock);
        #1;
        for (index = 0; index < 256; index = index + 1)
            r_model_dirty[index] = 1'b0;
        r_we = 1'b0;
        check_load(32'd0, 3'b010);
        check_debug(8'd0);
        check_debug(8'd255);
        @(negedge r_clock);
        r_reset = 1'b0;
        write_word(32'd1025, 3'b000, 32'h0000_00aa, 1'b1, 1'b1);
        check_load(32'd0, 3'b010);
        check_word(w_load_data, 32'h0000_aa00, "partial store on clean word");

        if (errors != 0)
            $fatal(1, "FAIL tb_dmem: %0d errors in %0d checks", errors, checks);
        else begin
            $display("PASS tb_dmem: %0d checks", checks);
            $finish;
        end
    end
endmodule

`default_nettype wire

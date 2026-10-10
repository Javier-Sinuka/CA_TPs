`timescale 1ns/1ps

module tb_dmem;
    reg r_clk = 1'b0;
    reg r_rst = 1'b0;
    reg r_run_start = 1'b0;
    reg [31:0] r_cpu_addr = 32'd0;
    reg [31:0] r_cpu_write_data = 32'd0;
    reg [2:0] r_cpu_funct3 = 3'b010;
    reg r_cpu_read_en = 1'b0;
    reg r_cpu_write_en = 1'b0;
    reg [31:0] r_dbg_addr = 32'd0;
    reg r_dbg_write_en = 1'b0;
    reg [31:0] r_dbg_write_data = 32'd0;
    wire [31:0] w_cpu_read_data;
    wire w_cpu_error;
    wire [31:0] w_dbg_data;
    wire w_dbg_touched;
    wire w_dbg_dirty;
    wire w_dbg_error;
    integer r_checks = 0;

    dmem #(.WORDS(8)) dut (
        .i_clk(r_clk), .i_rst(r_rst), .i_run_start(r_run_start),
        .i_cpu_addr(r_cpu_addr), .i_cpu_write_data(r_cpu_write_data),
        .i_cpu_funct3(r_cpu_funct3), .i_cpu_read_en(r_cpu_read_en),
        .i_cpu_write_en(r_cpu_write_en), .o_cpu_read_data(w_cpu_read_data),
        .o_cpu_error(w_cpu_error), .i_dbg_addr(r_dbg_addr),
        .i_dbg_write_en(r_dbg_write_en), .i_dbg_write_data(r_dbg_write_data),
        .o_dbg_data(w_dbg_data), .o_dbg_touched(w_dbg_touched),
        .o_dbg_dirty(w_dbg_dirty), .o_dbg_error(w_dbg_error)
    );

    task tick;
        begin
            #2 r_clk = 1'b1;
            #2 r_clk = 1'b0;
        end
    endtask

    task check_debug;
        input [31:0] addr, expected_data;
        input expected_touched, expected_dirty, expected_error;
        begin
            r_dbg_addr = addr;
            #1;
            if (w_dbg_data !== expected_data || w_dbg_touched !== expected_touched ||
                w_dbg_dirty !== expected_dirty || w_dbg_error !== expected_error)
                $fatal(1, "dmem debug addr=%h expected=%h/%b/%b/%b got=%h/%b/%b/%b",
                       addr, expected_data, expected_touched, expected_dirty, expected_error,
                       w_dbg_data, w_dbg_touched, w_dbg_dirty, w_dbg_error);
            r_checks = r_checks + 1;
        end
    endtask

    task debug_write;
        input [31:0] addr, data;
        begin
            r_dbg_addr = addr;
            r_dbg_write_data = data;
            r_dbg_write_en = 1'b1;
            tick();
            r_dbg_write_en = 1'b0;
        end
    endtask

    task store;
        input [31:0] addr, data;
        input [2:0] funct3;
        input expected_error;
        begin
            r_cpu_addr = addr;
            r_cpu_write_data = data;
            r_cpu_funct3 = funct3;
            r_cpu_write_en = 1'b1;
            #1;
            if (w_cpu_error !== expected_error) $fatal(1, "dmem store error addr=%h", addr);
            tick();
            r_cpu_write_en = 1'b0;
        end
    endtask

    task load;
        input [31:0] addr, expected_data;
        input [2:0] funct3;
        input expected_error;
        begin
            r_cpu_addr = addr;
            r_cpu_funct3 = funct3;
            r_cpu_read_en = 1'b1;
            #1;
            if (w_cpu_error !== expected_error || w_cpu_read_data !== expected_data)
                $fatal(1, "dmem load addr=%h funct3=%b expected=%h/%b got=%h/%b",
                       addr, funct3, expected_data, expected_error, w_cpu_read_data, w_cpu_error);
            tick();
            r_cpu_read_en = 1'b0;
            r_checks = r_checks + 1;
        end
    endtask

    initial begin
        r_rst = 1'b1;
        tick();
        r_rst = 1'b0;
        debug_write(32'd0, 32'd0);
        debug_write(32'd4, 32'd0);
        debug_write(32'd12, 32'd0);
        debug_write(32'd28, 32'd0);
        check_debug(32'd0, 32'd0, 1'b0, 1'b0, 1'b0);

        store(32'd0, 32'h80, 3'b000, 1'b0);
        store(32'd1, 32'h80, 3'b000, 1'b0);
        store(32'd2, 32'h80, 3'b000, 1'b0);
        store(32'd3, 32'h80, 3'b000, 1'b0);
        check_debug(32'd0, 32'h8080_8080, 1'b1, 1'b1, 1'b0);
        load(32'd2, 32'hffff_ff80, 3'b000, 1'b0);
        load(32'd2, 32'h0000_0080, 3'b100, 1'b0);
        load(32'd0, 32'h8080_8080, 3'b010, 1'b0);

        store(32'd4, 32'h0000_80ff, 3'b001, 1'b0);
        store(32'd6, 32'h0000_7f01, 3'b001, 1'b0);
        check_debug(32'd4, 32'h7f01_80ff, 1'b1, 1'b1, 1'b0);
        load(32'd4, 32'hffff_80ff, 3'b001, 1'b0);
        load(32'd4, 32'h0000_80ff, 3'b101, 1'b0);
        load(32'd6, 32'h0000_7f01, 3'b001, 1'b0);

        store(32'd12, 32'h1234_5678, 3'b010, 1'b0);
        check_debug(32'd12, 32'h1234_5678, 1'b1, 1'b1, 1'b0);
        load(32'd12, 32'h1234_5678, 3'b010, 1'b0);

        store(32'd1, 32'hffff_ffff, 3'b001, 1'b1);
        store(32'd2, 32'hffff_ffff, 3'b010, 1'b1);
        store(32'd32, 32'hffff_ffff, 3'b010, 1'b1);
        store(32'h4000_0000, 32'hffff_ffff, 3'b010, 1'b1);
        store(32'd0, 32'hffff_ffff, 3'b100, 1'b1);
        check_debug(32'd0, 32'h8080_8080, 1'b1, 1'b1, 1'b0);
        load(32'd1, 32'd0, 3'b010, 1'b1);
        load(32'd32, 32'd0, 3'b000, 1'b1);
        load(32'd0, 32'd0, 3'b111, 1'b1);
        check_debug(32'd1, 32'd0, 1'b0, 1'b0, 1'b1);
        check_debug(32'd32, 32'd0, 1'b0, 1'b0, 1'b1);

        load(32'd28, 32'd0, 3'b010, 1'b0);
        check_debug(32'd28, 32'd0, 1'b1, 1'b0, 1'b0);

        r_run_start = 1'b1;
        tick();
        r_run_start = 1'b0;
        check_debug(32'd0, 32'h8080_8080, 1'b0, 1'b0, 1'b0);
        check_debug(32'd28, 32'd0, 1'b0, 1'b0, 1'b0);

        debug_write(32'd0, 32'd0);
        debug_write(32'd4, 32'd0);
        debug_write(32'd12, 32'd0);
        check_debug(32'd0, 32'd0, 1'b0, 1'b0, 1'b0);
        check_debug(32'd4, 32'd0, 1'b0, 1'b0, 1'b0);

        r_dbg_addr = 32'd0;
        r_dbg_write_data = 32'h7654_3210;
        r_dbg_write_en = 1'b1;
        r_cpu_addr = 32'd0;
        r_cpu_write_data = 32'hffff_ffff;
        r_cpu_funct3 = 3'b010;
        r_cpu_write_en = 1'b1;
        #1;
        if (w_cpu_error !== 1'b1) $fatal(1, "dmem did not reject simultaneous CPU and debug write");
        tick();
        r_dbg_write_en = 1'b0;
        r_cpu_write_en = 1'b0;
        check_debug(32'd0, 32'h7654_3210, 1'b0, 1'b0, 1'b0);

        $display("tb_dmem passed: %0d checks", r_checks);
        $finish;
    end
endmodule

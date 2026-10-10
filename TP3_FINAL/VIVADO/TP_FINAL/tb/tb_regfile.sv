`timescale 1ns/1ps

module tb_regfile;
    reg r_clk = 1'b0;
    reg r_rst = 1'b0;
    reg r_write_en = 1'b0;
    reg [4:0] r_write_addr = 5'd0;
    reg [31:0] r_write_data = 32'd0;
    reg [4:0] r_read_addr_a = 5'd0;
    reg [4:0] r_read_addr_b = 5'd0;
    reg [4:0] r_dbg_addr = 5'd0;
    wire [31:0] w_read_data_a;
    wire [31:0] w_read_data_b;
    wire [31:0] w_dbg_data;
    integer r_checks = 0;

    regfile dut (
        .i_clk(r_clk), .i_rst(r_rst),
        .i_write_en(r_write_en), .i_write_addr(r_write_addr), .i_write_data(r_write_data),
        .i_read_addr_a(r_read_addr_a), .i_read_addr_b(r_read_addr_b), .i_dbg_addr(r_dbg_addr),
        .o_read_data_a(w_read_data_a), .o_read_data_b(w_read_data_b), .o_dbg_data(w_dbg_data)
    );

    task tick;
        begin
            #2 r_clk = 1'b1;
            #2 r_clk = 1'b0;
        end
    endtask

    task check;
        input [31:0] expected_a, expected_b, expected_dbg;
        begin
            #1;
            if (w_read_data_a !== expected_a || w_read_data_b !== expected_b || w_dbg_data !== expected_dbg)
                $fatal(1, "regfile expected %h %h %h got %h %h %h",
                       expected_a, expected_b, expected_dbg, w_read_data_a, w_read_data_b, w_dbg_data);
            r_checks = r_checks + 1;
        end
    endtask

    initial begin
        r_rst = 1'b1;
        tick();
        r_rst = 1'b0;
        r_read_addr_a = 5'd5;
        r_read_addr_b = 5'd6;
        r_dbg_addr = 5'd5;
        check(32'd0, 32'd0, 32'd0);

        r_write_en = 1'b1;
        r_write_addr = 5'd5;
        r_write_data = 32'h1234_5678;
        check(32'h1234_5678, 32'd0, 32'd0);
        tick();
        r_write_en = 1'b0;
        check(32'h1234_5678, 32'd0, 32'h1234_5678);

        r_write_en = 1'b1;
        r_write_addr = 5'd6;
        r_write_data = 32'hffff_ff80;
        check(32'h1234_5678, 32'hffff_ff80, 32'h1234_5678);
        tick();
        r_write_en = 1'b0;
        r_read_addr_a = 5'd6;
        r_dbg_addr = 5'd6;
        check(32'hffff_ff80, 32'hffff_ff80, 32'hffff_ff80);

        r_write_en = 1'b1;
        r_write_addr = 5'd0;
        r_write_data = 32'hdead_beef;
        r_read_addr_a = 5'd0;
        r_dbg_addr = 5'd0;
        check(32'd0, 32'hffff_ff80, 32'd0);
        tick();
        r_write_en = 1'b0;
        check(32'd0, 32'hffff_ff80, 32'd0);

        r_rst = 1'b1;
        r_write_en = 1'b1;
        r_write_addr = 5'd6;
        r_write_data = 32'hdead_beef;
        r_read_addr_a = 5'd6;
        tick();
        r_rst = 1'b0;
        r_write_en = 1'b0;
        r_dbg_addr = 5'd6;
        check(32'd0, 32'd0, 32'd0);

        $display("tb_regfile passed: %0d checks", r_checks);
        $finish;
    end
endmodule

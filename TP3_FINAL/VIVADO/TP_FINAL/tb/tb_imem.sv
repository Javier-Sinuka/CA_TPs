`timescale 1ns/1ps

module tb_imem;
    reg r_clk = 1'b0;
    reg r_rst = 1'b0;
    reg [31:0] r_fetch_addr = 32'd0;
    reg r_load_start = 1'b0;
    reg r_load_write = 1'b0;
    reg [31:0] r_load_addr = 32'd0;
    reg [31:0] r_load_data = 32'd0;
    reg r_load_commit = 1'b0;
    wire [31:0] w_fetch_data;
    wire w_fetch_error;
    wire w_program_valid;
    wire w_load_error;
    wire [31:0] w_program_words;
    integer r_checks = 0;

    imem #(.WORDS(4)) dut (
        .i_clk(r_clk), .i_rst(r_rst), .i_fetch_addr(r_fetch_addr),
        .o_fetch_data(w_fetch_data), .o_fetch_error(w_fetch_error),
        .i_load_start(r_load_start), .i_load_write(r_load_write),
        .i_load_addr(r_load_addr), .i_load_data(r_load_data),
        .i_load_commit(r_load_commit), .o_program_valid(w_program_valid),
        .o_load_error(w_load_error), .o_program_words(w_program_words)
    );

    task tick;
        begin
            #2 r_clk = 1'b1;
            #2 r_clk = 1'b0;
        end
    endtask

    task start_load;
        begin
            r_load_start = 1'b1;
            tick();
            r_load_start = 1'b0;
        end
    endtask

    task write_word;
        input [31:0] addr, data;
        begin
            r_load_addr = addr;
            r_load_data = data;
            r_load_write = 1'b1;
            tick();
            r_load_write = 1'b0;
        end
    endtask

    task commit_load;
        begin
            r_load_commit = 1'b1;
            tick();
            r_load_commit = 1'b0;
        end
    endtask

    task check_fetch;
        input [31:0] addr, expected_data;
        input expected_error;
        begin
            r_fetch_addr = addr;
            #1;
            if (w_fetch_data !== expected_data || w_fetch_error !== expected_error)
                $fatal(1, "imem fetch addr=%h expected=%h/%b got=%h/%b",
                       addr, expected_data, expected_error, w_fetch_data, w_fetch_error);
            r_checks = r_checks + 1;
        end
    endtask

    initial begin
        r_rst = 1'b1;
        tick();
        r_rst = 1'b0;
        check_fetch(32'd0, 32'd0, 1'b1);

        start_load();
        write_word(32'd0, 32'h0050_0093);
        write_word(32'd4, 32'h0000_0073);
        if (w_program_words !== 32'd2 || w_program_valid !== 1'b0) $fatal(1, "imem loading state");
        commit_load();
        if (w_program_valid !== 1'b1 || w_load_error !== 1'b0) $fatal(1, "imem commit failed");
        check_fetch(32'd0, 32'h0050_0093, 1'b0);
        check_fetch(32'd4, 32'h0000_0073, 1'b0);
        check_fetch(32'd8, 32'd0, 1'b1);
        check_fetch(32'd1, 32'd0, 1'b1);
        check_fetch(32'd16, 32'd0, 1'b1);
        check_fetch(32'h4000_0000, 32'd0, 1'b1);

        start_load();
        check_fetch(32'd0, 32'd0, 1'b1);
        write_word(32'd0, 32'h0000_0073);
        commit_load();
        check_fetch(32'd0, 32'h0000_0073, 1'b0);
        check_fetch(32'd4, 32'd0, 1'b1);

        start_load();
        write_word(32'd4, 32'hdead_beef);
        commit_load();
        if (w_program_valid !== 1'b0 || w_load_error !== 1'b1) $fatal(1, "imem accepted skipped word");
        check_fetch(32'd0, 32'd0, 1'b1);

        start_load();
        write_word(32'd0, 32'h1234_5678);
        write_word(32'd5, 32'hbad0_0000);
        commit_load();
        if (w_program_valid !== 1'b0 || w_load_error !== 1'b1) $fatal(1, "imem accepted unaligned write");

        start_load();
        commit_load();
        if (w_program_valid !== 1'b0 || w_load_error !== 1'b1) $fatal(1, "imem accepted empty program");

        start_load();
        write_word(32'd0, 32'd1);
        write_word(32'd4, 32'd2);
        write_word(32'd8, 32'd3);
        write_word(32'd12, 32'd4);
        commit_load();
        if (w_program_words !== 32'd4 || !w_program_valid) $fatal(1, "imem last word failed");
        check_fetch(32'd12, 32'd4, 1'b0);

        start_load();
        write_word(32'd0, 32'd1);
        write_word(32'd4, 32'd2);
        write_word(32'd8, 32'd3);
        write_word(32'd12, 32'd4);
        write_word(32'd16, 32'd5);
        commit_load();
        if (w_program_valid !== 1'b0 || w_load_error !== 1'b1) $fatal(1, "imem accepted oversized program");

        start_load();
        write_word(32'd0, 32'h0000_0073);
        r_load_addr = 32'd4;
        r_load_data = 32'hdead_beef;
        r_load_write = 1'b1;
        r_load_commit = 1'b1;
        tick();
        r_load_write = 1'b0;
        r_load_commit = 1'b0;
        if (w_program_valid !== 1'b0 || w_load_error !== 1'b1) $fatal(1, "imem accepted simultaneous write and commit");

        $display("tb_imem passed: %0d fetch checks", r_checks);
        $finish;
    end
endmodule

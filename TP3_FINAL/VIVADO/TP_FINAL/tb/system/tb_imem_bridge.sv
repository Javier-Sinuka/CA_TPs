`timescale 1ns/1ps
`default_nettype none

module tb_imem_bridge;
    reg r_clock;
    reg r_reset;
    reg r_en;
    reg r_imem_we;
    reg [7:0] r_imem_waddr;
    reg [31:0] r_imem_wdata;
    reg r_use_manual_addr;
    reg [31:0] r_manual_addr;
    wire [31:0] w_cpu_addr;
    wire [31:0] w_cpu_pc;
    wire [31:0] w_read_addr;
    wire [31:0] w_imem_data;
    wire [31:0] w_dbg_reg_data;
    wire [31:0] w_dbg_latch_word;
    wire w_halted;
    wire [31:0] w_dbg_mem_data;
    wire w_dbg_mem_dirty;
    integer checks;
    integer errors;
    integer index;
    reg [31:0] r_reg_snapshot;
    reg [31:0] r_latch_snapshot;

    assign w_read_addr = r_use_manual_addr ? r_manual_addr : w_cpu_addr;

    cpu_stub #(.HALT_AT(0)) u_cpu (
        .i_clock(r_clock),
        .i_reset(r_reset),
        .i_en(r_en),
        .o_halted(w_halted),
        .o_imem_addr(w_cpu_addr),
        .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(5'd1),
        .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(4'd0),
        .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(8'd0),
        .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty),
        .o_dbg_pc(w_cpu_pc)
    );

    imem u_imem (
        .i_clock(r_clock),
        .i_raddr(w_read_addr[9:2]),
        .o_rdata(w_imem_data),
        .i_we(r_imem_we),
        .i_waddr(r_imem_waddr),
        .i_wdata(r_imem_wdata)
    );

    task automatic check_word;
        input [31:0] got;
        input [31:0] expected;
        input [127:0] label;
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL imem_bridge: %0s check=%0d expected=%08h got=%08h",
                         label, checks, expected, got);
            end
        end
    endtask

    task automatic write_word;
        input [7:0] addr;
        input [31:0] data;
        begin
            @(negedge r_clock);
            r_imem_we = 1'b1;
            r_imem_waddr = addr;
            r_imem_wdata = data;
            @(posedge r_clock);
            #1;
            r_imem_we = 1'b0;
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #5 r_clock = ~r_clock;
    end

    initial begin
        #100000;
        $fatal(1, "FAIL tb_imem_bridge: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        r_reset = 1'b1;
        r_en = 1'b0;
        r_imem_we = 1'b0;
        r_imem_waddr = 8'd0;
        r_imem_wdata = 32'd0;
        r_use_manual_addr = 1'b1;
        r_manual_addr = 32'd0;

        @(posedge r_clock);
        #1;
        for (index = 0; index < 256; index = index + 1) begin
            r_manual_addr = index << 2;
            #1;
            check_word(w_imem_data, 32'h0000_0073, "initial HALT");
        end

        write_word(8'd0, 32'h0050_0093);
        write_word(8'd1, 32'h0010_0113);
        write_word(8'd255, 32'hdead_beef);
        r_manual_addr = 32'd0;
        #1;
        check_word(w_imem_data, 32'h0050_0093, "PC 0");
        r_manual_addr = 32'd4;
        #1;
        check_word(w_imem_data, 32'h0010_0113, "PC 4");
        r_manual_addr = 32'd1020;
        #1;
        check_word(w_imem_data, 32'hdead_beef, "PC 1020");
        r_manual_addr = 32'd1024;
        #1;
        check_word(w_imem_data, 32'h0050_0093, "PC 1024 wrap");
        r_manual_addr = 32'd1028;
        #1;
        check_word(w_imem_data, 32'h0010_0113, "PC 1028 wrap");
        r_manual_addr = 32'd2;
        #1;
        check_word(w_imem_data, 32'h0050_0093, "PC 2 unaligned");

        @(negedge r_clock);
        r_use_manual_addr = 1'b0;
        r_reset = 1'b0;
        r_en = 1'b1;
        @(posedge r_clock);
        #1;
        check_word(w_cpu_addr, 32'd4, "CPU byte PC 4");
        check_word(w_cpu_pc, 32'd4, "debug byte PC 4");
        check_word(w_imem_data, 32'h0010_0113, "CPU fetch index 1");

        @(negedge r_clock);
        r_en = 1'b0;
        r_reg_snapshot = w_dbg_reg_data;
        r_latch_snapshot = w_dbg_latch_word;
        write_word(8'd1, 32'h1234_5678);
        check_word(w_cpu_addr, 32'd4, "pause keeps PC");
        check_word(w_cpu_pc, 32'd4, "pause keeps debug PC");
        check_word(w_dbg_reg_data, r_reg_snapshot, "pause keeps register state");
        check_word(w_dbg_latch_word, r_latch_snapshot, "pause keeps latch state");
        check_word(w_imem_data, 32'h1234_5678, "paused write changes imem");
        r_use_manual_addr = 1'b1;
        r_manual_addr = 32'd0;
        #1;
        check_word(w_imem_data, 32'h0050_0093, "paused write leaves neighbor");

        @(negedge r_clock);
        r_use_manual_addr = 1'b0;
        r_en = 1'b1;
        repeat (254) @(posedge r_clock);
        #1;
        check_word(w_cpu_addr, 32'd1020, "CPU byte PC 1020");
        check_word(w_cpu_pc, 32'd1020, "debug byte PC 1020");
        check_word(w_imem_data, 32'hdead_beef, "CPU fetch index 255");
        @(posedge r_clock);
        #1;
        check_word(w_cpu_addr, 32'd1024, "CPU byte PC 1024");
        check_word(w_cpu_pc, 32'd1024, "debug byte PC 1024");
        check_word(w_imem_data, 32'h0050_0093, "CPU wrapped fetch 0");
        @(posedge r_clock);
        #1;
        check_word(w_cpu_addr, 32'd1028, "CPU byte PC 1028");
        check_word(w_cpu_pc, 32'd1028, "debug byte PC 1028");
        check_word(w_imem_data, 32'h1234_5678, "CPU wrapped fetch 1");

        @(negedge r_clock);
        r_en = 1'b0;
        r_reset = 1'b1;
        @(posedge r_clock);
        #1;
        check_word(w_cpu_addr, 32'd0, "reset clears CPU PC");
        check_word(w_imem_data, 32'h0050_0093, "reset preserves imem");
        @(negedge r_clock);
        r_en = 1'b1;
        write_word(8'd0, 32'h0000_0013);
        check_word(w_cpu_addr, 32'd0, "held reset keeps CPU PC");
        check_word(w_imem_data, 32'h0000_0013, "held reset permits imem write");
        write_word(8'd1, 32'h0000_0073);
        check_word(w_cpu_addr, 32'd0, "held reset keeps CPU PC again");
        r_use_manual_addr = 1'b1;
        r_manual_addr = 32'd4;
        #1;
        check_word(w_imem_data, 32'h0000_0073, "held reset permits next word");

        if (errors != 0)
            $fatal(1, "FAIL tb_imem_bridge: %0d errors in %0d checks", errors, checks);
        else begin
            $display("PASS tb_imem_bridge: %0d checks", checks);
            $finish;
        end
    end
endmodule

`default_nettype wire

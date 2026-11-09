`timescale 1ns/1ps

// imem: arranca en HALT, escribe y lee una palabra, y sin i_we no cambia.
module tb_imem;
    reg clk = 1'b0;
    always #10 clk = ~clk;                        // 50 MHz

    reg  [7:0]  raddr = 8'd0;
    reg         we = 1'b0;
    reg  [7:0]  waddr = 8'd0;
    reg  [31:0] wdata = 32'd0;
    wire [31:0] rdata;

    imem u_dut (
        .i_clock(clk),
        .i_raddr(raddr), .o_rdata(rdata),
        .i_we(we), .i_waddr(waddr), .i_wdata(wdata)
    );

    integer errors = 0, checks = 0;
    integer i;

    initial begin #(1_000_000); $fatal(1, "FAIL tb_imem: watchdog"); end

    task automatic check_read(input [7:0] a, input [31:0] exp, input string caso);
        begin
            raddr = a;
            #1;
            checks = checks + 1;
            if (rdata !== exp) begin
                errors = errors + 1;
                $display("FAIL %s: imem[%0d] exp=%h got=%h", caso, a, exp, rdata);
            end
        end
    endtask

    task automatic write_word(input [7:0] a, input [31:0] d);
        begin
            @(negedge clk);
            we = 1'b1; waddr = a; wdata = d;
            @(negedge clk);
            we = 1'b0;
        end
    endtask

    initial begin
        @(negedge clk);
        // 1) las 256 posiciones arrancan en HALT
        for (i = 0; i < 256; i = i + 1) check_read(i[7:0], 32'h0000_0073, "inicial");
        // 2) escribir la 5 no toca las vecinas
        write_word(8'd5, 32'hDEADBEEF);
        check_read(8'd5, 32'hDEADBEEF, "escritura");
        check_read(8'd4, 32'h0000_0073, "vecina baja");
        check_read(8'd6, 32'h0000_0073, "vecina alta");
        // 3) extremos
        write_word(8'd255, 32'h12345678);
        write_word(8'd0,   32'h00500093);
        check_read(8'd255, 32'h12345678, "extremo alto");
        check_read(8'd0,   32'h00500093, "extremo bajo");
        // 4) sin i_we, wdata cambiando no modifica la memoria
        wdata = 32'hAAAA_AAAA; @(negedge clk);
        wdata = 32'h5555_5555; @(negedge clk);
        wdata = 32'hFFFF_FFFF; @(negedge clk);
        check_read(8'd5, 32'hDEADBEEF, "sin we");
        if (errors != 0) $fatal(1, "FAIL tb_imem: %0d errores", errors);
        $display("PASS tb_imem: %0d chequeos", checks);
        $finish;
    end
endmodule

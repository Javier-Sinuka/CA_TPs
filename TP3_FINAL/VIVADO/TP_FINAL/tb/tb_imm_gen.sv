`timescale 1ns/1ps

module tb_imm_gen;
    reg [31:0] r_instr;
    wire [31:0] w_imm;
    integer r_checks;

    imm_gen dut (.i_instr(r_instr), .o_imm(w_imm));

    task check_imm;
        input [31:0] instr, expected;
        begin
            r_instr = instr;
            #1;
            if (w_imm !== expected)
                $fatal(1, "IMM failed: instr=%h expected=%h got=%h",
                       instr, expected, w_imm);
            r_checks = r_checks + 1;
        end
    endtask

    initial begin
        r_checks = 0;
        check_imm(32'hfff0_0093, 32'hffff_ffff);
        check_imm(32'h07f0_0093, 32'd127);
        check_imm(32'hffc0_a183, 32'hffff_fffc);
        check_imm(32'h0040_81e7, 32'd4);
        check_imm(32'h0020_a623, 32'd12);
        check_imm(32'hfe20_a823, 32'hffff_fff0);
        check_imm(32'h0020_8663, 32'd12);
        check_imm(32'hfe20_8ee3, 32'hffff_fffc);
        check_imm(32'h0080_00ef, 32'd8);
        check_imm(32'hffdff0ef, 32'hffff_fffc);
        check_imm(32'h1234_50b7, 32'h1234_5000);
        check_imm(32'hffff_f0b7, 32'hffff_f000);
        check_imm(32'h0020_81b3, 32'd0);
        $display("tb_imm_gen passed: %0d checks", r_checks);
        $finish;
    end
endmodule

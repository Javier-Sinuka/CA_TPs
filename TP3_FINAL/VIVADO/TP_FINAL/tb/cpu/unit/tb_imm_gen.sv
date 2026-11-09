`timescale 1ns/1ps

module tb_imm_gen;
    reg [31:0] r_instr;
    wire [31:0] w_imm;
    integer checks, errors;

    imm_gen dut (.i_instr(r_instr), .o_imm(w_imm));

    task automatic check_imm;
        input [31:0] instr, expected;
        begin
            r_instr = instr;
            #1;
            checks = checks + 1;
            if (w_imm !== expected) begin
                errors = errors + 1;
                $display("FAIL imm: check=%0d instr=%h expected=%h got=%h",
                         checks, instr, expected, w_imm);
            end
        end
    endtask

    initial begin
        #10000;
        $fatal(1, "FAIL tb_imm_gen: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        // Vectores constantes; el esperado no se calcula con el decoder.
        check_imm(32'hfff0_0093, 32'hffff_ffff);
        check_imm(32'h07f0_0093, 32'd127);
        check_imm(32'h8000_0013, 32'hffff_f800); // I: -2048
        check_imm(32'h7ff0_0013, 32'd2047);      // I: +2047
        check_imm(32'hffc0_a183, 32'hffff_fffc);
        check_imm(32'h0040_81e7, 32'd4);
        check_imm(32'h0020_a623, 32'd12);
        check_imm(32'hfe20_a823, 32'hffff_fff0);
        check_imm(32'h8000_0023, 32'hffff_f800); // S: -2048
        check_imm(32'h7e00_0fa3, 32'd2047);      // S: +2047
        check_imm(32'hfe00_0fa3, 32'hffff_ffff); // S: -1
        check_imm(32'h0000_00a3, 32'd1);         // S: imm[0]
        check_imm(32'h0000_0123, 32'd2);         // S: imm[1]
        check_imm(32'h0000_0223, 32'd4);         // S: imm[2]
        check_imm(32'h0000_0423, 32'd8);         // S: imm[3]
        check_imm(32'h0000_0823, 32'd16);        // S: imm[4]
        check_imm(32'h0200_0023, 32'd32);        // S: imm[5]
        check_imm(32'h0400_0023, 32'd64);        // S: imm[6]
        check_imm(32'h0800_0023, 32'd128);       // S: imm[7]
        check_imm(32'h1000_0023, 32'd256);       // S: imm[8]
        check_imm(32'h2000_0023, 32'd512);       // S: imm[9]
        check_imm(32'h4000_0023, 32'd1024);      // S: imm[10]
        check_imm(32'h0020_8663, 32'd12);
        check_imm(32'hfe20_8ee3, 32'hffff_fffc);
        check_imm(32'hfe00_0ee3, 32'hffff_fffc); // B: -4, vector del contrato
        check_imm(32'h8000_0063, 32'hffff_f000); // B: -4096
        check_imm(32'h7e00_0fe3, 32'd4094);      // B: +4094
        check_imm(32'h0000_0163, 32'd2);         // B: imm[1]
        check_imm(32'h0000_0263, 32'd4);         // B: imm[2]
        check_imm(32'h0000_0463, 32'd8);         // B: imm[3]
        check_imm(32'h0000_0863, 32'd16);        // B: imm[4]
        check_imm(32'h0200_0063, 32'd32);        // B: imm[5]
        check_imm(32'h0400_0063, 32'd64);        // B: imm[6]
        check_imm(32'h0800_0063, 32'd128);       // B: imm[7]
        check_imm(32'h1000_0063, 32'd256);       // B: imm[8]
        check_imm(32'h2000_0063, 32'd512);       // B: imm[9]
        check_imm(32'h4000_0063, 32'd1024);      // B: imm[10]
        check_imm(32'h0000_00e3, 32'd2048);      // B: imm[11]
        check_imm(32'h0080_00ef, 32'd8);
        check_imm(32'hffdff0ef, 32'hffff_fffc);
        check_imm(32'h8000_006f, 32'hfff0_0000); // J: -1048576
        check_imm(32'h7fff_f06f, 32'd1048574);   // J: +1048574
        check_imm(32'h0020_006f, 32'd2);         // J: imm[1]
        check_imm(32'h0040_006f, 32'd4);         // J: imm[2]
        check_imm(32'h0080_006f, 32'd8);         // J: imm[3]
        check_imm(32'h0100_006f, 32'd16);        // J: imm[4]
        check_imm(32'h0200_006f, 32'd32);        // J: imm[5]
        check_imm(32'h0400_006f, 32'd64);        // J: imm[6]
        check_imm(32'h0800_006f, 32'd128);       // J: imm[7]
        check_imm(32'h1000_006f, 32'd256);       // J: imm[8]
        check_imm(32'h2000_006f, 32'd512);       // J: imm[9]
        check_imm(32'h4000_006f, 32'd1024);      // J: imm[10]
        check_imm(32'h0010_006f, 32'd2048);      // J: imm[11]
        check_imm(32'h0000_106f, 32'd4096);      // J: imm[12]
        check_imm(32'h0000_206f, 32'd8192);      // J: imm[13]
        check_imm(32'h0000_406f, 32'd16384);     // J: imm[14]
        check_imm(32'h0000_806f, 32'd32768);     // J: imm[15]
        check_imm(32'h0001_006f, 32'd65536);     // J: imm[16]
        check_imm(32'h0002_006f, 32'd131072);    // J: imm[17]
        check_imm(32'h0004_006f, 32'd262144);    // J: imm[18]
        check_imm(32'h0008_006f, 32'd524288);    // J: imm[19]
        check_imm(32'h1234_50b7, 32'h1234_5000);
        check_imm(32'hffff_f0b7, 32'hffff_f000);
        check_imm(32'h8000_00b7, 32'h8000_0000); // U: bit 31
        check_imm(32'habcd_e0b7, 32'habcd_e000);
        check_imm(32'hfff0_0183, 32'hffff_ffff); // Load I: funct3 inválido para control
        check_imm(32'h0000_0073, 32'd0);        // HALT: sin inmediato
        check_imm(32'h0020_81b3, 32'd0);
        check_imm(32'd0, 32'd0);                // opcode no soportado
        check_imm(32'hffff_ffff, 32'd0);        // opcode no soportado
        if (errors != 0)
            $fatal(1, "FAIL tb_imm_gen: %0d errores de %0d chequeos", errors, checks);
        else begin
            $display("PASS tb_imm_gen: %0d chequeos", checks);
            $finish;
        end
    end
endmodule

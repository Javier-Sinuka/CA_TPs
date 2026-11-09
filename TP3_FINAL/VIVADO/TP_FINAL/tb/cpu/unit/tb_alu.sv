`timescale 1ns/1ps
`include "riscv_defs.vh"

module tb_alu;
    reg [31:0] r_operand_a, r_operand_b;
    reg [3:0] r_op;
    wire [31:0] w_result;
    reg [31:0] r_edges [0:4];
    reg [31:0] r_shifts [0:6];
    reg [3:0] r_ops [0:9];
    reg [31:0] r_seed, r_a, r_b;
    integer checks, errors;
    integer i, j, k;

    alu dut (
        .i_operand_a(r_operand_a),
        .i_operand_b(r_operand_b),
        .i_op(r_op),
        .o_result(w_result)
    );

    // Oráculo de 64 bits: conversión explícita a signed y máscara RV32.
    function automatic [31:0] reference_result;
        input [31:0] a, b;
        input [3:0] op;
        reg [63:0] ua, ub;
        reg signed [63:0] sa, sb;
        reg [63:0] value;
        begin
            ua = {32'd0, a};
            ub = {32'd0, b};
            sa = {{32{a[31]}}, a};
            sb = {{32{b[31]}}, b};
            value = 64'd0;
            case (op)
                `ALU_ADD:  value = (ua + ub) & 64'h0000_0000_ffff_ffff;
                `ALU_SUB:  value = (ua - ub) & 64'h0000_0000_ffff_ffff;
                `ALU_SLL:  value = (ua << b[4:0]) & 64'h0000_0000_ffff_ffff;
                `ALU_SRL:  value = ua >> b[4:0];
                `ALU_SRA:  value = sa >>> b[4:0];
                `ALU_AND:  value = ua & ub;
                `ALU_OR:   value = ua | ub;
                `ALU_XOR:  value = ua ^ ub;
                `ALU_SLT:  value = (sa < sb) ? 64'd1 : 64'd0;
                `ALU_SLTU: value = (ua < ub) ? 64'd1 : 64'd0;
                default:   value = 64'd0;
            endcase
            reference_result = value[31:0];
        end
    endfunction

    function automatic [31:0] next_random;
        input [31:0] state;
        reg [31:0] x;
        begin
            x = state ^ (state << 13);
            x = x ^ (x >> 17);
            next_random = x ^ (x << 5);
        end
    endfunction

    task automatic check_result;
        input [31:0] a, b;
        input [3:0] op;
        input [31:0] expected;
        begin
            r_operand_a = a;
            r_operand_b = b;
            r_op = op;
            #1;
            checks = checks + 1;
            if (w_result !== expected) begin
                errors = errors + 1;
                $display("FAIL alu: check=%0d op=%h a=%h b=%h expected=%h got=%h",
                         checks, op, a, b, expected, w_result);
            end
        end
    endtask

    initial begin
        #100000;
        $fatal(1, "FAIL tb_alu: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        r_seed = 32'h5eed_1234;
        check_result(32'd5, 32'd7, `ALU_ADD, 32'd12);
        check_result(32'hffff_ffff, 32'd1, `ALU_ADD, 32'd0);
        check_result(32'h8000_0000, 32'h8000_0000, `ALU_ADD, 32'd0);
        check_result(32'h7fff_ffff, 32'd1, `ALU_ADD, 32'h8000_0000);
        check_result(32'd5, 32'd7, `ALU_SUB, 32'hffff_fffe);
        check_result(32'd0, 32'd1, `ALU_SUB, 32'hffff_ffff);
        check_result(32'd1, 32'd31, `ALU_SLL, 32'h8000_0000);
        check_result(32'd1, 32'd32, `ALU_SLL, 32'd1);
        check_result(32'd1, 32'd63, `ALU_SLL, 32'h8000_0000);
        check_result(32'h8000_0000, 32'd1, `ALU_SRL, 32'h4000_0000);
        check_result(32'h8000_0000, 32'd32, `ALU_SRL, 32'h8000_0000);
        check_result(32'h8000_0000, 32'd31, `ALU_SRL, 32'd1);
        check_result(32'hffff_ffff, 32'd4, `ALU_SRL, 32'h0fff_ffff);
        check_result(32'h8000_0000, 32'd1, `ALU_SRA, 32'hc000_0000);
        check_result(32'h8000_0000, 32'd63, `ALU_SRA, 32'hffff_ffff);
        check_result(32'h8000_0000, 32'd31, `ALU_SRA, 32'hffff_ffff);
        check_result(32'hffff_ffff, 32'd4, `ALU_SRA, 32'hffff_ffff);
        check_result(32'hf0f0_aa55, 32'h0ff0_0f0f, `ALU_AND, 32'h00f0_0a05);
        check_result(32'hf0f0_aa55, 32'h0ff0_0f0f, `ALU_OR, 32'hfff0_af5f);
        check_result(32'hf0f0_aa55, 32'h0ff0_0f0f, `ALU_XOR, 32'hff00_a55a);
        check_result(32'haaaa_aaaa, 32'h5555_5555, `ALU_AND, 32'd0);
        check_result(32'haaaa_aaaa, 32'h5555_5555, `ALU_OR, 32'hffff_ffff);
        check_result(32'haaaa_aaaa, 32'h5555_5555, `ALU_XOR, 32'hffff_ffff);
        check_result(32'h8000_0000, 32'd1, `ALU_SLT, 32'd1);
        check_result(32'd1, 32'h8000_0000, `ALU_SLT, 32'd0);
        check_result(32'hffff_ffff, 32'd1, `ALU_SLT, 32'd1);
        check_result(32'h8000_0000, 32'd1, `ALU_SLTU, 32'd0);
        check_result(32'd1, 32'h8000_0000, `ALU_SLTU, 32'd1);
        check_result(32'hffff_ffff, 32'd1, `ALU_SLTU, 32'd0);
        check_result(32'd1, 32'd2, `ALU_SLT, 32'd1);
        check_result(32'd2, 32'd2, `ALU_SLTU, 32'd0);
        check_result(32'd2, 32'd2, `ALU_SLT, 32'd0);
        check_result(32'd1, 32'd2, 4'd15, 32'd0);

        r_edges[0] = 32'd0;
        r_edges[1] = 32'd1;
        r_edges[2] = 32'hffff_ffff;
        r_edges[3] = 32'h7fff_ffff;
        r_edges[4] = 32'h8000_0000;
        for (i = 0; i < 10; i = i + 1) r_ops[i] = i;

        // Producto de operandos borde: todas las operaciones.
        for (i = 0; i < 5; i = i + 1)
            for (j = 0; j < 5; j = j + 1)
                for (k = 0; k < 10; k = k + 1)
                    check_result(r_edges[i], r_edges[j], r_ops[k],
                                 reference_result(r_edges[i], r_edges[j], r_ops[k]));

        r_shifts[0] = 32'd0;
        r_shifts[1] = 32'd1;
        r_shifts[2] = 32'd31;
        r_shifts[3] = 32'd32;
        r_shifts[4] = 32'd63;
        r_shifts[5] = 32'h8000_0000;
        r_shifts[6] = 32'hffff_ffff;
        for (i = 0; i < 5; i = i + 1)
            for (j = 0; j < 7; j = j + 1) begin
                check_result(r_edges[i], r_shifts[j], `ALU_SLL,
                             reference_result(r_edges[i], r_shifts[j], `ALU_SLL));
                check_result(r_edges[i], r_shifts[j], `ALU_SRL,
                             reference_result(r_edges[i], r_shifts[j], `ALU_SRL));
                check_result(r_edges[i], r_shifts[j], `ALU_SRA,
                             reference_result(r_edges[i], r_shifts[j], `ALU_SRA));
            end

        // xorshift32 con semilla fija: cada par cruza las diez operaciones.
        for (i = 0; i < 1000; i = i + 1) begin
            r_seed = next_random(r_seed);
            r_a = r_seed;
            r_seed = next_random(r_seed);
            r_b = r_seed;
            for (k = 0; k < 10; k = k + 1)
                check_result(r_a, r_b, r_ops[k],
                             reference_result(r_a, r_b, r_ops[k]));
        end

        for (i = 10; i < 16; i = i + 1)
            check_result(32'hdead_beef, 32'd7, i[3:0], 32'd0);
        check_result(32'hdead_beef, 32'd7, 4'bxxxx, 32'd0);
        check_result(32'hdead_beef, 32'd7, 4'bzzzz, 32'd0);

        if (errors != 0)
            $fatal(1, "FAIL tb_alu: %0d errores de %0d chequeos", errors, checks);
        else begin
            $display("PASS tb_alu: %0d chequeos, seed=%h", checks, 32'h5eed_1234);
            $finish;
        end
    end
endmodule

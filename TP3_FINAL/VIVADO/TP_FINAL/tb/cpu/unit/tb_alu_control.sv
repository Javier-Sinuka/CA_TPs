`timescale 1ns/1ps
`include "riscv_defs.vh"

module tb_alu_control;
    reg [31:0] r_instr, r_operand_a, r_operand_b;
    wire [3:0] w_alu_op, w_control_op;
    wire w_alu_valid, w_control_valid, w_reg_write;
    wire w_mem_read, w_mem_write, w_branch, w_jump, w_halt;
    wire [31:0] w_result;
    integer checks, errors, valid_patterns;
    integer opcode, funct3, funct7;
    reg [4:0] r_expected;

    alu_control u_alu_control (
        .i_opcode(r_instr[6:0]),
        .i_funct3(r_instr[14:12]),
        .i_funct7(r_instr[31:25]),
        .o_alu_op(w_alu_op),
        .o_valid(w_alu_valid)
    );

    control u_control (
        .i_instr(r_instr),
        .o_alu_op(w_control_op),
        .o_alu_src_b(),
        .o_reg_write(w_reg_write),
        .o_mem_read(w_mem_read),
        .o_mem_write(w_mem_write),
        .o_mem_to_reg(),
        .o_branch(w_branch),
        .o_jump(w_jump),
        .o_jalr(),
        .o_lui(),
        .o_halt(w_halt),
        .o_uses_rs1(),
        .o_uses_rs2(),
        .o_valid_instr(w_control_valid)
    );

    alu u_alu (
        .i_operand_a(r_operand_a),
        .i_operand_b(r_operand_b),
        .i_op(w_alu_op),
        .o_result(w_result)
    );

    // Tabla de referencia separada del casez del DUT; bit 4 = validez.
    function automatic [4:0] expected_decode;
        input [6:0] op;
        input [2:0] f3;
        input [6:0] f7;
        begin
            expected_decode = {1'b0, `ALU_ADD};
            if (op == 7'h33) begin
                if (f7 == 7'h00) begin
                    case (f3)
                        3'h0: expected_decode = {1'b1, `ALU_ADD};
                        3'h1: expected_decode = {1'b1, `ALU_SLL};
                        3'h2: expected_decode = {1'b1, `ALU_SLT};
                        3'h3: expected_decode = {1'b1, `ALU_SLTU};
                        3'h4: expected_decode = {1'b1, `ALU_XOR};
                        3'h5: expected_decode = {1'b1, `ALU_SRL};
                        3'h6: expected_decode = {1'b1, `ALU_OR};
                        3'h7: expected_decode = {1'b1, `ALU_AND};
                    endcase
                end else if (f7 == 7'h20) begin
                    if (f3 == 3'h0) expected_decode = {1'b1, `ALU_SUB};
                    if (f3 == 3'h5) expected_decode = {1'b1, `ALU_SRA};
                end
            end else if (op == 7'h13) begin
                case (f3)
                    3'h0: expected_decode = {1'b1, `ALU_ADD};
                    3'h2: expected_decode = {1'b1, `ALU_SLT};
                    3'h3: expected_decode = {1'b1, `ALU_SLTU};
                    3'h4: expected_decode = {1'b1, `ALU_XOR};
                    3'h6: expected_decode = {1'b1, `ALU_OR};
                    3'h7: expected_decode = {1'b1, `ALU_AND};
                    3'h1: if (f7 == 7'h00)
                        expected_decode = {1'b1, `ALU_SLL};
                    3'h5: begin
                        if (f7 == 7'h00)
                            expected_decode = {1'b1, `ALU_SRL};
                        else if (f7 == 7'h20)
                            expected_decode = {1'b1, `ALU_SRA};
                    end
                endcase
            end
        end
    endfunction

    function automatic [31:0] enc_r;
        input [6:0] f7;
        input [2:0] f3;
        begin
            enc_r = {f7, 5'd2, 5'd1, f3, 5'd3, 7'h33};
        end
    endfunction

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [2:0] f3;
        input [6:0] op;
        begin
            enc_i = {imm, 5'd1, f3, 5'd3, op};
        end
    endfunction

    task automatic check_execute;
        input [31:0] instr, a, b;
        input [3:0] expected_op;
        input [31:0] expected_result;
        begin
            r_instr = instr;
            r_operand_a = a;
            r_operand_b = b;
            #1;
            checks = checks + 1;
            if ({w_alu_valid, w_alu_op, w_control_valid, w_reg_write,
                 w_control_op, w_result} !==
                {1'b1, expected_op, 1'b1, 1'b1, expected_op,
                 expected_result}) begin
                errors = errors + 1;
                $display("FAIL execute: instr=%h a=%h b=%h valid/op=%b/%h control=%b/%b/%h result=%h expected=%h/%h",
                         instr, a, b, w_alu_valid, w_alu_op,
                         w_control_valid, w_reg_write, w_control_op,
                         w_result, expected_op, expected_result);
            end
        end
    endtask

    task automatic check_other;
        input [31:0] instr;
        input expected_valid, expected_reg_write;
        begin
            r_instr = instr;
            #1;
            checks = checks + 1;
            if ({w_alu_valid, w_alu_op, w_control_op, w_control_valid,
                 w_reg_write} !==
                {1'b0, `ALU_ADD, `ALU_ADD, expected_valid,
                 expected_reg_write}) begin
                errors = errors + 1;
                $display("FAIL other: instr=%h alu=%b/%h control=%h valid=%b reg_write=%b expected=%b/%b",
                         instr, w_alu_valid, w_alu_op, w_control_op,
                         w_control_valid, w_reg_write, expected_valid,
                         expected_reg_write);
            end
        end
    endtask

    initial begin
        #300000;
        $fatal(1, "FAIL tb_alu_control: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        valid_patterns = 0;
        r_instr = 32'd0;
        r_operand_a = 32'd0;
        r_operand_b = 32'd0;

        // 10 R: una ejecución dirigida para cada operación de ALU.
        check_execute(enc_r(7'h00, 3'h0), 32'd5, 32'd7, `ALU_ADD, 32'd12);
        check_execute(enc_r(7'h20, 3'h0), 32'd5, 32'd7, `ALU_SUB, 32'hffff_fffe);
        check_execute(enc_r(7'h00, 3'h1), 32'd1, 32'd31, `ALU_SLL, 32'h8000_0000);
        check_execute(enc_r(7'h00, 3'h2), 32'hffff_ffff, 32'd1, `ALU_SLT, 32'd1);
        check_execute(enc_r(7'h00, 3'h3), 32'hffff_ffff, 32'd1, `ALU_SLTU, 32'd0);
        check_execute(enc_r(7'h00, 3'h4), 32'haaaa_aaaa, 32'h5555_5555, `ALU_XOR, 32'hffff_ffff);
        check_execute(enc_r(7'h00, 3'h5), 32'h8000_0000, 32'd1, `ALU_SRL, 32'h4000_0000);
        check_execute(enc_r(7'h20, 3'h5), 32'h8000_0000, 32'd1, `ALU_SRA, 32'hc000_0000);
        check_execute(enc_r(7'h00, 3'h6), 32'haaaa_aaaa, 32'h5555_5555, `ALU_OR, 32'hffff_ffff);
        check_execute(enc_r(7'h00, 3'h7), 32'haaaa_aaaa, 32'h5555_5555, `ALU_AND, 32'd0);

        // 9 I-ALU; los bits altos de ADDI negativo no indican SUB.
        check_execute(32'hfff0_0093, 32'd0, 32'hffff_ffff, `ALU_ADD, 32'hffff_ffff);
        check_execute(enc_i(12'hfff, 3'h2, 7'h13), 32'd0, 32'hffff_ffff, `ALU_SLT, 32'd0);
        check_execute(enc_i(12'hfff, 3'h3, 7'h13), 32'd0, 32'hffff_ffff, `ALU_SLTU, 32'd1);
        check_execute(enc_i(12'h00f, 3'h4, 7'h13), 32'hf0, 32'h0f, `ALU_XOR, 32'hff);
        check_execute(enc_i(12'h00f, 3'h6, 7'h13), 32'hf0, 32'h0f, `ALU_OR, 32'hff);
        check_execute(enc_i(12'h00f, 3'h7, 7'h13), 32'hf0, 32'h0f, `ALU_AND, 32'd0);
        check_execute(enc_i(12'h01f, 3'h1, 7'h13), 32'd1, 32'd31, `ALU_SLL, 32'h8000_0000);
        check_execute(enc_i(12'h01f, 3'h5, 7'h13), 32'h8000_0000, 32'd31, `ALU_SRL, 32'd1);
        check_execute(enc_i(12'h41f, 3'h5, 7'h13), 32'h8000_0000, 32'd31, `ALU_SRA, 32'hffff_ffff);

        // Otros opcodes usan ADD en control aunque el subdecoder sea inválido.
        check_other(enc_i(12'hfff, 3'h0, 7'h03), 1'b1, 1'b1); // LB
        check_other(32'h0020_8023, 1'b1, 1'b0); // SB
        check_other(32'h0020_8063, 1'b1, 1'b0); // BEQ
        check_other(32'h0080_00ef, 1'b1, 1'b1); // JAL
        check_other(32'h0040_81e7, 1'b1, 1'b1); // JALR
        check_other(32'h1234_50b7, 1'b1, 1'b1); // LUI
        check_other(32'd0, 1'b0, 1'b0);

        // Barrido binario completo: 128 opcodes × 8 funct3 × 128 funct7.
        for (opcode = 0; opcode < 128; opcode = opcode + 1)
            for (funct3 = 0; funct3 < 8; funct3 = funct3 + 1)
                for (funct7 = 0; funct7 < 128; funct7 = funct7 + 1) begin
                    r_instr = {funct7[6:0], 5'd2, 5'd1, funct3[2:0], 5'd3, opcode[6:0]};
                    r_expected = expected_decode(opcode[6:0], funct3[2:0], funct7[6:0]);
                    #1;
                    checks = checks + 1;
                    if (r_expected[4]) valid_patterns = valid_patterns + 1;
                    if ({w_alu_valid, w_alu_op} !== r_expected) begin
                        errors = errors + 1;
                        $display("FAIL decode: instr=%h expected=%b got=%b%h",
                                 r_instr, r_expected, w_alu_valid, w_alu_op);
                    end
                    if (opcode == 7'h33 || opcode == 7'h13) begin
                        checks = checks + 1;
                        if ({w_control_valid, w_reg_write, w_control_op,
                             w_mem_read, w_mem_write, w_branch, w_jump,
                             w_halt} !==
                            {r_expected[4], r_expected[4], r_expected[3:0],
                             5'b0}) begin
                            errors = errors + 1;
                            $display("FAIL effects: instr=%h valid=%b reg_write=%b op=%h mem_read=%b mem_write=%b branch=%b jump=%b halt=%b",
                                     r_instr, w_control_valid, w_reg_write,
                                     w_control_op, w_mem_read, w_mem_write,
                                     w_branch, w_jump, w_halt);
                        end
                    end
                end

        // Un X/Z en cualquier campo del subdecoder no puede activar writes.
        r_instr = enc_r(7'h00, 3'h0);
        r_instr[6] = 1'bx;
        #1;
        checks = checks + 1;
        if ({w_alu_valid, w_alu_op, w_control_valid, w_reg_write} !==
            {1'b0, `ALU_ADD, 2'b00}) begin
            errors = errors + 1;
            $display("FAIL unknown opcode: instr=%h", r_instr);
        end
        r_instr = enc_r(7'h00, 3'h0);
        r_instr[12] = 1'bz;
        #1;
        checks = checks + 1;
        if ({w_alu_valid, w_alu_op, w_control_valid, w_reg_write} !==
            {1'b0, `ALU_ADD, 2'b00}) begin
            errors = errors + 1;
            $display("FAIL unknown funct3: instr=%h", r_instr);
        end
        r_instr = enc_r(7'h00, 3'h0);
        r_instr[25] = 1'bx;
        #1;
        checks = checks + 1;
        if ({w_alu_valid, w_alu_op, w_control_valid, w_reg_write} !==
            {1'b0, `ALU_ADD, 2'b00}) begin
            errors = errors + 1;
            $display("FAIL unknown funct7: instr=%h", r_instr);
        end
        if (valid_patterns != 781) begin
            errors = errors + 1;
            $display("FAIL pattern count: expected=781 got=%0d", valid_patterns);
        end

        if (errors != 0)
            $fatal(1, "FAIL tb_alu_control: %0d errores de %0d chequeos", errors, checks);
        else begin
            $display("PASS tb_alu_control: %0d chequeos, valid_patterns=%0d",
                     checks, valid_patterns);
            $finish;
        end
    end
endmodule

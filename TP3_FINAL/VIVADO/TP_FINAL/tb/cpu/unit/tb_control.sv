`timescale 1ns/1ps
`include "riscv_defs.vh"

module tb_control;
    reg [31:0] r_instr;
    wire [3:0] w_alu_op;
    wire w_alu_src_b, w_reg_write, w_mem_read, w_mem_write, w_mem_to_reg;
    wire w_branch, w_jump, w_jalr, w_lui, w_halt;
    wire w_uses_rs1, w_uses_rs2, w_valid_instr;
    wire [12:0] w_flags;
    wire [31:0] w_imm;
    integer checks, errors;
    integer f3;

    localparam [12:0] F_ALU_SRC_B = 13'd1 << 12;
    localparam [12:0] F_REG_WRITE = 13'd1 << 11;
    localparam [12:0] F_MEM_READ = 13'd1 << 10;
    localparam [12:0] F_MEM_WRITE = 13'd1 << 9;
    localparam [12:0] F_MEM_TO_REG = 13'd1 << 8;
    localparam [12:0] F_BRANCH = 13'd1 << 7;
    localparam [12:0] F_JUMP = 13'd1 << 6;
    localparam [12:0] F_JALR = 13'd1 << 5;
    localparam [12:0] F_LUI = 13'd1 << 4;
    localparam [12:0] F_HALT = 13'd1 << 3;
    localparam [12:0] F_USES_RS1 = 13'd1 << 2;
    localparam [12:0] F_USES_RS2 = 13'd1 << 1;
    localparam [12:0] F_VALID = 13'd1;

    localparam [12:0] F_R = F_REG_WRITE | F_USES_RS1 | F_USES_RS2 | F_VALID;
    localparam [12:0] F_I = F_ALU_SRC_B | F_REG_WRITE | F_USES_RS1 | F_VALID;
    localparam [12:0] F_LOAD = F_I | F_MEM_READ | F_MEM_TO_REG;
    localparam [12:0] F_STORE = F_ALU_SRC_B | F_MEM_WRITE | F_USES_RS1 | F_USES_RS2 | F_VALID;
    localparam [12:0] F_BRANCH_OP = F_BRANCH | F_USES_RS1 | F_USES_RS2 | F_VALID;

    assign w_flags = {
        w_alu_src_b, w_reg_write, w_mem_read, w_mem_write, w_mem_to_reg,
        w_branch, w_jump, w_jalr, w_lui, w_halt, w_uses_rs1,
        w_uses_rs2, w_valid_instr
    };

    control dut (
        .i_instr(r_instr),
        .o_alu_op(w_alu_op),
        .o_alu_src_b(w_alu_src_b),
        .o_reg_write(w_reg_write),
        .o_mem_read(w_mem_read),
        .o_mem_write(w_mem_write),
        .o_mem_to_reg(w_mem_to_reg),
        .o_branch(w_branch),
        .o_jump(w_jump),
        .o_jalr(w_jalr),
        .o_lui(w_lui),
        .o_halt(w_halt),
        .o_uses_rs1(w_uses_rs1),
        .o_uses_rs2(w_uses_rs2),
        .o_valid_instr(w_valid_instr)
    );

    imm_gen u_imm_gen (.i_instr(r_instr), .o_imm(w_imm));

    function [31:0] enc_r;
        input [6:0] funct7;
        input [2:0] funct3;
        begin
            enc_r = {funct7, 5'd2, 5'd1, funct3, 5'd3, 7'b0110011};
        end
    endfunction

    function [31:0] enc_i;
        input [11:0] imm;
        input [2:0] funct3;
        input [6:0] opcode;
        begin
            enc_i = {imm, 5'd1, funct3, 5'd3, opcode};
        end
    endfunction

    task automatic check_control;
        input [31:0] instr;
        input [3:0] expected_alu_op;
        input [12:0] expected_flags;
        begin
            r_instr = instr;
            #1;
            checks = checks + 1;
            if (w_alu_op !== expected_alu_op || w_flags !== expected_flags) begin
                errors = errors + 1;
                $display("FAIL control: check=%0d instr=%h op=%h/%h flags=%h/%h",
                         checks, instr, w_alu_op, expected_alu_op, w_flags,
                         expected_flags);
            end
        end
    endtask

    task automatic check_control_imm;
        input [31:0] instr;
        input [3:0] expected_alu_op;
        input [12:0] expected_flags;
        input [31:0] expected_imm;
        begin
            check_control(instr, expected_alu_op, expected_flags);
            checks = checks + 1;
            if (w_imm !== expected_imm) begin
                errors = errors + 1;
                $display("FAIL immediate: instr=%h expected=%h got=%h",
                         instr, expected_imm, w_imm);
            end
        end
    endtask

    initial begin
        #10000;
        $fatal(1, "FAIL tb_control: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        check_control(enc_r(7'b0000000, 3'b000), `ALU_ADD, F_R);
        check_control(enc_r(7'b0100000, 3'b000), `ALU_SUB, F_R);
        check_control(enc_r(7'b0000000, 3'b001), `ALU_SLL, F_R);
        check_control(enc_r(7'b0000000, 3'b010), `ALU_SLT, F_R);
        check_control(enc_r(7'b0000000, 3'b011), `ALU_SLTU, F_R);
        check_control(enc_r(7'b0000000, 3'b100), `ALU_XOR, F_R);
        check_control(enc_r(7'b0000000, 3'b101), `ALU_SRL, F_R);
        check_control(enc_r(7'b0100000, 3'b101), `ALU_SRA, F_R);
        check_control(enc_r(7'b0000000, 3'b110), `ALU_OR, F_R);
        check_control(enc_r(7'b0000000, 3'b111), `ALU_AND, F_R);

        check_control(enc_i(12'hfff, 3'b000, 7'b0010011), `ALU_ADD, F_I);
        check_control(enc_i(12'hfff, 3'b010, 7'b0010011), `ALU_SLT, F_I);
        check_control(enc_i(12'hfff, 3'b011, 7'b0010011), `ALU_SLTU, F_I);
        check_control(enc_i(12'hfff, 3'b100, 7'b0010011), `ALU_XOR, F_I);
        check_control(enc_i(12'hfff, 3'b110, 7'b0010011), `ALU_OR, F_I);
        check_control(enc_i(12'hfff, 3'b111, 7'b0010011), `ALU_AND, F_I);
        check_control(enc_i(12'h002, 3'b001, 7'b0010011), `ALU_SLL, F_I);
        check_control(enc_i(12'h002, 3'b101, 7'b0010011), `ALU_SRL, F_I);
        check_control(enc_i(12'h402, 3'b101, 7'b0010011), `ALU_SRA, F_I);

        check_control(enc_i(12'h004, 3'b000, 7'b0000011), `ALU_ADD, F_LOAD);
        check_control(enc_i(12'h004, 3'b001, 7'b0000011), `ALU_ADD, F_LOAD);
        check_control(enc_i(12'h004, 3'b010, 7'b0000011), `ALU_ADD, F_LOAD);
        check_control(enc_i(12'h004, 3'b100, 7'b0000011), `ALU_ADD, F_LOAD);
        check_control(enc_i(12'h004, 3'b101, 7'b0000011), `ALU_ADD, F_LOAD);

        check_control(32'h0020_8023, `ALU_ADD, F_STORE);
        check_control(32'h0020_9023, `ALU_ADD, F_STORE);
        check_control(32'h0020_a023, `ALU_ADD, F_STORE);
        check_control(32'h0020_8063, `ALU_ADD, F_BRANCH_OP);
        check_control(32'h0020_9063, `ALU_ADD, F_BRANCH_OP);
        check_control(32'h0080_00ef, `ALU_ADD, F_REG_WRITE | F_JUMP | F_VALID);
        check_control(enc_i(12'h004, 3'b000, 7'b1100111), `ALU_ADD,
                      F_I | F_JUMP | F_JALR);
        check_control(32'h1234_50b7, `ALU_ADD,
                      F_ALU_SRC_B | F_REG_WRITE | F_LUI | F_VALID);
        check_control(32'h0000_0073, `ALU_ADD, F_HALT | F_VALID);

        // La misma instrucción alimenta control e imm_gen: un caso por formato.
        check_control_imm(enc_r(7'd0, 3'd0), `ALU_ADD, F_R, 32'd0);
        check_control_imm(32'hfff0_0093, `ALU_ADD, F_I, 32'hffff_ffff);
        check_control_imm(32'hffc0_a183, `ALU_ADD, F_LOAD, 32'hffff_fffc);
        check_control_imm(32'hfe20_a823, `ALU_ADD, F_STORE, 32'hffff_fff0);
        check_control_imm(32'hfe20_8ee3, `ALU_ADD, F_BRANCH_OP, 32'hffff_fffc);
        check_control_imm(32'h0080_00ef, `ALU_ADD,
                          F_REG_WRITE | F_JUMP | F_VALID, 32'd8);
        check_control_imm(32'h0040_81e7, `ALU_ADD,
                          F_I | F_JUMP | F_JALR, 32'd4);
        check_control_imm(32'h1234_50b7, `ALU_ADD,
                          F_ALU_SRC_B | F_REG_WRITE | F_LUI | F_VALID,
                          32'h1234_5000);
        check_control_imm(32'h0000_0073, `ALU_ADD, F_HALT | F_VALID, 32'd0);

        // El aparente rs2=x5 en ADDI es parte del inmediato, no una fuente.
        check_control(32'h0000_a283, `ALU_ADD, F_LOAD); // LW x5,0(x1)
        check_control(32'h0050_8313, `ALU_ADD, F_I);    // ADDI x6,x1,5
        check_control(32'h0000_0013, `ALU_ADD, F_I);    // NOP válido, distinto de burbuja

        // Barrido completo de funct3 en familias no R/I-ALU.
        for (f3 = 0; f3 < 8; f3 = f3 + 1) begin
            if (f3 == 0 || f3 == 1 || f3 == 2 || f3 == 4 || f3 == 5)
                check_control(enc_i(12'h004, f3[2:0], 7'h03), `ALU_ADD, F_LOAD);
            else
                check_control(enc_i(12'h004, f3[2:0], 7'h03), `ALU_ADD, 13'd0);
            if (f3 <= 2)
                check_control({7'd0, 5'd2, 5'd1, f3[2:0], 5'd3, 7'h23},
                              `ALU_ADD, F_STORE);
            else
                check_control({7'd0, 5'd2, 5'd1, f3[2:0], 5'd3, 7'h23},
                              `ALU_ADD, 13'd0);
            if (f3 <= 1)
                check_control({7'd0, 5'd2, 5'd1, f3[2:0], 5'd3, 7'h63},
                              `ALU_ADD, F_BRANCH_OP);
            else
                check_control({7'd0, 5'd2, 5'd1, f3[2:0], 5'd3, 7'h63},
                              `ALU_ADD, 13'd0);
            if (f3 == 0)
                check_control(enc_i(12'h004, f3[2:0], 7'h67), `ALU_ADD,
                              F_I | F_JUMP | F_JALR);
            else
                check_control(enc_i(12'h004, f3[2:0], 7'h67), `ALU_ADD, 13'd0);
        end

        check_control(enc_r(7'b0000001, 3'b000), `ALU_ADD, 13'd0);
        check_control(enc_r(7'b0100000, 3'b111), `ALU_ADD, 13'd0);
        check_control(enc_i(12'h402, 3'b001, 7'b0010011), `ALU_ADD, 13'd0);
        check_control(enc_i(12'h202, 3'b101, 7'b0010011), `ALU_ADD, 13'd0);
        check_control(enc_i(12'h004, 3'b011, 7'b0000011), `ALU_ADD, 13'd0);
        check_control(32'h0020_b023, `ALU_ADD, 13'd0);
        check_control(32'h0020_c063, `ALU_ADD, 13'd0);
        check_control(enc_i(12'h004, 3'b001, 7'b1100111), `ALU_ADD, 13'd0);
        check_control(32'h0010_0073, `ALU_ADD, 13'd0);
        check_control(32'h0000_00f3, `ALU_ADD, 13'd0);
        check_control(32'h0000_1073, `ALU_ADD, 13'd0);
        check_control(32'd0, `ALU_ADD, 13'd0);
        check_control({7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, 7'b01100z1}, `ALU_ADD, 13'd0);
        check_control({7'b0000000, 5'd2, 5'd1, 3'b0z0, 5'd3, 7'b0110011}, `ALU_ADD, 13'd0);
        check_control({7'b000000z, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0110011}, `ALU_ADD, 13'd0);
        check_control({7'b000000x, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0010011}, `ALU_ADD, 13'd0);

        if (errors != 0)
            $fatal(1, "FAIL tb_control: %0d errores de %0d chequeos", errors, checks);
        else begin
            $display("PASS tb_control: %0d chequeos", checks);
            $finish;
        end
    end
endmodule

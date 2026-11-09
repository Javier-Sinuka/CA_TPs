`timescale 1ns/1ps
`default_nettype none

module tb_hazard_unit;
    reg r_valid_ex;
    reg r_mem_read_ex;
    reg [4:0] r_rd_ex;
    reg r_valid_id;
    reg r_uses_rs1_id;
    reg r_uses_rs2_id;
    reg [4:0] r_rs1_id;
    reg [4:0] r_rs2_id;
    reg r_decode;
    reg [31:0] r_instr_id;
    reg [31:0] r_consumed_registers;
    reg r_expected_stall;
    wire w_decoded_uses_rs1;
    wire w_decoded_uses_rs2;
    wire w_valid_instr;
    wire w_uses_rs1_id = r_decode ? w_decoded_uses_rs1 : r_uses_rs1_id;
    wire w_uses_rs2_id = r_decode ? w_decoded_uses_rs2 : r_uses_rs2_id;
    wire [4:0] w_rs1_id = r_decode ? r_instr_id[19:15] : r_rs1_id;
    wire [4:0] w_rs2_id = r_decode ? r_instr_id[24:20] : r_rs2_id;
    wire w_stall;
    integer checks;
    integer errors;
    integer destination;
    integer source_a;
    integer source_b;
    integer usage;
    integer validity;

    hazard_unit dut (
        .i_valid_ex(r_valid_ex),
        .i_mem_read_ex(r_mem_read_ex),
        .i_rd_ex(r_rd_ex),
        .i_valid_id(r_valid_id),
        .i_uses_rs1_id(w_uses_rs1_id),
        .i_uses_rs2_id(w_uses_rs2_id),
        .i_rs1_id(w_rs1_id),
        .i_rs2_id(w_rs2_id),
        .o_stall(w_stall)
    );

    control u_control (
        .i_instr(r_instr_id),
        .o_alu_op(),
        .o_alu_src_b(),
        .o_reg_write(),
        .o_mem_read(),
        .o_mem_write(),
        .o_mem_to_reg(),
        .o_branch(),
        .o_jump(),
        .o_jalr(),
        .o_lui(),
        .o_halt(),
        .o_uses_rs1(w_decoded_uses_rs1),
        .o_uses_rs2(w_decoded_uses_rs2),
        .o_valid_instr(w_valid_instr)
    );

    task automatic check_stall(input bit expected, input string label);
        begin
            #1;
            checks = checks + 1;
            if (w_stall !== expected) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL tb_hazard_unit: %s producer=%b/%b/x%0d consumer=%b uses=%b%b rs1=x%0d rs2=x%0d expected=%b got=%b",
                             label, r_valid_ex, r_mem_read_ex, r_rd_ex, r_valid_id,
                             w_uses_rs1_id, w_uses_rs2_id, w_rs1_id, w_rs2_id, expected, w_stall);
            end
        end
    endtask

    task automatic check_instruction(input [31:0] instruction,
                                     input [1:0] expected_usage,
                                     input bit expected_valid,
                                     input bit expected_stall,
                                     input string label);
        begin
            r_instr_id = instruction;
            check_stall(expected_stall, label);
            checks = checks + 2;
            if ({w_decoded_uses_rs1, w_decoded_uses_rs2} !== expected_usage) begin
                errors = errors + 1;
                $display("FAIL tb_hazard_unit: %s usage expected=%b got=%b%b", label,
                         expected_usage, w_decoded_uses_rs1, w_decoded_uses_rs2);
            end
            if (w_valid_instr !== expected_valid) begin
                errors = errors + 1;
                $display("FAIL tb_hazard_unit: %s encoding expected=%b got=%b", label,
                         expected_valid, w_valid_instr);
            end
        end
    endtask

    initial begin
        #3000000;
        $fatal(1, "FAIL tb_hazard_unit: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        r_valid_ex = 1'b1;
        r_mem_read_ex = 1'b1;
        r_rd_ex = 5'd5;
        r_valid_id = 1'b1;
        r_uses_rs1_id = 1'b0;
        r_uses_rs2_id = 1'b0;
        r_rs1_id = 5'd0;
        r_rs2_id = 5'd0;
        r_decode = 1'b1;
        r_instr_id = 32'd0;
        r_consumed_registers = 32'd0;
        r_expected_stall = 1'b0;

        check_instruction(32'h0092_8333, 2'b11, 1'b1, 1'b1, "LW to ADD rs1");
        check_instruction(32'h0054_8333, 2'b11, 1'b1, 1'b1, "LW to ADD rs2");
        check_instruction(32'h0052_8333, 2'b11, 1'b1, 1'b1, "LW to ADD both sources");
        check_instruction(32'h0094_0333, 2'b11, 1'b1, 1'b0, "independent ADD");
        check_instruction(32'h0050_2023, 2'b11, 1'b1, 1'b1, "LW to SW data");
        check_instruction(32'h0092_a023, 2'b11, 1'b1, 1'b1, "LW to SW base");
        check_instruction(32'h0050_0423, 2'b11, 1'b1, 1'b1, "LW to SB data");
        check_instruction(32'h0050_1423, 2'b11, 1'b1, 1'b1, "LW to SH data");
        check_instruction(32'h0050_0463, 2'b11, 1'b1, 1'b1, "LW to BEQ rs2");
        check_instruction(32'h0002_9463, 2'b11, 1'b1, 1'b1, "LW to BNE rs1");
        check_instruction(32'h0050_0313, 2'b10, 1'b1, 1'b0, "ADDI immediate resembles rs2");
        check_instruction(32'h0052_8313, 2'b10, 1'b1, 1'b1, "dependent ADDI still consumes rs1");
        check_instruction(32'h0050_1313, 2'b10, 1'b1, 1'b0, "SLLI shamt resembles rs2");
        check_instruction(32'h0050_2303, 2'b10, 1'b1, 1'b0, "LW offset resembles rs2");
        check_instruction(32'h0002_a303, 2'b10, 1'b1, 1'b1, "LW to LW base");
        check_instruction(32'h0050_0367, 2'b10, 1'b1, 1'b0, "JALR offset resembles rs2");
        check_instruction(32'h0002_8367, 2'b10, 1'b1, 1'b1, "LW to JALR base");
        check_instruction(32'h0052_8337, 2'b00, 1'b1, 1'b0, "LUI fields resemble both sources");
        check_instruction(32'h0052_836f, 2'b00, 1'b1, 1'b0, "JAL fields resemble both sources");
        check_instruction(32'h0000_0073, 2'b00, 1'b1, 1'b0, "HALT consumes neither source");
        check_instruction(32'h0052_807f, 2'b00, 1'b0, 1'b0, "illegal opcode with matching fields");
        check_instruction(32'h0252_8333, 2'b00, 1'b0, 1'b0, "unsupported MUL with matching fields");
        r_valid_id = 1'b0;
        check_instruction(32'h0052_8333, 2'b11, 1'b1, 1'b0, "bubble with dependent encoding");
        r_valid_id = 1'b1;
        r_mem_read_ex = 1'b0;
        check_instruction(32'h0052_8333, 2'b11, 1'b1, 1'b0, "non-load RAW needs no load-use stall");

        r_decode = 1'b0;
        for (destination = 0; destination < 32; destination = destination + 1) begin
            r_rd_ex = destination[4:0];
            for (source_a = 0; source_a < 32; source_a = source_a + 1) begin
                r_rs1_id = source_a[4:0];
                for (source_b = 0; source_b < 32; source_b = source_b + 1) begin
                    r_rs2_id = source_b[4:0];
                    for (usage = 0; usage < 4; usage = usage + 1) begin
                        {r_uses_rs1_id, r_uses_rs2_id} = usage[1:0];
                        r_consumed_registers = 32'd0;
                        if (usage[1]) r_consumed_registers[source_a] = 1'b1;
                        if (usage[0]) r_consumed_registers[source_b] = 1'b1;
                        r_consumed_registers[0] = 1'b0;
                        for (validity = 0; validity < 8; validity = validity + 1) begin
                            {r_valid_ex, r_mem_read_ex, r_valid_id} = validity[2:0];
                            r_expected_stall = 1'b0;
                            if (validity == 7)
                                r_expected_stall = r_consumed_registers[destination];
                            check_stall(r_expected_stall, "exhaustive input sweep");
                        end
                    end
                end
            end
        end

        if (errors != 0)
            $fatal(1, "FAIL tb_hazard_unit: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_hazard_unit: %0d checks, exhaustive binary inputs and 24 decoded scenarios", checks);
        $finish;
    end
endmodule

`default_nettype wire

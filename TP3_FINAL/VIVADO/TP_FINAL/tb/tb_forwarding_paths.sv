`timescale 1ns/1ps
`default_nettype none

module tb_forwarding_paths;
    reg r_clock;
    reg r_reset;
    reg r_en;
    reg [4:0] r_dbg_reg_addr;
    reg [3:0] r_dbg_latch_sel;
    reg [7:0] r_dbg_mem_addr;
    reg [31:0] r_program [0:255];
    wire [31:0] w_imem_addr;
    wire [31:0] w_imem_data = r_program[w_imem_addr[9:2]];
    wire w_halted;
    wire [31:0] w_dbg_reg_data;
    wire [31:0] w_dbg_latch_word;
    wire [31:0] w_dbg_mem_data;
    wire w_dbg_mem_dirty;
    wire [31:0] w_dbg_pc;
    reg [8:0] r_seen;
    integer checks;
    integer errors;
    integer index;

    cpu dut (
        .i_clock(r_clock),
        .i_reset(r_reset),
        .i_en(r_en),
        .o_halted(w_halted),
        .o_imem_addr(w_imem_addr),
        .i_imem_data(w_imem_data),
        .i_dbg_reg_addr(r_dbg_reg_addr),
        .o_dbg_reg_data(w_dbg_reg_data),
        .i_dbg_latch_sel(r_dbg_latch_sel),
        .o_dbg_latch_word(w_dbg_latch_word),
        .i_dbg_mem_addr(r_dbg_mem_addr),
        .o_dbg_mem_data(w_dbg_mem_data),
        .o_dbg_mem_dirty(w_dbg_mem_dirty),
        .o_dbg_pc(w_dbg_pc)
    );

    task automatic check_word(input [31:0] got, input [31:0] expected,
                              input string label);
        begin
            checks = checks + 1;
            if (got !== expected) begin
                errors = errors + 1;
                $display("FAIL tb_forwarding_paths: %s expected=%08h got=%08h pc_ex=%08h",
                         label, expected, got, dut.w_pc_ex);
            end
        end
    endtask

    task automatic check_ex;
        begin
            if (dut.w_valid_ex) begin
                checks = checks + 2;
                if (dut.w_forward_a_ex === 2'b11 || (^dut.w_forward_a_ex) === 1'bx) begin
                    errors = errors + 1;
                    $display("FAIL tb_forwarding_paths: invalid selector A at pc_ex=%08h", dut.w_pc_ex);
                end
                if (dut.w_forward_b_ex === 2'b11 || (^dut.w_forward_b_ex) === 1'bx) begin
                    errors = errors + 1;
                    $display("FAIL tb_forwarding_paths: invalid selector B at pc_ex=%08h", dut.w_pc_ex);
                end
                case (dut.w_pc_ex)
                    32'd4: begin
                        r_seen[0] = 1'b1;
                        check_word({30'd0, dut.w_forward_b_ex}, 32'd2, "ADDI to SW selector");
                        check_word(dut.w_rs2_fwd_ex, 32'd7, "ADDI to SW data");
                        r_dbg_latch_sel = 4'd4;
                        #1;
                        check_word(w_dbg_latch_word, 32'd0, "captured rs2 stays old");
                    end
                    32'd16: begin
                        r_seen[1] = 1'b1;
                        check_word({30'd0, dut.w_forward_a_ex}, 32'd1, "two producers A from WB");
                        check_word({30'd0, dut.w_forward_b_ex}, 32'd2, "two producers B from MEM");
                        check_word(dut.w_rs1_fwd_ex, 32'd3, "two producers rs1");
                        check_word(dut.w_rs2_fwd_ex, 32'd5, "two producers rs2");
                        check_word(dut.w_result_ex, 32'd8, "two producers ALU result");
                    end
                    32'd20: begin
                        r_seen[2] = 1'b1;
                        check_word({30'd0, dut.w_forward_a_ex}, 32'd2, "immediate source selector");
                        check_word({30'd0, dut.w_forward_b_ex}, 32'd0, "immediate ignores rs2");
                        check_word(dut.w_rs1_fwd_ex, 32'd8, "immediate forwarded rs1");
                        check_word(dut.w_result_ex, 32'd18, "immediate ALU operand");
                    end
                    32'd28: begin
                        r_seen[3] = 1'b1;
                        check_word({30'd0, dut.w_forward_a_ex}, 32'd2, "JAL link selector");
                        check_word(dut.w_rs1_fwd_ex, 32'd28, "JAL link value");
                        check_word(dut.w_result_ex, 32'd30, "JAL dependent result");
                    end
                    32'd36: begin
                        r_seen[4] = 1'b1;
                        check_word({30'd0, dut.w_forward_a_ex}, 32'd2, "JALR link selector");
                        check_word(dut.w_rs1_fwd_ex, 32'd36, "JALR link value");
                        check_word(dut.w_result_ex, 32'd39, "JALR dependent result");
                    end
                    32'd48: begin
                        r_seen[5] = 1'b1;
                        check_word({30'd0, dut.w_forward_a_ex}, 32'd1, "load from WB selector");
                        check_word({30'd0, dut.w_forward_b_ex}, 32'd2, "ALU from MEM selector");
                        check_word(dut.w_rs1_fwd_ex, 32'd7, "load data not address");
                        check_word(dut.w_rs2_fwd_ex, 32'd1, "ALU second source");
                        check_word(dut.w_result_ex, 32'd8, "load dependent result");
                    end
                    32'd60: begin
                        r_seen[6] = 1'b1;
                        check_word({30'd0, dut.w_forward_a_ex}, 32'd1, "branch source A selector");
                        check_word({30'd0, dut.w_forward_b_ex}, 32'd2, "branch source B selector");
                        check_word(dut.w_rs1_fwd_ex, 32'd11, "branch source A value");
                        check_word(dut.w_rs2_fwd_ex, 32'd22, "branch source B value");
                    end
                    32'd68: begin
                        r_seen[7] = 1'b1;
                        check_word({30'd0, dut.w_forward_a_ex}, 32'd2, "JALR base selector");
                        check_word(dut.w_rs1_fwd_ex, 32'd64, "JALR forwarded base");
                        check_word(dut.u_execute.w_alu_result_ex, 32'd64, "JALR target calculation");
                        check_word(dut.w_result_ex, 32'd72, "JALR architectural link");
                    end
                    32'd72: begin
                        r_seen[8] = 1'b1;
                        check_word({30'd0, dut.w_forward_a_ex}, 32'd2, "second JALR link selector");
                        check_word(dut.w_rs1_fwd_ex, 32'd72, "second JALR link value");
                        check_word(dut.w_result_ex, 32'd73, "second JALR dependent result");
                    end
                    default: begin end
                endcase
            end
        end
    endtask

    task automatic tick;
        begin
            @(posedge r_clock);
            #1;
            check_ex();
        end
    endtask

    task automatic check_reg(input [4:0] addr, input [31:0] expected);
        begin
            r_dbg_reg_addr = addr;
            #1;
            check_word(w_dbg_reg_data, expected, "register final");
        end
    endtask

    initial begin
        r_clock = 1'b0;
        forever #5 r_clock = ~r_clock;
    end

    initial begin
        #10000;
        $fatal(1, "FAIL tb_forwarding_paths: watchdog");
    end

    initial begin
        checks = 0;
        errors = 0;
        r_seen = 9'd0;
        r_reset = 1'b1;
        r_en = 1'b1;
        r_dbg_reg_addr = 5'd0;
        r_dbg_latch_sel = 4'd0;
        r_dbg_mem_addr = 8'd0;
        for (index = 0; index < 256; index = index + 1)
            r_program[index] = 32'h0000_0013;
        r_program[0] = 32'h0070_0293;
        r_program[1] = 32'h0050_2023;
        r_program[2] = 32'h0030_0093;
        r_program[3] = 32'h0050_0113;
        r_program[4] = 32'h0020_81b3;
        r_program[5] = 32'h00a1_8213;
        r_program[6] = 32'h0040_04ef;
        r_program[7] = 32'h0024_8513;
        r_program[8] = 32'h0000_05e7;
        r_program[9] = 32'h0035_8613;
        r_program[10] = 32'h0000_2683;
        r_program[11] = 32'h0010_0713;
        r_program[12] = 32'h00e6_87b3;
        r_program[13] = 32'h00b0_0893;
        r_program[14] = 32'h0160_0913;
        r_program[15] = 32'h0128_8063;
        r_program[16] = 32'h0400_0993;
        r_program[17] = 32'h0009_8a67;
        r_program[18] = 32'h001a_0a93;

        tick();
        tick();
        @(negedge r_clock);
        r_reset = 1'b0;
        repeat (28) tick();

        check_word({23'd0, r_seen}, 32'h0000_01ff, "all forwarding paths observed");
        check_reg(5'd0, 32'd0);
        check_reg(5'd1, 32'd3);
        check_reg(5'd2, 32'd5);
        check_reg(5'd3, 32'd8);
        check_reg(5'd4, 32'd18);
        check_reg(5'd5, 32'd7);
        check_reg(5'd9, 32'd28);
        check_reg(5'd10, 32'd30);
        check_reg(5'd11, 32'd36);
        check_reg(5'd12, 32'd39);
        check_reg(5'd13, 32'd7);
        check_reg(5'd14, 32'd1);
        check_reg(5'd15, 32'd8);
        check_reg(5'd17, 32'd11);
        check_reg(5'd18, 32'd22);
        check_reg(5'd19, 32'd64);
        check_reg(5'd20, 32'd72);
        check_reg(5'd21, 32'd73);
        check_word(w_dbg_mem_data, 32'd7, "ADDI to SW memory word");
        check_word({31'd0, w_dbg_mem_dirty}, 32'd1, "ADDI to SW dirty");

        if (errors != 0)
            $fatal(1, "FAIL tb_forwarding_paths: %0d errors in %0d checks", errors, checks);
        $display("PASS tb_forwarding_paths: %0d checks", checks);
        $finish;
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module id_ex (
    input  wire        i_clock,
    input  wire        i_reset,
    input  wire        i_en,
    input  wire        i_flush,
    input  wire        i_stall,
    input  wire        i_valid,
    input  wire [31:0] i_pc,
    input  wire [31:0] i_rs1_data,
    input  wire [31:0] i_rs2_data,
    input  wire [31:0] i_imm,
    input  wire [4:0] i_rd,
    input  wire [4:0] i_rs1,
    input  wire [4:0] i_rs2,
    input  wire [2:0] i_funct3,
    input  wire [3:0] i_alu_op,
    input  wire        i_alu_src_b,
    input  wire        i_mem_read,
    input  wire        i_mem_write,
    input  wire        i_mem_to_reg,
    input  wire        i_reg_write,
    input  wire        i_branch,
    input  wire        i_jump,
    input  wire        i_jalr,
    input  wire        i_lui,
    input  wire        i_halt,
    input  wire        i_uses_rs1,
    input  wire        i_uses_rs2,
    output wire        o_valid,
    output wire [31:0] o_pc,
    output wire [31:0] o_rs1_data,
    output wire [31:0] o_rs2_data,
    output wire [31:0] o_imm,
    output wire [4:0] o_rd,
    output wire [4:0] o_rs1,
    output wire [4:0] o_rs2,
    output wire [2:0] o_funct3,
    output wire [3:0] o_alu_op,
    output wire        o_alu_src_b,
    output wire        o_mem_read,
    output wire        o_mem_write,
    output wire        o_mem_to_reg,
    output wire        o_reg_write,
    output wire        o_branch,
    output wire        o_jump,
    output wire        o_jalr,
    output wire        o_lui,
    output wire        o_halt,
    output wire        o_uses_rs1,
    output wire        o_uses_rs2,
    output wire [31:0] o_info
);

    reg r_valid;
    reg [31:0] r_pc;
    reg [31:0] r_rs1_data;
    reg [31:0] r_rs2_data;
    reg [31:0] r_imm;
    reg [4:0] r_rd;
    reg [4:0] r_rs1;
    reg [4:0] r_rs2;
    reg [2:0] r_funct3;
    reg [3:0] r_alu_op;
    reg r_alu_src_b;
    reg r_mem_read;
    reg r_mem_write;
    reg r_mem_to_reg;
    reg r_reg_write;
    reg r_branch;
    reg r_jump;
    reg r_jalr;
    reg r_lui;
    reg r_halt;
    reg r_uses_rs1;
    reg r_uses_rs2;

    assign o_valid = r_valid;
    assign o_pc = r_pc;
    assign o_rs1_data = r_rs1_data;
    assign o_rs2_data = r_rs2_data;
    assign o_imm = r_imm;
    assign o_rd = r_rd;
    assign o_rs1 = r_rs1;
    assign o_rs2 = r_rs2;
    assign o_funct3 = r_funct3;
    assign o_alu_op = r_alu_op;
    assign o_alu_src_b = r_alu_src_b;
    assign o_mem_read = r_mem_read;
    assign o_mem_write = r_mem_write;
    assign o_mem_to_reg = r_mem_to_reg;
    assign o_reg_write = r_reg_write;
    assign o_branch = r_branch;
    assign o_jump = r_jump;
    assign o_jalr = r_jalr;
    assign o_lui = r_lui;
    assign o_halt = r_halt;
    assign o_uses_rs1 = r_uses_rs1;
    assign o_uses_rs2 = r_uses_rs2;
    assign o_info = {
        r_halt, r_lui, r_jalr, r_jump, r_branch, r_reg_write,
        r_mem_to_reg, r_mem_write, r_mem_read, r_alu_src_b, r_alu_op,
        r_funct3, r_rs2, r_rs1, r_rd
    };

    always @(posedge i_clock) begin
        if (i_reset)
            r_valid <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_valid <= 1'd0;
            else if (!i_stall)
                r_valid <= i_valid;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_pc <= 32'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_pc <= i_pc;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_rs1_data <= 32'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_rs1_data <= i_rs1_data;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_rs2_data <= 32'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_rs2_data <= i_rs2_data;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_imm <= 32'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_imm <= i_imm;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_rd <= 5'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_rd <= i_rd;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_rs1 <= 5'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_rs1 <= i_rs1;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_rs2 <= 5'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_rs2 <= i_rs2;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_funct3 <= 3'd0;
        else if (i_en) begin
            if (!i_flush && !i_stall)
                r_funct3 <= i_funct3;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_alu_op <= 4'd0;
        else if (i_en) begin
            if (i_flush)
                r_alu_op <= 4'd0;
            else if (!i_stall)
                r_alu_op <= i_valid ? i_alu_op : 4'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_alu_src_b <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_alu_src_b <= 1'd0;
            else if (!i_stall)
                r_alu_src_b <= i_valid ? i_alu_src_b : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_mem_read <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_mem_read <= 1'd0;
            else if (!i_stall)
                r_mem_read <= i_valid ? i_mem_read : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_mem_write <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_mem_write <= 1'd0;
            else if (!i_stall)
                r_mem_write <= i_valid ? i_mem_write : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_mem_to_reg <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_mem_to_reg <= 1'd0;
            else if (!i_stall)
                r_mem_to_reg <= i_valid ? i_mem_to_reg : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_reg_write <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_reg_write <= 1'd0;
            else if (!i_stall)
                r_reg_write <= i_valid ? i_reg_write : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_branch <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_branch <= 1'd0;
            else if (!i_stall)
                r_branch <= i_valid ? i_branch : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_jump <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_jump <= 1'd0;
            else if (!i_stall)
                r_jump <= i_valid ? i_jump : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_jalr <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_jalr <= 1'd0;
            else if (!i_stall)
                r_jalr <= i_valid ? i_jalr : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_lui <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_lui <= 1'd0;
            else if (!i_stall)
                r_lui <= i_valid ? i_lui : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_halt <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_halt <= 1'd0;
            else if (!i_stall)
                r_halt <= i_valid ? i_halt : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_uses_rs1 <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_uses_rs1 <= 1'd0;
            else if (!i_stall)
                r_uses_rs1 <= i_valid ? i_uses_rs1 : 1'd0;
        end
    end

    always @(posedge i_clock) begin
        if (i_reset)
            r_uses_rs2 <= 1'd0;
        else if (i_en) begin
            if (i_flush)
                r_uses_rs2 <= 1'd0;
            else if (!i_stall)
                r_uses_rs2 <= i_valid ? i_uses_rs2 : 1'd0;
        end
    end

endmodule

`default_nettype wire

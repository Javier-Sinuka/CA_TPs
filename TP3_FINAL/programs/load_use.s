addi x8, x0, 73
addi x9, x0, 21
addi x10, x0, 96
sw x8, 0(x0)
sw x10, 4(x0)
addi x12, x0, 31
nop
nop

alu_both:
addi x1, x0, -1
lw x1, 0(x0)
add x2, x1, x1
nop
nop
nop
nop
nop

store_data:
addi x1, x0, -2
lw x1, 0(x0)
sw x1, 64(x0)
nop
nop
nop
nop
nop

store_base:
addi x1, x0, -3
lw x1, 4(x0)
sw x9, 4(x1)
nop
nop
nop
nop
nop

false_rs2:
addi x1, x0, -4
lw x1, 0(x0)
addi x3, x0, 1
nop
nop
nop
nop
nop

independent_alu:
addi x1, x0, -5
lw x1, 0(x0)
add x4, x9, x9
nop
nop
nop
nop
nop

branch_rs1_equal:
addi x1, x0, -6
lw x1, 0(x0)
beq x1, x8, 4
nop
nop
nop
nop
nop

branch_rs2_different:
addi x1, x0, -7
lw x1, 0(x0)
bne x9, x1, 4
nop
nop
nop
nop
nop

alu_rs2:
addi x1, x0, -8
lw x1, 0(x0)
add x5, x9, x1
nop
nop
nop
nop
nop

alu_rs1:
addi x1, x0, -9
lw x1, 0(x0)
addi x6, x1, 2
nop
nop
nop
nop
nop

load_x0:
addi x1, x0, -10
lw x0, 0(x0)
addi x7, x0, 0
nop
nop
nop
nop
nop

branch_rs1_different:
addi x1, x0, -11
lw x1, 0(x0)
beq x1, x9, 4
nop
nop
nop
nop
nop

branch_rs2_equal:
addi x1, x0, -12
lw x1, 0(x0)
bne x8, x1, 4
nop
nop
nop
nop
nop

store_both:
addi x1, x0, -13
lw x1, 4(x0)
sw x1, 8(x1)
nop
nop
nop
nop
nop

done:
addi x31, x0, 0x5a5

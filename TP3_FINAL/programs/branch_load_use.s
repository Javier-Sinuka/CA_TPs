addi x8, x0, 73
addi x9, x0, 21
sw x8, 0(x0)
sw x9, 4(x0)
addi x1, x0, -1
lw x1, 0(x0)
beq x1, x8, equal
sw x9, 8(x0)
jal x20, wrong
equal:
addi x2, x0, -2
lw x2, 4(x0)
bne x8, x2, different
sw x8, 8(x0)
jal x21, wrong
different:
addi x3, x0, -3
lw x3, 4(x0)
beq x3, x8, wrong
addi x10, x0, 1
addi x4, x0, -4
lw x4, 0(x0)
bne x8, x4, wrong
addi x11, x0, 2
addi x5, x0, 101
sw x5, 12(x0)
lw x6, 12(x0)
jalr x7, x6, 8
jal x22, wrong
add x12, x10, x11
sw x12, 16(x0)
jal x0, done
sw x8, 8(x0)
wrong:
addi x23, x0, 99
sw x8, 20(x0)
done:
addi x31, x0, 0x5a5

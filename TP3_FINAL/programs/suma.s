addi x1, x0, 0
addi x2, x0, 1
addi x3, x0, 11
loop:
add x1, x1, x2
addi x2, x2, 1
bne x2, x3, loop
sw x1, 0(x0)
addi x31, x0, 0x5a5

addi x1, x0, 1
bne x1, x0, target
halt
sw x1, 4(x0)
target:
addi x2, x0, 9
sw x2, 0(x0)
halt
addi x10, x0, 99
sw x1, 8(x0)
halt

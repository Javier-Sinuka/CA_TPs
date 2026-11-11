addi x10, x0, 3
jal ra, function
addi x11, ra, 0
beq x10, x0, wrong
bne x10, x0, chain
jal x20, wrong
sw x10, 4(x0)
chain:
jal x5, next
jal x21, wrong
sw x10, 4(x0)
next:
addi x6, x0, 65
jalr x7, x6, 0
jal x22, wrong
sw x10, 4(x0)
nop
nop
target:
addi x8, x7, 1
sw x8, 0(x0)
jal x0, done
addi x23, x0, 99
function:
addi x10, x10, 4
jalr x0, ra, 0
wrong:
sw x10, 8(x0)
addi x25, x0, 99
done:
addi x31, x0, 0x5a5
halt

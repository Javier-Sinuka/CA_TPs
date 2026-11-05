# Las 32 instrucciones de B-19, una vez cada una y en el orden de la tabla A; halt al final.
    add   x1, x2, x3
    sub   x4, x5, x6
    sll   x7, x8, x9
    slt   x10, x11, x12
    sltu  x13, x14, x15
    xor   x16, x17, x18
    srl   x19, x20, x21
    sra   x22, x23, x24
    or    x25, x26, x27
    and   x28, x29, x30
    addi  x1, x2, -123
    slti  x3, x4, 1000
    sltiu x5, x6, -1
    xori  x7, x8, -2048
    ori   x9, x10, 2047
    andi  x11, x12, 255
    slli  x13, x14, 5
    srli  x15, x16, 31
    srai  x17, x18, 7
    lb    x19, -4(x20)
    lh    x21, 6(x22)
    lw    x23, -2048(x24)
    lbu   x25, 2047(x26)
    lhu   x27, 100(x28)
    jalr  x29, 12(x30)
    sb    x1, -1(x2)
    sh    x3, 10(x4)
    sw    x5, -300(x6)
back:
    beq   x7, x8, fwd       # hacia adelante
    bne   x9, x10, back     # hacia atrás
fwd:
    jal   x31, done
    lui   x11, 0xABCDE
done:
    halt

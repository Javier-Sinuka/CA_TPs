# programa: alu_nodep.s
# cubre: tipo R e I sin dependencias (separadas por 2 nop), lui
# fase-A: 3
# expect: stop=halt pc=0x60 mem=none
# expect: x1=0x7 x2=0xfffffffd x3=0x4 x4=0xa x5=0x380 x6=0x1 x7=0x0
# expect: x8=0xfffffffa x9=0x01ffffff x10=0xffffffff x11=0xffffffff x12=0x5
# expect: x13=0xffffffff x14=0x1 x15=0x1 x16=0xf7 x17=0x107 x18=0x7fd
# expect: x19=0x70000000 x20=0xf x21=0xfffffffe x22=0xabcde000
        addi x1, x0, 7
        addi x2, x0, -3
        nop
        nop
        add  x3, x1, x2
        sub  x4, x1, x2
        sll  x5, x1, x1
        slt  x6, x2, x1
        sltu x7, x2, x1
        xor  x8, x1, x2
        srl  x9, x2, x1
        sra  x10, x2, x1
        or   x11, x1, x2
        and  x12, x1, x2
        addi x13, x1, -8
        slti x14, x2, -2
        sltiu x15, x1, -1
        xori x16, x1, 0xf0
        ori  x17, x1, 0x100
        andi x18, x2, 0x7ff
        slli x19, x1, 28
        srli x20, x2, 28
        srai x21, x2, 1
        lui  x22, 0xabcde
        halt

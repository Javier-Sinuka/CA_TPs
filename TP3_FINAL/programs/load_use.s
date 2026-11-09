# programa: load_use.s
# cubre: lw seguido de su consumidor como ALU, dato de store, branch y dirección base
# fase-A: 5
# expect: stop=halt pc=0x3c
# expect: x1=0x2a x2=0x8 x3=0x2a x4=0x2b x5=0x8 x6=0x2a x7=0x0 x8=0x8 x9=0x10 x10=0x8 x11=0x6c
# expect: mem[0x0]=0x2a mem[0x4]=0x8 mem[0x8]=0x8
        addi x1, x0, 42       # i0
        sw   x1, 0(x0)        # i1
        addi x2, x0, 8        # i2
        sw   x2, 4(x0)        # i3
        lw   x3, 0(x0)        # i4
        addi x4, x3, 1        # i5  load-use: ALU
        lw   x5, 4(x0)        # i6
        sw   x5, 8(x0)        # i7  load-use: dato de store
        lw   x6, 0(x0)        # i8
        beq  x6, x1, ok       # i9  load-use: branch (tomado)
        addi x7, x0, 1        # i10 no se ejecuta
ok:     lw   x8, 4(x0)        # i11
        add  x9, x8, x8       # i12
        lw   x10, 0(x8)       # i13 load-use: dirección base (lee mem[8])
        addi x11, x10, 100    # i14
        halt                  # i15

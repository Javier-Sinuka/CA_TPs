# programa: mem_bytes.s
# cubre: sb/sh/lb/lbu/lh/lhu en todos los offsets, lw desalineado (D-18)
# fase-A: 2
# rars-ignore: x17
# expect: stop=halt pc=0x60
# expect: x1=0x80 x2=0xffffff80 x3=0x80 x4=0xffffff80 x5=0x80 x6=0xffffff80 x7=0x80
# expect: x8=0xffffff80 x9=0x80 x10=0x8001 x11=0xffff8001 x12=0x8001 x13=0xffff8001
# expect: x14=0x8001 x15=0x8000 x16=0x80010000 x17=0x8000
# expect: mem[0x0]=0x80 mem[0x4]=0x8000 mem[0x8]=0x800000 mem[0xc]=0x80000000
# expect: mem[0x10]=0x8001 mem[0x14]=0x80010000
        addi x1, x0, 0x80     # i0
        sb   x1, 0(x0)        # i1  palabra 0, byte 0
        sb   x1, 5(x0)        # i2  palabra 1, byte 1
        sb   x1, 10(x0)       # i3  palabra 2, byte 2
        sb   x1, 15(x0)       # i4  palabra 3, byte 3
        lb   x2, 0(x0)        # i5
        lbu  x3, 0(x0)        # i6
        lb   x4, 5(x0)        # i7
        lbu  x5, 5(x0)        # i8
        lb   x6, 10(x0)       # i9
        lbu  x7, 10(x0)       # i10
        lb   x8, 15(x0)       # i11
        lbu  x9, 15(x0)       # i12
        lui  x10, 0x8         # i13
        addi x10, x10, 1      # i14 x10 = 0x8001
        sh   x10, 16(x0)      # i15 palabra 4, mitad baja
        sh   x10, 22(x0)      # i16 palabra 5, mitad alta
        lh   x11, 16(x0)      # i17
        lhu  x12, 16(x0)      # i18
        lh   x13, 22(x0)      # i19
        lhu  x14, 22(x0)      # i20
        lw   x15, 4(x0)       # i21
        lw   x16, 20(x0)      # i22
        lw   x17, 6(x0)       # i23 desalineado: lee la palabra 1
        halt                  # i24

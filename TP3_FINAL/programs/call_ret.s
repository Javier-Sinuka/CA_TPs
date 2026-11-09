# programa: call_ret.s
# cubre: jal/jalr, función recursiva con pila, llamada a la instrucción siguiente
# fase-A: 6
# rars-ignore: x1, x3
# expect: stop=halt pc=0x18 x1=0x14 x2=0x400 x5=0x1 x6=0x5 x10=0xf
# expect: mem[0x0]=0xf mem[0x3d8]=0x1 mem[0x3dc]=0x38 mem[0x3e0]=0x2 mem[0x3e4]=0x38
# expect: mem[0x3e8]=0x3 mem[0x3ec]=0x38 mem[0x3f0]=0x4 mem[0x3f4]=0x38 mem[0x3f8]=0x5 mem[0x3fc]=0xc
        addi sp, x0, 1024     # i0  tope de dmem
        addi a0, x0, 5        # i1  n
        jal  ra, sum_rec      # i2
        sw   a0, 0(x0)        # i3  15
        jal  ra, next         # i4  llamada a la instrucción siguiente
next:   addi t0, x0, 1        # i5
        halt                  # i6
# sum_rec(n) = n + sum_rec(n - 1); sum_rec(0) = 0
sum_rec:
        bne  a0, x0, rec      # i7
        jalr x0, 0(ra)        # i8
rec:    addi sp, sp, -8       # i9
        sw   ra, 4(sp)        # i10
        sw   a0, 0(sp)        # i11
        addi a0, a0, -1       # i12
        jal  ra, sum_rec      # i13
        lw   t1, 0(sp)        # i14
        lw   ra, 4(sp)        # i15
        addi sp, sp, 8        # i16
        add  a0, a0, t1       # i17
        ret                   # i18

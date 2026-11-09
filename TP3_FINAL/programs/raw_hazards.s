# programa: raw_hazards.s
# cubre: RAW a distancia 1, 2 y 3 en rs1 y rs2; doble dependencia (gana EX/MEM); escritura a x0; dato de store forwardeado
# fase-A: 4
# expect: stop=halt pc=0x48
# expect: x1=0x5 x2=0x6 x3=0x6 x4=0x5 x5=0x6 x6=0xa x7=0x14 x8=0x1e x9=0xa
# expect: x10=0x4 x11=0x8 x12=0x0 x13=0x4d
# expect: mem[0x0]=0x1e mem[0x4]=0x4d
        addi x1, x0, 5        # i0
        addi x2, x1, 1        # i1  rs1 a distancia 1
        add  x3, x0, x2       # i2  rs2 a distancia 1
        add  x4, x1, x0       # i3  rs1 a distancia 3 (bypass del banco)
        add  x5, x0, x2       # i4  rs2 a distancia 3
        addi x6, x0, 10       # i5
        addi x7, x0, 20       # i6
        add  x8, x6, x7       # i7  rs1 distancia 2, rs2 distancia 1
        sub  x9, x7, x6       # i8  rs1 distancia 2, rs2 distancia 3
        addi x10, x0, 1       # i9
        add  x10, x10, x10    # i10 = 2
        add  x10, x10, x10    # i11 = 4: EX/MEM gana sobre MEM/WB
        add  x11, x10, x10    # i12 = 8
        addi x0, x0, 99       # i13 escritura a x0
        add  x12, x0, x0      # i14 no se forwardea x0
        sw   x8, 0(x0)        # i15
        addi x13, x0, 77      # i16
        sw   x13, 4(x0)       # i17 dato del store a distancia 1
        halt                  # i18

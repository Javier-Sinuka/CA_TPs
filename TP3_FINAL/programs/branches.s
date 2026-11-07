# programa: branches.s
# cubre: saltos tomados y no tomados seguidos, jal incondicional, HALT detrás de un salto tomado, salto como última instrucción antes de HALT
# fase-A: 6
# expect: stop=halt pc=0x44 mem=none
# expect: x1=0x1 x2=0x2 x3=0x3 x4=0x4 x5=0x5 x10=0x0 x11=0x0 x12=0x0 x13=0x0
        addi x1, x0, 1        # i0
        addi x2, x0, 2        # i1
        beq  x1, x2, bad      # i2  no tomado
        bne  x1, x2, tk1      # i3  tomado
        addi x10, x0, 99      # i4  anulada
        addi x11, x0, 99      # i5  anulada
tk1:    beq  x1, x1, tk2      # i6  tomado, justo después de otro salto
bad:    addi x12, x0, 99      # i7  nunca se ejecuta
tk2:    bne  x1, x1, bad      # i8  no tomado
        addi x3, x0, 3        # i9
        jal  x0, tk3          # i10
        addi x13, x0, 99      # i11 anulada
tk3:    addi x4, x0, 4        # i12
        beq  x0, x0, skip     # i13
        halt                  # i14 no debe parar: lo anula el salto anterior
skip:   addi x5, x0, 5        # i15
        beq  x5, x5, end      # i16 salto a la instrucción siguiente
end:    halt                  # i17

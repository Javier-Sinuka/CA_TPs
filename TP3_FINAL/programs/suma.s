# programa: suma.s
# cubre: bucle con bne y dependencia a distancia 1 (hoja de ruta)
# fase-A: 6
# expect: stop=halt pc=0x1c x1=0x37 x2=0xb x3=0xb mem[0x0]=0x37
        addi x1, x0, 0        # acumulador
        addi x2, x0, 1        # i = 1
        addi x3, x0, 11       # límite
loop:   add  x1, x1, x2       # acc += i
        addi x2, x2, 1        # i++
        bne  x2, x3, loop
        sw   x1, 0(x0)
        halt

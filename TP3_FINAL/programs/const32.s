# programa: const32.s
# cubre: li de 1 y 2 palabras, redondeo de hi/lo, lui con bit 31
# fase-A: 3
# expect: stop=halt pc=0x34 mem=none
# expect: x1=0x12345fff x2=0x800 x3=0xfffff800 x4=0x7fffffff x5=0xffffffff
# expect: x6=0x12345678 x7=0x0 x8=0xfffff000 x9=0xfffff7ff
        li   x1, 0x12345FFF   # 2 palabras (pc 0x00)
        li   x2, 0x00000800   # 2 palabras (pc 0x08)
        li   x3, 0xFFFFF800   # 1 palabra  (pc 0x10)
        li   x4, 0x7FFFFFFF   # 2 palabras (pc 0x14)
        li   x5, -1           # 1 palabra  (pc 0x1c)
        li   x6, 0x12345678   # 2 palabras (pc 0x20)
        li   x7, 0            # 1 palabra  (pc 0x28)
        lui  x8, 0xfffff      # pc 0x2c
        addi x9, x8, 0x7ff    # pc 0x30
        halt                  # pc 0x34

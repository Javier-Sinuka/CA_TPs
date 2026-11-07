# programa: no_halt.s
# cubre: programa que nunca llega a HALT (timeout de R y límite del ISS)
# fase-A: 7
# rars: no
# expect: stop=limit
        addi x1, x0, 0
loop:   addi x1, x1, 1
        j    loop

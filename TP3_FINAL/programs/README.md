# Programas de prueba

Nueve programas con resultado esperado. Los usan A (Fases 3 a 7), la Fase 10, `stub_model`/`FakeBoard`, `tb_system_prog` y la demo.

| Programa | Cubre | Fase de A | Valores clave | RARS |
| --- | --- | --- | --- | --- |
| `alu_nodep` | tipo R e I sin dependencias (separadas por 2 `nop`), `lui` | 3 | `pc=0x60`, sin escrituras a memoria, `x22=0xabcde000` | sí |
| `raw_hazards` | RAW a distancia 1, 2 y 3 en `rs1` y `rs2`; doble dependencia; escritura a `x0`; dato de store forwardeado | 4 | `pc=0x48`, `x8=0x1e`, `x13=0x4d`, `mem[0x0]=0x1e`, `mem[0x4]=0x4d` | sí |
| `load_use` | `lw` seguido de su consumidor como ALU, dato de store, branch y dirección base | 5 | `pc=0x3c`, `x4=0x2b`, `x11=0x6c`, `mem[0x8]=0x8` | sí |
| `mem_bytes` | `sb`/`sh`/`lb`/`lbu`/`lh`/`lhu` en todos los offsets, `lw` desalineado (D-18) | 2 | `pc=0x60`, `x16=0x80010000`, `x17=0x8000` | sí, sin `x17` |
| `suma` | bucle con `bne` y dependencia a distancia 1 | 6 | `pc=0x1c`, `x1=0x37`, `mem[0x0]=0x37` | sí |
| `call_ret` | `jal`/`jalr`, función recursiva con pila, llamada a la instrucción siguiente | 6 | `pc=0x18`, `x10=0xf`, `mem[0x3fc]=0xc` | sí, sin `x1` y `x3` |
| `branches` | saltos tomados y no tomados seguidos, `jal`, HALT detrás de un salto tomado | 6 | `pc=0x44`, sin escrituras a memoria, `x5=0x5` | sí |
| `const32` | `li` de 1 y 2 palabras, redondeo de hi/lo, `lui` con bit 31 | 3 | `pc=0x34`, `x1=0x12345fff`, `x9=0xfffff7ff` | sí |
| `no_halt` | nunca llega a HALT (timeout de `R` y límite del ISS) | 7 | `stop=limit` | no |

## Archivos

Cada `<nombre>.s` genera `<nombre>.hex`, `<nombre>.bin` y `<nombre>.expected.json` (formato canónico de `dump.md` §6). Los cuatro se versionan. La cabecera de cada `.s` (`# programa`, `# cubre`, `# fase-A`, `# expect`, `# rars-ignore`, `# rars: no`) la lee `sw/tests/test_programs.py`.

## Regenerar

```
py TP3_FINAL/tools/gen_expected.py
```

Ensambla cada `.s` con `asm.rvasm`, corre `build/iss.exe` y reescribe los tres archivos generados. Después de regenerar, `git status TP3_FINAL/programs` no debe mostrar cambios.

Un `.expected.json` solo se cambia si la línea `# expect:` del `.s` lo respalda. Si no coinciden, uno de los dos está mal: se revisa a mano la instrucción y, si el error está en el ISS, se corrige el ISS en un commit propio.

## Comparación con RARS

`py TP3_FINAL/tools/rars_ref.py regs <prog.s> -o <out.json>` corre el programa en RARS 1.6 (`mc CompactDataAtZero`) y devuelve `x1..x31`; el test compara contra el ISS salvo los registros de `# rars-ignore:`. Casos que RARS resuelve distinto del ISS:

- `x1` en `call_ret`: RARS carga el texto en `0x3000`, así que las direcciones de retorno difieren.
- `x3` en `call_ret`: RARS arranca con `gp = 0x1800` (y `sp = 0x2ffc`); el ISS arranca con todo en 0. El programa no escribe `x3`.
- `x17` en `mem_bytes`: el `lw` desalineado es una excepción en RARS (termina con `Load address not aligned…`), mientras que el ISS ignora los bits bajos (D-18). `regs` copia el aviso de RARS a stderr y sigue.
- `branches` usa las etiquetas `tk1`, `tk2` y `tk3` porque `t1`, `t2` y `t3` son nombres de registros para RARS.
- `no_halt` no se compara con RARS (no termina).

# B-22 · Programas de prueba con resultado esperado

`M` · etiquetas `test` `bloquea-A` · milestone M3 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

Nueve programas en `TP3_FINAL/programs/` con `.hex`, `.bin` y `.expected.json` generados por el ISS y verificados contra valores calculados a mano; los usan A (Fases 3 a 7), la Fase 10, B-24, B-27 y la demo.

## Antes de empezar

- Leer: [`dump.md`](../../../TP3_FINAL/doc/documentation/dump.md) §6 (formato canónico); [B-19](B-19-ensamblador.md) §B y §C; [B-21](B-21-golden-model.md) pasos 2, 3 y 6.
- Precondiciones: B-19 y B-21 cerrados; B-07 cerrado (existe `sw/host/dump.py`). Comprobar: `py TP3_FINAL/tools/run.py test` → código 0.
- Rama: `b/B-22-programas`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/programs/<nombre>.s` (9) | Código de §A, literal |
| crear (generado, se versiona) | `TP3_FINAL/programs/<nombre>.hex`, `.bin`, `.expected.json` | Paso 3 |
| crear | `TP3_FINAL/programs/README.md` | Paso 5 |
| crear | `TP3_FINAL/tools/gen_expected.py` | Paso 3 |
| no tocar | `TP3_FINAL/sw/host/canonical.py` | Ya existe (B-07): `load`, `from_dump`, `diff`, `save` |
| crear | `TP3_FINAL/sw/tests/test_programs.py` | Paso 4 |

## A. Programas (copiar literal)

Cabecera obligatoria de cada archivo (la lee el test):

```
# programa: <nombre>.s
# cubre: <una línea>
# fase-A: <número>
# expect: <clave>=<valor> ...      (una o más líneas)
# rars-ignore: <registros>          (opcional)
# rars: no                          (opcional; excluye el programa de la comparación con RARS)
```

Claves de `expect`: `stop=halt|limit`, `pc=0x…`, `xN=0x…`, `mem[0x…]=0x…`, `mem=none` (no hay palabras escritas). Los valores se comparan como enteros.

### `alu_nodep.s`

```
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
```

### `raw_hazards.s`

```
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
```

### `load_use.s`

```
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
```

### `mem_bytes.s`

```
# programa: mem_bytes.s
# cubre: sb/sh/lb/lbu/lh/lhu en todos los offsets, lw desalineado (D-18)
# fase-A: 2
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
```

### `suma.s`

```
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
```

### `call_ret.s`

```
# programa: call_ret.s
# cubre: jal/jalr, función recursiva con pila, llamada a la instrucción siguiente
# fase-A: 6
# rars-ignore: x1
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
```

El ensamblador agrega un HALT inalcanzable después de `ret` (pc 0x4c); el que para es el de pc 0x18.

### `branches.s`

```
# programa: branches.s
# cubre: saltos tomados y no tomados seguidos, jal incondicional, HALT detrás de un salto tomado, salto como última instrucción antes de HALT
# fase-A: 6
# expect: stop=halt pc=0x44 mem=none
# expect: x1=0x1 x2=0x2 x3=0x3 x4=0x4 x5=0x5 x10=0x0 x11=0x0 x12=0x0 x13=0x0
        addi x1, x0, 1        # i0
        addi x2, x0, 2        # i1
        beq  x1, x2, bad      # i2  no tomado
        bne  x1, x2, t1       # i3  tomado
        addi x10, x0, 99      # i4  anulada
        addi x11, x0, 99      # i5  anulada
t1:     beq  x1, x1, t2       # i6  tomado, justo después de otro salto
bad:    addi x12, x0, 99      # i7  nunca se ejecuta
t2:     bne  x1, x1, bad      # i8  no tomado
        addi x3, x0, 3        # i9
        jal  x0, t3           # i10
        addi x13, x0, 99      # i11 anulada
t3:     addi x4, x0, 4        # i12
        beq  x0, x0, skip     # i13
        halt                  # i14 no debe parar: lo anula el salto anterior
skip:   addi x5, x0, 5        # i15
        beq  x5, x5, end      # i16 salto a la instrucción siguiente
end:    halt                  # i17
```

### `const32.s`

```
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
```

### `no_halt.s`

```
# programa: no_halt.s
# cubre: programa que nunca llega a HALT (timeout de R y límite del ISS)
# fase-A: 7
# rars: no
# expect: stop=limit
        addi x1, x0, 0
loop:   addi x1, x1, 1
        j    loop
```

## Pasos

1. Crear los 9 `.s` copiando §A literal.

2. `sw/host/canonical.py` ya existe (B-07, con sus tests). Usar `canonical.load`, `canonical.diff` y `canonical.save` tal cual; **no** reescribirlo. Si algo de este issue no encaja con su API, detenerse y preguntar.

3. `tools/gen_expected.py` (corre desde la raíz del repo): compila `build/iss.exe` igual que `conftest.build_iss()`; para cada `TP3_FINAL/programs/*.s` en orden alfabético: `py -m asm.rvasm <s> -o TP3_FINAL/programs` (con `cwd = TP3_FINAL/sw`), luego `build/iss.exe <hex> -o <base>.expected.json`; imprime `<nombre>: <stop> pc=<pc>`. Correrlo: `py TP3_FINAL/tools/gen_expected.py`.

4. `sw/tests/test_programs.py`, parametrizado por los 9 `.s`:
   - **Al día:** `assemble(src)` == palabras del `.hex` versionado, y `to_bin()` == `.bin` versionado.
   - **ISS reproduce:** correr `iss.exe` (fixture `iss_exe`) sobre el `.hex` en `tmp_path` y comparar con `canonical.load(expected)`: `diff(...) == []`.
   - **Valores a mano:** parsear las líneas `# expect:` y verificar cada una contra `.expected.json` (`mem=none` ↔ `mem == []`).
   - **RARS** (skip si no hay jar o si el programa tiene `# rars: no`): `tools/rars_ref.py regs` y comparar `x1..x31` salvo los de `ignore`.
   - **Cantidad:** existen exactamente estos 9 programas: `alu_nodep branches call_ret const32 load_use mem_bytes no_halt raw_hazards suma`.

5. `programs/README.md`: tabla con columnas `Programa | Cubre | Fase de A | Valores clave | RARS` (de la cabecera de cada `.s`), y debajo: cómo regenerar (`py TP3_FINAL/tools/gen_expected.py`), que `.hex`/`.bin`/`.expected.json` se versionan y que un `.expected.json` solo se cambia si la línea `# expect:` lo respalda.

## Validación

```
py TP3_FINAL/tools/gen_expected.py      → 9 líneas; no_halt: limit, el resto halt con el pc de su cabecera
cd TP3_FINAL/sw && py -m pytest -q tests/test_programs.py   → todos pasan
git status TP3_FINAL/programs           → después de regenerar, sin cambios (los generados están al día)
```

## Listo cuando

- [ ] Los 9 programas ensamblan, corren en el ISS y su `.expected.json` cumple todas sus líneas `# expect:`.
- [ ] La comparación con RARS pasa en los 8 programas sin `rars: no` (o el fallback de B-21 está anotado en `programs/README.md`).
- [ ] A recibió `programs/` y confirmó por escrito (comentario en el PR) que cubren lo que necesita.

## No hacer

- No "arreglar" una línea `# expect:` para que coincida con el ISS. Si no coinciden, uno de los dos está mal: revisar a mano la instrucción, y si el error está en el ISS, corregir el ISS (B-21) en un commit propio.
- No agregar programas fuera de estos 9.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `pc` de HALT distinto al de la cabecera | Contar palabras: `li` de 2 palabras (B-19 §C) desplaza las direcciones |
| RARS difiere solo en `x1` en un programa con `jal` | Falta `rars-ignore: x1` en la cabecera; agregarlo solo si el valor del ISS coincide con la cabecera |
| RARS cuelga en `no_halt.s` | Debe estar excluido con `# rars: no` |

## Commits

1. `programs: nueve programas de prueba`
2. `programs: resultados esperados generados por el ISS`

## Depende de / bloquea

Depende de: B-07 (`dump.py`), B-19, B-21. Bloquea: B-24, B-27, B-28 y la verificación de A (Fases 2 a 7, 10).

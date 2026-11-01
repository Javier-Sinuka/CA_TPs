# B-21 · Golden model en C++

`M` · etiquetas `sw-iss` `bloquea-A` · milestone M3 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

`build/iss.exe` ejecuta un `.hex` con la misma semántica que el CPU de A y escribe el estado final en el formato canónico de [`dump.md`](../../../TP3_FINAL/doc/documentation/dump.md) §6.

## Antes de empezar

- Leer: [`dump.md`](../../../TP3_FINAL/doc/documentation/dump.md) §6; [`interfaz_cpu.md`](../../../TP3_FINAL/doc/documentation/interfaz_cpu.md) §3, §4, §5; [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §6; [B-19](B-19-ensamblador.md) §A (codificación).
- Precondiciones: B-18 cerrado. B-19 no hace falta para el C++, sí para el paso 6.
- Rama: `b/B-21-golden-model`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/iss/iss.hpp` | API (paso 1) |
| crear | `TP3_FINAL/sw/iss/iss.cpp` | Semántica (paso 2) |
| crear | `TP3_FINAL/sw/iss/iss_main.cpp` | CLI (paso 3) |
| crear | `TP3_FINAL/sw/iss/test_iss.cpp` | Tests unitarios (paso 4) |
| crear | `TP3_FINAL/sw/tests/test_iss_cli.py` | Test de la CLI desde pytest (paso 5) |
| modificar | `TP3_FINAL/tools/rars_ref.py` | Modo `regs` (paso 6) |

## Pasos

1. **API** (`iss.hpp`):

   ```cpp
   #pragma once
   #include <cstdint>
   #include <string>

   constexpr uint32_t HALT_WORD  = 0x00000073u;
   constexpr int      IMEM_WORDS = 256;
   constexpr int      DMEM_WORDS = 256;

   struct IssState {
       uint32_t x[32];
       uint32_t pc;
       uint32_t imem[IMEM_WORDS];
       uint32_t dmem[DMEM_WORDS];
       bool     written[DMEM_WORDS];   // palabra escrita al menos una vez
       uint64_t instret;               // instrucciones ejecutadas (HALT no cuenta)
   };

   enum class Stop { Halt, Limit };

   void iss_reset(IssState& s);                                   // x=0, pc=0, dmem=0, written=false, instret=0, imem toda en HALT
   bool iss_load_hex(IssState& s, const std::string& path, std::string& err);
   bool iss_step(IssState& s);                                    // false si la instrucción en pc es HALT (no la ejecuta)
   Stop iss_run(IssState& s, uint64_t max_instr);
   std::string iss_to_json(const IssState& s, Stop stop, bool full);
   ```

2. **Semántica exacta** (`iss.cpp`):

   - `iss_load_hex`: lee líneas; ignora vacías y las que empiezan con `//`; cada línea es una palabra de hasta 8 dígitos hex. Carga desde `imem[0]`. Más de 256 palabras → `err = "más de 256 palabras"` y `false`. Línea inválida → `err = "línea N inválida"` y `false`. El resto de imem queda en HALT (D-20).
   - Fetch: `ins = imem[(pc >> 2) & 255]`.
   - `iss_step`: si `ins == HALT_WORD` devuelve `false` sin tocar nada. Si no, ejecuta, `instret++`, `x[0] = 0`, devuelve `true`.
   - `iss_run(max)`: bucle: si `ins == HALT_WORD` → `Stop::Halt`; si `instret == max` → `Stop::Limit`; si no `iss_step`. (Con `max = k`, un HALT que sigue a la k-ésima instrucción se informa como `Halt`.)
   - Aritmética en `uint32_t`; con signo solo donde se indica. Shifts usan `& 31`.
   - Escribir esta función **exactamente así** (B-27 la muta buscando el marcador):

     ```cpp
     static uint32_t op_sra(uint32_t a, uint32_t sh) { return (uint32_t)((int32_t)a >> (sh & 31)); } // MUT:sra
     ```

     y usarla en `sra` y `srai`.
   - `slt`/`slti`: comparación `(int32_t)`; `sltu`/`sltiu`: `uint32_t`, con el inmediato extendido con signo antes de comparar.
   - Dirección efectiva `ea = x[rs1] + imm`. Índice de palabra `w = (ea >> 2) & 255` (la dirección da la vuelta, D-17).
   - **Desalineados (D-18):** `lw`/`sw` ignoran `ea[1:0]`; `lh`/`lhu`/`sh` usan la media palabra `(ea >> 1) & 1`, ignorando `ea[0]`; `lb`/`lbu`/`sb` usan el byte `ea & 3`. Little-endian: byte `k` = bits `[8k+7:8k]`.
   - Store: modifica solo los bytes del tamaño y pone `written[w] = true`. Como dmem arranca en 0 (equivale a "palabra limpia se lee 0" de `interfaz_cpu.md` §4), no hace falta otra cosa.
   - `jal`: `x[rd] = pc + 4`; `pc = pc + imm`. `jalr`: `t = (x[rs1] + imm) & ~1u`; `x[rd] = pc + 4`; `pc = t` (calcular `t` **antes** de escribir `rd`, por si `rd == rs1`).
   - `beq`/`bne`: `pc = pc + imm` si se toma, si no `pc + 4`.
   - `lui`: `x[rd] = imm_u` (bits `[31:12]` de la instrucción, ceros abajo).
   - Instrucción fuera del subconjunto: imprime en `stderr` `iss: instrucción ilegal 0x%08x en pc 0x%08x` y se comporta como `nop` (`pc += 4`, cuenta en `instret`). Ningún programa de B-22 la contiene.
   - `iss_to_json` (formato canónico exacto, una clave por línea, `x` en una sola línea, hex de 8 dígitos en minúsculas):

     ```
     {
       "stop": "halt",
       "pc": "0x0000001c",
       "x": ["0x00000000", "0x00000037", ...],
       "mem": [["0x00000000", "0x00000037"]]
     }
     ```

     `pc` es la dirección del HALT si `Halt`; `null` si `Limit`. `mem`: las palabras con `written`, ascendente por dirección en bytes (`w*4`), `[]` si no hay. Con `full = true` agrega antes de la `}` final: `"instret": N` y `"next_pc": "0x…"` (el `pc` actual, se haya detenido o no).

3. **CLI** (`iss_main.cpp`):

   ```
   build/iss.exe <prog.hex> [-o <out.json>] [--max-instr N] [--full]
   ```

   Default `--max-instr 1000000`. Sin `-o`, escribe el JSON en stdout. Códigos de salida: 0 si terminó (`Halt` o `Limit`), 2 si hubo error de argumentos o de lectura (mensaje en stderr).

4. **Tests unitarios** (`test_iss.cpp`): `main` propio con un macro `CHECK(cond)` que imprime `FAIL <archivo>:<línea>: <cond>` y cuenta; al final imprime `PASS test_iss: N chequeos` o sale con 1. Codificadores en el test (no depende del ensamblador de Python):

   ```cpp
   static uint32_t R(uint32_t f7,uint32_t rs2,uint32_t rs1,uint32_t f3,uint32_t rd,uint32_t op){return f7<<25|rs2<<20|rs1<<15|f3<<12|rd<<7|op;}
   static uint32_t I(int32_t imm,uint32_t rs1,uint32_t f3,uint32_t rd,uint32_t op){return ((uint32_t)imm&0xFFF)<<20|rs1<<15|f3<<12|rd<<7|op;}
   static uint32_t S(int32_t imm,uint32_t rs2,uint32_t rs1,uint32_t f3){uint32_t u=(uint32_t)imm;return ((u>>5)&0x7F)<<25|rs2<<20|rs1<<15|f3<<12|(u&0x1F)<<7|0x23;}
   static uint32_t B(int32_t imm,uint32_t rs2,uint32_t rs1,uint32_t f3){uint32_t u=(uint32_t)imm;return ((u>>12)&1)<<31|((u>>5)&0x3F)<<25|rs2<<20|rs1<<15|f3<<12|((u>>1)&0xF)<<8|((u>>11)&1)<<7|0x63;}
   static uint32_t U(uint32_t imm20,uint32_t rd){return imm20<<12|rd<<7|0x37;}
   static uint32_t J(int32_t imm,uint32_t rd){uint32_t u=(uint32_t)imm;return ((u>>20)&1)<<31|((u>>1)&0x3FF)<<21|((u>>11)&1)<<20|((u>>12)&0xFF)<<12|rd<<7|0x6F;}
   ```

   Cada test arma `imem` con un vector de palabras terminado en `HALT_WORD`, hace `iss_reset`, copia, `iss_run(s, 1000)` y compara. Casos obligatorios con su valor esperado:

   | Caso | Programa | Esperado |
   | --- | --- | --- |
   | `sra` negativo | `x1 = -16` (addi), `x2 = 2`, `sra x3,x1,x2` | `x3 = 0xfffffffc` |
   | `srai` 31 | `x1 = -1`, `srai x3,x1,31` | `x3 = 0xffffffff` |
   | `srl` negativo | `x1 = -16`, `x2 = 2`, `srl x3,x1,x2` | `x3 = 0x3ffffffc` |
   | `slt` vs `sltu` | `x1 = lui 0x80000` (0x80000000), `x2 = 1`; `slt x3,x1,x2`; `sltu x4,x1,x2` | `x3 = 1`, `x4 = 0` |
   | `sltiu` con −1 | `x1 = 5`; `sltiu x3,x1,-1` | `x3 = 1` |
   | escribir x0 | `addi x0,x0,5`; `add x3,x0,x0` | `x0 = 0`, `x3 = 0` |
   | `lb`/`lbu` 4 offsets | `x1 = 0x80`; `sb x1,k(x0)` y `lb x(10+k),k(x0)`, `lbu x(20+k),k(x0)` para k = 0..3 | `x10..x13 = 0xffffff80`, `x20..x23 = 0x00000080`, `mem[0] = 0x80808080` |
   | `lh`/`lhu` | `x1 = lui 8` + `addi 1` (0x8001); `sh x1,2(x0)`; `lh x3,2(x0)`; `lhu x4,2(x0)` | `x3 = 0xffff8001`, `x4 = 0x00008001`, `mem[0] = 0x80010000` |
   | desalineado `lw` | `x1 = 0x55`; `sw x1,4(x0)`; `lw x3,6(x0)` | `x3 = 0x55` |
   | desalineado `sh` | `x1 = 0x1234`… con `lui`/`addi`; `sh x1,1(x0)`; `lw x3,0(x0)` | `x3 = 0x00001234` |
   | vuelta de dirección | `x1 = 0x55`; `sw x1,1024(x0)` (1024 entra en el inmediato I/S); `lw x3,0(x0)` | `x3 = 0x55`, `mem` lista solo `0x00000000` |
   | `jalr` bit 0 | `x1 = 9` (addi); `jalr x5,0(x1)` en pc 4; en pc 8 `HALT`… (ver nota) | `pc` final = 8, `x5 = 8` |
   | `jalr` con `rd == rs1` | `x1 = 12`; `jalr x1,0(x1)` en pc 4 | `x1 = 8`, ejecución sigue en 12 |
   | `jal` | `jal x1, 8` en pc 0 | `x1 = 4`, pc = 8 |
   | `beq`/`bne` | tomado y no tomado | pc correspondiente |
   | `lui` + `addi` redondeo | `lui x1,0x12346`; `addi x1,x1,-1` | `x1 = 0x12345fff` |
   | límite | `jal x0, 0` (bucle) con `max = 10` | `Stop::Limit`, `instret = 10` |
   | HALT inicial | imem vacía | `Stop::Halt`, `pc = 0`, `instret = 0` |
   | JSON | programa `suma` (hoja de ruta) | `iss_to_json` contiene exactamente `"pc": "0x0000001c"` y `["0x00000000", "0x00000037"]` |

   Nota `jalr` bit 0: programa `[addi x1,x0,9 ; jalr x5,0(x1) ; HALT ; ...]`: el destino `9 & ~1 = 8` es el HALT de pc 8; `x5 = 8` (pc 4 + 4). Esperado: `Halt` con `pc = 8`.

5. **Test de CLI** (`sw/tests/test_iss_cli.py`, usa la fixture `iss_exe` de `conftest.py`): escribe en `tmp_path` el `.hex` de `suma` (palabras de B-22 o ensambladas con `asm.rvasm`), corre `iss.exe x.hex -o out.json` y verifica con `json.load` `stop == "halt"`, `pc == "0x0000001c"`, `x[1] == "0x00000037"`, `mem == [["0x00000000", "0x00000037"]]`; corre con `--max-instr 3 --full` y verifica `stop == "limit"`, `pc is None`, `instret == 3`, `next_pc == "0x0000000c"`.

6. **Comparación con RARS** (`tools/rars_ref.py regs <prog.s> -o <out.json>`), para B-22:
   1. Copia a `build/rars/<base>_regs.s` reemplazando cada `halt` por `j __rars_end` y agregando al final la línea `__rars_end:` (sin instrucción después: RARS termina "cayéndose" del final del programa).
   2. Corre `java -jar TP3_FINAL/tools/rars1_6.jar nc mc CompactDataAtZero x1 x2 … x31 build/rars/<base>_regs.s` (los 31 nombres explícitos).
   3. Parsea las líneas con la regex `^(x\d+)\s+(0x[0-9a-fA-F]{8})` y escribe `{"x": [...32 valores, x0 = 0x00000000...]}`.
   4. Lee del `.s` la línea opcional `# rars-ignore: x1, x5` y agrega al JSON `"ignore": ["x1", "x5"]`.

   Antes de escribir el paso 2, correr `java -jar TP3_FINAL/tools/rars1_6.jar h` y confirmar `nc`, `mc CompactDataAtZero` y la impresión de registros por nombre. Si RARS imprime en otro formato, adaptar solo la regex. Por qué `CompactDataAtZero`: los programas guardan en direcciones bajas (`sw x1, 0(x0)`), que con esa configuración caen en el segmento de datos de RARS; el texto queda en 0x3000, así que las direcciones de retorno (`ra`) difieren y se listan en `rars-ignore`.

   Fallback: si RARS no termina limpio al caer del final o no imprime registros, `regs` sale con 2 y B-22 valida esos programas solo con los valores revisados a mano (se anota en `programs/README.md`).

## Validación

```
py TP3_FINAL/tools/run.py iss                 → "PASS test_iss: N chequeos", código 0
cd TP3_FINAL/sw && py -m pytest -q tests/test_iss_cli.py   → pasa
```

Mutación manual: cambiar `op_sra` por un shift lógico → `run.py iss` falla en "sra negativo". Revertir.

## Listo cuando

- [ ] Todos los tests unitarios pasan (`run.py iss` devuelve 0) y la mutación manual los hace fallar.
- [ ] El test de CLI pasa.
- [ ] `rars_ref.py regs` funciona (o el fallback está documentado en el PR con la salida de RARS).
- [ ] Registros coinciden con RARS en los programas de B-22 (se cierra en B-22, paso 4).

## No hacer

- No agregar dependencias (JSON se escribe a mano con `snprintf`).
- No implementar `auipc`, CSRs ni syscalls.
- No cambiar el formato JSON: lo comparan B-22, B-24 y B-27 como texto parseado.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `-Werror` por comparación con signo | Castear explícitamente; no bajar los warnings |
| RARS da otro valor en un registro que no es dirección de retorno | Es un bug del ISS o del programa: no agregar ese registro a `rars-ignore`; detenerse y avisar |

## Commits

1. `sw-iss: API y semántica del golden model`
2. `sw-iss: CLI y salida canónica`
3. `sw-iss: tests unitarios`
4. `tools: rars_ref regs`

## Depende de / bloquea

Depende de: B-18; A para confirmar D-17, D-18 y D-19 (aprobación de B-08). Bloquea: B-22, B-24, B-27 y la verificación de A.

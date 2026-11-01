# B-19 · Ensamblador

`L` · etiquetas `sw-asm` `bloquea-A` · milestone M3 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

`sw/asm/rvasm.py` traduce `.s` a `.hex` (para `$readmemh` y el ISS) y `.bin` (para `L`), con codificación idéntica a RARS.

## Antes de empezar

- Leer: [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §2, §6; [`protocolo.md`](../../../TP3_FINAL/doc/documentation/protocolo.md) §1 (little-endian). Nada más: todo lo demás está acá.
- Precondiciones: B-18 cerrado (`py TP3_FINAL/tools/run.py pytest` pasa).
- Manual (lo hace el usuario, no el modelo): descargar `rars1_6.jar` de las releases de GitHub `TheThirdOne/rars` y guardarlo en `TP3_FINAL/tools/rars1_6.jar`.
- Rama: `b/B-19-ensamblador`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/asm/isa.py` | Tablas de codificación (§A) y funciones `enc_r/enc_i/enc_s/enc_b/enc_u/enc_j` |
| crear | `TP3_FINAL/sw/asm/rvasm.py` | Ensamblador + CLI |
| crear | `TP3_FINAL/sw/tests/test_rvasm.py` | Tests (§E) |
| crear | `TP3_FINAL/sw/tests/data/all32.s` | Programa con las 32 instrucciones (§D) |
| crear | `TP3_FINAL/tools/rars_ref.py` | Referencia RARS (§F) |

## A. Codificación

Formatos (bits de la instrucción):

| Formato | Campos |
| --- | --- |
| R | `funct7[31:25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]` |
| I | `imm[11:0]→[31:20] rs1 funct3 rd opcode` |
| I-shift | `funct7[31:25] shamt[24:20] rs1 funct3 rd opcode` |
| S | `imm[11:5]→[31:25] rs2 rs1 funct3 imm[4:0]→[11:7] opcode` |
| B | `imm[12]→[31] imm[10:5]→[30:25] rs2 rs1 funct3 imm[4:1]→[11:8] imm[11]→[7] opcode` |
| U | `imm[31:12]→[31:12] rd opcode` |
| J | `imm[20]→[31] imm[10:1]→[30:21] imm[11]→[20] imm[19:12]→[19:12] rd opcode` |

| Instr. | Fmt | opcode | funct3 | funct7 |
| --- | --- | --- | --- | --- |
| add | R | 0110011 | 000 | 0000000 |
| sub | R | 0110011 | 000 | 0100000 |
| sll | R | 0110011 | 001 | 0000000 |
| slt | R | 0110011 | 010 | 0000000 |
| sltu | R | 0110011 | 011 | 0000000 |
| xor | R | 0110011 | 100 | 0000000 |
| srl | R | 0110011 | 101 | 0000000 |
| sra | R | 0110011 | 101 | 0100000 |
| or | R | 0110011 | 110 | 0000000 |
| and | R | 0110011 | 111 | 0000000 |
| addi | I | 0010011 | 000 | — |
| slti | I | 0010011 | 010 | — |
| sltiu | I | 0010011 | 011 | — |
| xori | I | 0010011 | 100 | — |
| ori | I | 0010011 | 110 | — |
| andi | I | 0010011 | 111 | — |
| slli | I-shift | 0010011 | 001 | 0000000 |
| srli | I-shift | 0010011 | 101 | 0000000 |
| srai | I-shift | 0010011 | 101 | 0100000 |
| lb | I | 0000011 | 000 | — |
| lh | I | 0000011 | 001 | — |
| lw | I | 0000011 | 010 | — |
| lbu | I | 0000011 | 100 | — |
| lhu | I | 0000011 | 101 | — |
| jalr | I | 1100111 | 000 | — |
| sb | S | 0100011 | 000 | — |
| sh | S | 0100011 | 001 | — |
| sw | S | 0100011 | 010 | — |
| beq | B | 1100011 | 000 | — |
| bne | B | 1100011 | 001 | — |
| jal | J | 1101111 | — | — |
| lui | U | 0110111 | — | — |
| halt / ecall | — | — | — | palabra fija `0x00000073` |

## B. Gramática aceptada

Línea a línea; mayúsculas y minúsculas indistintas en mnemónicos y registros.

- Comentario: desde `#` hasta el fin de línea. Líneas vacías se ignoran.
- Etiqueta: `nombre:` al principio (puede ir sola o seguida de una instrucción). `nombre` = `[A-Za-z_][A-Za-z0-9_]*`. Varias etiquetas en la misma dirección están permitidas.
- Directiva: solo `.text` (se ignora). Cualquier otra directiva (`.data`, `.word`, ...) es error.
- Operandos separados por comas; espacios libres.
- Registros: `x0`…`x31` y nombres ABI: `zero ra sp gp tp t0 t1 t2 s0 fp s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6` (`fp` = `s0` = x8).
- Inmediatos: decimal con signo opcional (`-12`, `+4`), hex `0x…` (con `-0x…` permitido). Sin expresiones ni `%hi/%lo`.
- Memoria: `imm(reg)` (por ejemplo `lw x1, -4(sp)`); `(reg)` sin número vale `0(reg)`.
- Destino de saltos (`beq bne jal j`): etiqueta **o** inmediato numérico, que es el desplazamiento en bytes respecto de la instrucción.

Formas por instrucción:

| Instrucciones | Sintaxis |
| --- | --- |
| R | `op rd, rs1, rs2` |
| I aritméticas | `op rd, rs1, imm` (imm en [−2048, 2047]; `sltiu` también) |
| shifts inmediatos | `op rd, rs1, shamt` (shamt en [0, 31]) |
| loads | `op rd, imm(rs1)` |
| stores | `op rs2, imm(rs1)` |
| branches | `op rs1, rs2, destino` (desplazamiento par, en [−4096, 4094]) |
| `jal` | `jal rd, destino` o `jal destino` (= `jal ra, destino`); desplazamiento par en [−1 048 576, 1 048 574] |
| `jalr` | `jalr rd, imm(rs1)` o `jalr rd, rs1, imm` o `jalr rs1` (= `jalr ra, 0(rs1)`) |
| `lui` | `lui rd, imm` con imm en [0, 0xFFFFF] |
| `halt`, `ecall` | sin operandos → `0x00000073` |

## C. Pseudo-instrucciones (expansión exacta)

| Pseudo | Expansión | Palabras |
| --- | --- | --- |
| `nop` | `addi x0, x0, 0` | 1 |
| `mv rd, rs` | `addi rd, rs, 0` | 1 |
| `j destino` | `jal x0, destino` | 1 |
| `ret` | `jalr x0, 0(x1)` | 1 |
| `li rd, v` | ver abajo | 1 o 2 |

`li rd, v`: `v` se acepta en [−2 147 483 648, 4 294 967 295] y se normaliza a 32 bits (`v & 0xFFFFFFFF`); sea `s` ese valor interpretado con signo.

- Si `−2048 ≤ s ≤ 2047`: **1 palabra**, `addi rd, x0, s`.
- Si no: **2 palabras**, siempre, aunque `lo` dé 0: `hi = ((v + 0x800) >> 12) & 0xFFFFF`, `lo = s − ((hi << 12) interpretado con signo)` (queda en [−2048, 2047]); `lui rd, hi` + `addi rd, rd, lo`.

El tamaño se decide en la primera pasada solo con `v` (que nunca es una etiqueta), así las direcciones de las etiquetas no cambian entre pasadas.

## D. Algoritmo y salidas

1. **Primera pasada:** por cada línea, quitar comentario, separar etiquetas, asignar dirección (`pc`, empieza en 0, +4 por palabra; `li` según §C). Guardar etiquetas en un `dict`; repetida → error.
2. **Segunda pasada:** codificar. Para destinos con etiqueta: `offset = dirección_etiqueta − pc_de_la_instrucción`.
3. **HALT final:** si la última palabra generada no es `0x00000073`, agregar `0x00000073`.
4. **Tamaño:** más de 256 palabras → error `programa de N palabras excede imem (256)` (línea 0).

API:

```python
class AsmError(Exception):
    def __init__(self, line: int, msg: str) -> None: ...   # str(e) == f"línea {line}: {msg}"

def assemble(src: str) -> list[int]: ...             # palabras de 32 bits; AsmError en el primer error
def to_hex(words: list[int]) -> str: ...             # "%08x\n" por palabra, minúsculas
def to_bin(words: list[int]) -> bytes: ...           # 4 bytes LE por palabra
```

CLI (`cwd = TP3_FINAL/sw`): `py -m asm.rvasm <prog.s> -o <dir>` escribe `<dir>/<base>.hex` y `<dir>/<base>.bin` (`<base>` = nombre sin `.s`). Con error imprime en stderr `<prog.s>:<línea>: error: <msg>`, no escribe ningún archivo y sale con 1. Sin `-o`, escribe al lado del `.s`.

Errores obligatorios (mensajes exactos, la línea es la del `.s`, empezando en 1):

| Caso | Mensaje |
| --- | --- |
| Mnemónico desconocido | `instrucción desconocida 'xyz'` |
| Registro inválido | `registro inválido 'x32'` |
| Cantidad de operandos | `'add' espera 3 operandos, recibió 2` |
| Inmediato fuera de rango | `inmediato 4096 fuera de rango [-2048, 2047]` (con el rango que corresponda) |
| Desplazamiento impar | `destino a desplazamiento impar (3)` |
| Etiqueta inexistente | `etiqueta 'loop2' no definida` |
| Etiqueta repetida | `etiqueta 'loop' repetida (primera en línea 4)` |
| Directiva no soportada | `directiva no soportada '.data'` |
| Inmediato mal escrito | `inmediato inválido '12z'` |

`TP3_FINAL/sw/tests/data/all32.s`: las 32 instrucciones en el orden de la tabla §A, una vez cada una, con registros distintos de x0, inmediatos no triviales (negativos en I y S), un branch hacia atrás y uno hacia adelante con etiquetas, `jal` y `jalr`, y `halt` al final. Sin pseudo-instrucciones.

## E. Tests (`sw/tests/test_rvasm.py`)

Valores esperados exactos (calculados a mano y verificados contra la especificación):

| Fuente | Palabra(s) |
| --- | --- |
| `addi x1, x0, 5` | `0x00500093` |
| `addi x1, x1, -2048` | `0x80008093` |
| `addi x1, x1, -1` | `0xfff08093` |
| `addi x1, x1, 0` | `0x00008093` |
| `addi x1, x1, 2047` | `0x7ff08093` |
| `sw x2, -4(x1)` | `0xfe20ae23` |
| `beq x0, x0, -4` | `0xfe000ee3` |
| `beq x0, x0, 4` | `0x00000263` |
| `beq x0, x0, 4094` | `0x7e000fe3` |
| `beq x0, x0, -4096` | `0x80000063` |
| `jal x0, -4` | `0xffdff06f` |
| `jal x0, 4` | `0x0040006f` |
| `jal x0, 1048574` | `0x7ffff06f` |
| `jal x0, -1048576` | `0x8000006f` |
| `lui x1, 0x12345` | `0x123450b7` |
| `srai x1, x1, 31` | `0x41f0d093` |
| `slli x1, x1, 0` | `0x00009093` |
| `nop` | `0x00000013` |
| `halt` / `ecall` | `0x00000073` |
| `ret` | `0x00008067` |
| `li x1, 0x12345FFF` | `lui x1, 0x12346` + `addi x1, x1, -1` |
| `li x1, 0x00000800` | `lui x1, 0x1` + `addi x1, x1, -2048` |
| `li x1, 0xFFFFF800` | `addi x1, x0, -2048` (1 palabra) |
| `li x1, 0x7FFFFFFF` | `lui x1, 0x80000` + `addi x1, x1, -1` |
| `li x1, -1` | `addi x1, x0, -1` (1 palabra) |
| `li x1, 0x12345000` | `lui x1, 0x12345` + `addi x1, x1, 0` (2 palabras) |

Para las filas de `li`, el test compara contra `assemble("lui ...\naddi ...")` sin el HALT agregado (comparar `words[:-1]`). En todos los casos de una sola línea, el HALT agregado es la última palabra y se descarta igual.

Además:
- Un test por error de la tabla de §D, que verifica `e.line` y el texto exacto.
- `assemble("addi x1,x0,1")` devuelve 2 palabras (HALT agregado); `assemble("addi x1,x0,1\nhalt")` devuelve 2 (no se duplica).
- Etiquetas: un `loop:` con `bne` hacia atrás da el mismo resultado que el desplazamiento numérico equivalente.
- `to_bin([0x00500093])` == `b"\x93\x00\x50\x00"`.
- CLI: con `tmp_path`, `subprocess.run(["py","-m","asm.rvasm",src,"-o",tmp])` crea `.hex` y `.bin`; con un error devuelve 1 y no crea nada.

## F. Referencia RARS (`tools/rars_ref.py`)

```
py TP3_FINAL/tools/rars_ref.py encode <prog.s> -o <out.hex>
```

1. Copia `<prog.s>` a `build/rars/<base>.s` reemplazando cada `halt` (palabra completa) por `ecall`; si la última instrucción no es `halt`/`ecall`, agrega `ecall` al final (igual que el ensamblador).
2. Corre `java -jar TP3_FINAL/tools/rars1_6.jar a mc CompactTextAtZero dump .text HexText <out.hex> build/rars/<base>.s`.
3. Devuelve el código de Java; si el jar no existe imprime `falta TP3_FINAL/tools/rars1_6.jar (ver B-19)` y sale con 2.

Antes de escribir el paso 2, correr `java -jar TP3_FINAL/tools/rars1_6.jar h` y confirmar que existen las opciones `a`, `mc CompactTextAtZero` y `dump <segment> HexText <file>`. Si el nombre de alguna difiere, usar el que muestra la ayuda y anotar en el PR qué cambió. Si no existe ninguna forma de volcar `.text` en hex, detenerse y preguntar.

Test de integración en `test_rvasm.py`, marcado `@pytest.mark.skipif(not jar.exists(), reason="sin RARS")`: para `tests/data/all32.s` y para un archivo con todas las filas de §E que usan etiquetas o `li` (las de desplazamiento numérico se excluyen: no se comparan contra RARS), `assemble()` y RARS dan las mismas palabras.

## Validación

```
cd TP3_FINAL/sw
py -m pytest -q tests/test_rvasm.py        → todos pasan (incluido el de RARS si el jar está)
py -m asm.rvasm tests/data/all32.s -o ../build
py ../tools/rars_ref.py encode tests/data/all32.s -o ../build/all32.rars.hex
```

y `fc /W ..\build\all32.hex ..\build\all32.rars.hex` (o `diff`) → sin diferencias.

## Listo cuando

- [ ] Coincidencia exacta con RARS en `all32.s` y en los casos de §E con etiquetas o `li`.
- [ ] Los casos de §E con valores fijos pasan.
- [ ] Cada error de la tabla de §D produce el mensaje con línea y no genera salida.

## No hacer

- No agregar directivas, expresiones, `la`, `call`, `tail` ni otras pseudo-instrucciones.
- No emitir `li` de 1 palabra cuando `s` no entra en 12 bits, ni de 2 cuando entra.
- No usar bibliotecas fuera de la estándar.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| RARS codifica un `li` distinto (por ejemplo, solo `lui` cuando `lo = 0`) | No cambiar §C. Excluir ese caso del test RARS, dejar un comentario con la salida de RARS y avisar en el PR |
| RARS no acepta `jal destino` de un operando | Usar `jal ra, destino` en `all32.s` |
| El volcado de RARS tiene más líneas (ceros al final) | Comparar solo las primeras `len(words)` líneas |

## Commits

1. `sw-asm: tablas de codificación`
2. `sw-asm: ensamblador de dos pasadas con pseudo-instrucciones`
3. `sw-asm: tests y referencia RARS`

## Depende de / bloquea

Depende de: B-18. Bloquea: B-20, B-22, B-24, B-25, B-27, y la verificación de A (Fases 3 a 7).

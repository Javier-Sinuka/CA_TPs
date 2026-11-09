# Formato del dump v1 y formato canónico de resultados

**Estado: v1 propuesta, pendiente de aprobación de A (B-07).** El layout de las palabras de latch (§3) define puertos del RTL de A: A lo aprueba o lo cambia **antes** de escribir sus latches.

## 1. Mapa de bytes

```
A5 | W0 W1 ... W51 | M pares (dirección, dato) | checksum
```

| Posición | Contenido | Fuente en la Debug Unit |
| --- | --- | --- |
| byte 0 | Cabecera `0xA5` | constante |
| W0 | Estado (§2) | registros de la Debug Unit + `i_cpu_halted` |
| W1 | Ciclos: cantidad de flancos con `cpu_en = 1` y `halted = 0` desde el último reset del CPU | contador de 32 bits de la Debug Unit |
| W2 | `dbg_pc` (PC de IF) | `o_dbg_pc` |
| W3 … W34 | x0 … x31 | `dbg_reg_addr = idx − 3` |
| W35 … W50 | Palabras de latch 0 … 15 (§3) | `dbg_latch_sel = idx − 35` |
| W51 | `M` = cantidad de palabras sucias de dmem (0 … 256) | primera pasada sobre `dbg_mem_dirty` |
| 2·M palabras | Para cada palabra sucia, en orden ascendente: dirección **en bytes** (`índice·4`) y dato | segunda pasada |
| último byte | Checksum (§4) | acumulador |

Cada palabra se envía en 4 bytes little-endian. Largo total: **`210 + 8·M` bytes** (1 + 52·4 + 8·M + 1). Con `M = 0`: 210 bytes, ≈ 18 ms a 115200.

## 2. Palabra de estado (W0)

| Bits | Campo | Significado |
| --- | --- | --- |
| 0 | `halted` | Valor de `i_cpu_halted` al armar el dump |
| 1 | `timeout` | La última `R` paró por `RUN_TIMEOUT` |
| 2 | `aborted` | La última `R` paró por `A` |
| 7:3 | — | 0 |
| 15:8 | `version` | `0x01` (versión del formato) |
| 31:16 | — | 0 |

`timeout` y `aborted` se ponen en 0 con `X`, `L`, `S` y al empezar `R`. Nunca están los dos en 1.

## 3. Palabras de latch (`dbg_latch_sel` 0 … 15)

| sel | Latch | Contenido |
| --- | --- | --- |
| 0 | IF/ID | `pc_id` |
| 1 | IF/ID | `instr_id` |
| 2 | ID/EX | `pc_ex` |
| 3 | ID/EX | `rs1_data_ex` |
| 4 | ID/EX | `rs2_data_ex` |
| 5 | ID/EX | `imm_ex` |
| 6 | ID/EX | info (§3.1) |
| 7 | EX/MEM | `pc_mem` |
| 8 | EX/MEM | `result_mem` |
| 9 | EX/MEM | `store_data_mem` |
| 10 | EX/MEM | info (§3.1) |
| 11 | MEM/WB | `pc_wb` |
| 12 | MEM/WB | `result_wb` |
| 13 | MEM/WB | `load_data_wb` |
| 14 | MEM/WB | info (§3.1) |
| 15 | — | palabra de validez y riesgos (§3.2) |

### 3.1 Palabra info (mismo layout en sel 6, 10 y 14)

Un solo layout para los tres latches, así el software tiene un único decodificador. Un campo que ese latch no transporta se lee 0.

| Bits | Campo | ID/EX | EX/MEM | MEM/WB |
| --- | --- | --- | --- | --- |
| 4:0 | `rd` | ✓ | ✓ | ✓ |
| 9:5 | `rs1` | ✓ | 0 | 0 |
| 14:10 | `rs2` | ✓ | 0 | 0 |
| 17:15 | `funct3` | ✓ | ✓ | 0 |
| 21:18 | `alu_op` (códigos `ALU_*` de `riscv_defs.vh`) | ✓ | 0 | 0 |
| 22 | `alu_src_b` | ✓ | 0 | 0 |
| 23 | `mem_read` | ✓ | ✓ | 0 |
| 24 | `mem_write` | ✓ | ✓ | 0 |
| 25 | `mem_to_reg` | ✓ | ✓ | ✓ |
| 26 | `reg_write` | ✓ | ✓ | ✓ |
| 27 | `branch` | ✓ | 0 | 0 |
| 28 | `jump` | ✓ | 0 | 0 |
| 29 | `jalr` | ✓ | 0 | 0 |
| 30 | `lui` | ✓ | 0 | 0 |
| 31 | `halt` | ✓ | ✓ | ✓ |

Los nombres son los puertos de `control.v` de A (`o_alu_op`, `o_alu_src_b`, ...).

### 3.2 Palabra de validez y riesgos (sel 15)

| Bit | Campo |
| --- | --- |
| 0 | `valid_id` (IF/ID) |
| 1 | `valid_ex` (ID/EX) |
| 2 | `valid_mem` (EX/MEM) |
| 3 | `valid_wb` (MEM/WB) |
| 4 | `halted` |
| 5 | `load_use_stall` (combinacional, del ciclo actual) |
| 6 | `take_ex` (salto tomado en EX en el ciclo actual) |
| 7 | `stop_fetch` |
| 31:8 | 0 |

Los bits 5 a 7 permiten dibujar el diagrama espacio-tiempo (B-26) con stalls y flushes marcados.

## 4. Checksum

`checksum = (suma de todos los bytes desde el primero de W0 hasta el último del último par) mod 256`. No incluye la cabecera ni a sí mismo. Un dump cuyo checksum no verifica se rechaza con `DumpError`.

## 5. API de `sw/host/dump.py`

```python
@dataclass(frozen=True)
class LatchInfo:            # §3.1
    rd: int; rs1: int; rs2: int; funct3: int; alu_op: int
    alu_src_b: bool; mem_read: bool; mem_write: bool; mem_to_reg: bool
    reg_write: bool; branch: bool; jump: bool; jalr: bool; lui: bool; halt: bool
    @staticmethod
    def unpack(word: int) -> "LatchInfo": ...
    def pack(self) -> int: ...

@dataclass(frozen=True)
class Dump:
    halted: bool; timeout: bool; aborted: bool; version: int
    cycles: int; pc: int
    x: tuple[int, ...]            # 32 valores
    latches: tuple[int, ...]      # 16 palabras crudas
    mem: tuple[tuple[int, int], ...]   # (dirección en bytes, dato), ascendente
    # vistas decodificadas (propiedades): info_ex, info_mem, info_wb -> LatchInfo; valid_id..valid_wb, load_use_stall, take_ex, stop_fetch -> bool

def encode(d: Dump) -> bytes: ...           # incluye 0xA5 y checksum
def decode(b: bytes) -> Dump: ...           # DumpError si cabecera, largo o checksum fallan
def expected_length(m: int) -> int: ...     # 210 + 8*m
class DumpError(Exception): ...
```

## 6. Formato canónico de resultados (`*.json`)

Lo producen el ISS (B-21), la simulación RTL y la placa (B-27), y se comparan entre sí. Todas las cifras en hex de 8 dígitos con prefijo `0x`, minúsculas.

```json
{
  "stop": "halt",
  "pc": "0x0000001c",
  "x": ["0x00000000", "0x00000037", "...32 valores en total..."],
  "mem": [["0x00000000", "0x00000037"]]
}
```

| Campo | Definición |
| --- | --- |
| `stop` | `"halt"` o `"limit"` (ISS: límite de instrucciones; RTL/placa: `timeout`) |
| `pc` | Dirección de la instrucción HALT que paró. En RTL/placa sale de la palabra de latch 11 (`pc_wb`, porque con `halted` el HALT está en WB). Con `stop = "limit"` vale `null` |
| `x` | x0 … x31 |
| `mem` | Palabras de dmem escritas al menos una vez por el programa, `[dirección en bytes, dato]`, ascendente. En RTL/placa: los pares del dump |

Con `stop = "limit"` solo se compara `stop` (las cuentas de ciclos e instrucciones no son comparables). `sw/host/canonical.py` tiene `from_dump(d: Dump) -> dict`, `load(path) -> dict`, `diff(a, b) -> list[str]` (una línea por diferencia: `x5: iss=0x00000003 rtl=0x00000004`).

## 7. Ejemplos

Dumps del `cpu_stub` con 0 y 1 ciclos, generados con `host.dump.encode` (los mismos que debe producir `stub_dump` en B-09).

`stub_dump(0, 20)` (210 bytes):

```
a5 00 01 00 00 00 00 00 00 00 00 00 00 00 00 00
00 01 00 00 00 02 00 00 00 03 00 00 00 04 00 00
00 05 00 00 00 06 00 00 00 07 00 00 00 08 00 00
00 09 00 00 00 0a 00 00 00 0b 00 00 00 0c 00 00
00 0d 00 00 00 0e 00 00 00 0f 00 00 00 10 00 00
00 11 00 00 00 12 00 00 00 13 00 00 00 14 00 00
00 15 00 00 00 16 00 00 00 17 00 00 00 18 00 00
00 19 00 00 00 1a 00 00 00 1b 00 00 00 1c 00 00
00 1d 00 00 00 1e 00 00 00 1f 00 00 00 00 00 00
1a 00 00 01 1a 00 00 02 1a 00 00 03 1a 00 00 04
1a 00 00 05 1a 00 00 06 1a 00 00 07 1a 00 00 08
1a 00 00 09 1a 00 00 0a 1a 00 00 0b 1a 00 00 0c
1a 00 00 0d 1a 00 00 0e 1a 00 00 0f 1a 00 00 00
00 09
```

`stub_dump(1, 20)` (234 bytes):

```
a5 00 01 00 00 01 00 00 00 04 00 00 00 00 00 00
00 01 01 00 00 02 01 00 00 03 01 00 00 04 01 00
00 05 01 00 00 06 01 00 00 07 01 00 00 08 01 00
00 09 01 00 00 0a 01 00 00 0b 01 00 00 0c 01 00
00 0d 01 00 00 0e 01 00 00 0f 01 00 00 10 01 00
00 11 01 00 00 12 01 00 00 13 01 00 00 14 01 00
00 15 01 00 00 16 01 00 00 17 01 00 00 18 01 00
00 19 01 00 00 1a 01 00 00 1b 01 00 00 1c 01 00
00 1d 01 00 00 1e 01 00 00 1f 01 00 00 01 00 00
1a 01 00 01 1a 01 00 02 1a 01 00 03 1a 01 00 04
1a 01 00 05 1a 01 00 06 1a 01 00 07 1a 01 00 08
1a 01 00 09 1a 01 00 0a 1a 01 00 0b 1a 01 00 0c
1a 01 00 0d 1a 01 00 0e 1a 01 00 0f 1a 03 00 00
00 10 00 00 00 04 00 00 d0 40 00 00 00 10 00 00
d0 fc 00 00 00 3f 00 00 d0 4f
```

# B-20 · Desensamblador

`S` · etiquetas `sw-asm` · milestone M3 · **Modelo sugerido:** Haiku · [índice](../README.md)

## Objetivo

`disasm(word) -> str` muestra la instrucción de cada etapa en la CLI y la GUI, y su salida vuelve a ensamblar a la misma palabra.

## Antes de empezar

- Leer: [B-19](B-19-ensamblador.md) §A (tabla de codificación) y §B (sintaxis). Reutilizar `sw/asm/isa.py`.
- Precondiciones: B-19 cerrado (`py -m pytest -q tests/test_rvasm.py` pasa, con `cwd = TP3_FINAL/sw`).
- Rama: `b/B-20-desensamblador`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/asm/disasm.py` | `disasm()` |
| crear | `TP3_FINAL/sw/tests/test_disasm.py` | Tests |

## Pasos

1. API:

   ```python
   def disasm(word: int) -> str: ...
   ```

   Formato de salida exacto (registros **siempre** como `xN`, inmediatos en decimal con signo, minúsculas, un espacio después del mnemónico, `", "` entre operandos):

   | Tipo | Ejemplo |
   | --- | --- |
   | R | `add x3, x1, x2` |
   | I aritmética | `addi x1, x0, -5` |
   | shift inmediato | `srai x1, x1, 31` |
   | load | `lw x5, -4(x2)` |
   | store | `sw x5, 8(x2)` |
   | branch | `bne x2, x3, -8` (desplazamiento numérico en bytes) |
   | jal | `jal x1, 16` |
   | jalr | `jalr x0, 0(x1)` |
   | lui | `lui x1, 0x12345` (único inmediato en hex, 5 dígitos) |
   | `0x00000073` | `halt` |
   | `0x00000013` | `nop` |
   | cualquier otra palabra fuera del subconjunto | `???` |

   Fuera del subconjunto = opcode no listado, o funct3/funct7 no listados para ese opcode (por ejemplo funct7 `0100000` con `add`… es `sub`; con `xor` es `???`), o shift inmediato con `funct7` distinto de los de la tabla.

2. Función auxiliar para la GUI y la CLI:

   ```python
   def disasm_at(words: list[int], pc: int) -> str:
       """Desensambla words[pc >> 2] si existe; si no, '???'."""
   ```

## Validación

`sw/tests/test_disasm.py`:

- Cada fila de la tabla del paso 1 (palabra → texto exacto), usando las palabras de B-19 §E.
- `disasm(0x00000000) == "???"`, `disasm(0xffffffff) == "???"`, `disasm(0x40007033) == "???"` (`and` con funct7 alterno).
- Ida y vuelta: para `tests/data/all32.s` y, cuando existan, todos los `TP3_FINAL/programs/*.s` (B-22), `w = assemble(src)`; `assemble("\n".join(disasm(x) for x in w)) == w`. El test arma la lista con `glob` y no falla si `programs/` está vacío.

`cd TP3_FINAL/sw && py -m pytest -q tests/test_disasm.py` → todos pasan.

## Listo cuando

- [ ] La ida y vuelta da idéntico en `all32.s` y en todos los programas de `programs/` que existan.
- [ ] Las palabras fuera del subconjunto dan `???`.

## No hacer

- No usar nombres ABI ni pseudo-instrucciones en la salida (salvo `nop` y `halt`), para que la ida y vuelta sea exacta.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| La ida y vuelta falla en un branch | El ensamblador acepta desplazamiento numérico (B-19 §B); verificar el signo del inmediato B |

## Commits

1. `sw-asm: desensamblador`

## Depende de / bloquea

Depende de: B-19. Bloquea: B-25, B-26.

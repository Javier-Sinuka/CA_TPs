# B-25 · CLI

`M` · etiquetas `sw-host` · milestone M3 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

`py -m host.cli` carga, ejecuta, avanza y muestra registros, memoria y pipeline, contra la placa real o la simulada, con una salida de texto fija que se puede comparar en un test.

## Antes de empezar

- Leer: [B-23](B-23-link.md) paso 3 (API de `Link`); [B-24](B-24-placa-simulada.md) "Diseño"; [B-20](B-20-desensamblador.md) paso 1; [`dump.md`](../../../TP3_FINAL/doc/documentation/dump.md) §3.2.
- Precondiciones: B-20, B-23 y B-24 cerrados.
- Rama: `b/B-25-cli`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/host/cli.py` | CLI |
| crear | `TP3_FINAL/sw/tests/data/session1.txt` | Sesión guionada (paso 4) |
| crear | `TP3_FINAL/sw/tests/data/session1.expected.txt` | Salida esperada (paso 5) |
| crear | `TP3_FINAL/sw/tests/data/b16_script.txt`, `b16_progA.hex`, `b16_progB.hex` | Guion de B-16 para la placa (paso 6) |
| crear | `TP3_FINAL/sw/tests/test_cli.py` | Tests |

## Pasos

1. **Invocación** (`cwd = TP3_FINAL/sw`):

   ```
   py -m host.cli (--port COMx | --fake) [--script <archivo>] [--iss <ruta>]
   ```

   `--fake` usa `FakeBoard(--iss)`, default `../build/iss.exe`; si no existe: `error: falta ../build/iss.exe (py TP3_FINAL/tools/run.py iss)` y sale con 2. Al arrancar llama `connect()` e imprime `conectado: protocolo 1, imem 256, dmem 256 palabras`.

   Sin `--script`: lee comandos de stdin con el prompt `rv> `. Con `--script`: lee el archivo, ignora líneas vacías y las que empiezan con `#`, y antes de ejecutar cada comando imprime `> <comando>`. Sale con 0 si no hubo ningún `error:`, 1 si hubo alguno (no corta en el primer error).

2. **Comandos y salida exacta.** La CLI guarda el último dump (`cur`), el anterior (`prev`) y las palabras del último programa cargado (`words`).

   | Comando | Acción | Salida |
   | --- | --- | --- |
   | `version` | `connect()` | `conectado: protocolo 1, imem 256, dmem 256 palabras` |
   | `load <ruta>` | `.s` → `asm.rvasm.assemble`; `.hex` → una palabra por línea; `link.load(words)`; después `dump()` silencioso (`prev = None`, `cur = dump`) | `cargado: <N> palabras (<ruta>)` |
   | `reset` | `link.reset()` y `dump()` silencioso | `reset: ok` |
   | `step [n]` | `n` veces (default 1) `step()` | por paso: `paso: ciclos=<c> pc=0x<pc8>` y, si `halted`, ` halted` al final de la línea |
   | `run` | `link.run()` | `run: <motivo> ciclos=<c> pc=0x<pc8>`; motivo `halt`, `timeout` o `abort`; con `halt`, `pc` es la palabra de latch 11; si no, W2 |
   | `dump` | `link.dump()` | `dump: ciclos=<c> pc=0x<pc8> halted=<0|1>` (pc = W2) |
   | `regs` | — | 8 líneas de 4 registros (ver abajo) |
   | `mem` | — | por par `0x<addr8>: 0x<dato8>`; si no hay, `(sin palabras escritas)` |
   | `pipe` | — | 5 líneas (ver abajo) |
   | `raw <hh>` | `link.raw_error(int(hh, 16))` | `raw: E <cc>` (2 dígitos hex) |
   | `quit` | termina | — |
   | otro | — | `error: comando desconocido '<texto>'` |

   Toda excepción `LinkError`/`AsmError`/`OSError` se imprime como `error: <str(e)>` y la CLI sigue. Cada comando que recibe un dump hace `prev = cur; cur = nuevo`.

   **`regs`:** línea `j` (0..7) con los registros `4j … 4j+3`. Cada celda `f"x{i:<2}=0x{v:08x}{m}"` con `m = "*"` si `prev` existe y el valor cambió respecto de `prev`, si no `" "`. Línea = `" ".join(celdas).rstrip()`. Sin dump todavía: `error: no hay estado (usar dump)`.

   **`pipe`:** cinco líneas, etapa con `f"{nombre:<4}"` (`IF  `, `ID  `, `EX  `, `MEM `, `WB  `) seguida de `0x<pc8>  <texto>` si la etapa es válida o `--` si no:

   | Etapa | Válida si | pc | texto |
   | --- | --- | --- | --- |
   | IF | `not stop_fetch and not halted` | W2 | `disasm_at(words, pc)` |
   | ID | `valid_id` | latch 0 | `disasm(latch 1)` |
   | EX | `valid_ex` | latch 2 | `disasm_at(words, pc)` |
   | MEM | `valid_mem` | latch 7 | `disasm_at(words, pc)` |
   | WB | `valid_wb` | latch 11 | `disasm_at(words, pc)` |

   Con la placa simulada solo WB es válida (B-24); es lo esperado.

3. Separar la lógica de la E/S: `class Session` con `execute(line: str) -> list[str]` (devuelve las líneas de salida) y `main()` que solo lee e imprime. Los tests usan `Session` directamente.

4. `tests/data/session1.txt` (literal):

   ```
   # sesión guionada sobre la placa simulada
   load ../programs/suma.s
   regs
   step 3
   regs
   pipe
   run
   regs
   mem
   step
   reset
   regs
   mem
   raw 7a
   foo
   ```

5. Generar `session1.expected.txt` corriendo `py -m host.cli --fake --script tests/data/session1.txt > tests/data/session1.expected.txt` **y revisarlo a mano** contra esta lista antes de versionarlo (si alguna no se cumple, el error está en el código, no en la lista):
   - `cargado: 8 palabras (../programs/suma.s)`.
   - Primer `regs`: todos `0x00000000`, ningún `*`.
   - `step 3`: `paso: ciclos=1 pc=0x00000004`, `paso: ciclos=2 pc=0x00000008`, `paso: ciclos=3 pc=0x0000000c`.
   - Segundo `regs`: `x2 =0x00000001` y `x3 =0x0000000b` sin `*` en `x2` (el último paso solo cambió `x3`), `*` en `x3`.
   - `run: halt ciclos=<n> pc=0x0000001c`, con `n` = instrucciones de `suma` hasta el HALT (3 + 10·3 + 1 = 34).
   - Tercer `regs`: `x1 =0x00000037*`.
   - `mem`: `0x00000000: 0x00000037`.
   - `step` con el CPU detenido: `paso: ciclos=34 pc=0x0000001c halted`.
   - Después de `reset`: `regs` todo en 0, `mem` → `(sin palabras escritas)`.
   - `raw 7a` → `raw: E 01`; `foo` → `error: comando desconocido 'foo'`.
   - El proceso sale con 1 (por `foo`).

6. Guion de B-16 para la placa: `tests/data/b16_progA.hex` y `b16_progB.hex` con las palabras exactas de los programas A y B del TB de B-16 (copiarlas de ese TB), y `b16_script.txt`:

   ```
   version
   load tests/data/b16_progA.hex
   step 5
   run
   dump
   reset
   load tests/data/b16_progB.hex
   run
   raw 7a
   dump
   ```

   Contra la placa con el stub (`--port COMx`, B-17) debe terminar con código 0 y los valores de `stub_model` (`run: halt ciclos=20 …`).

7. Tests (`test_cli.py`): `Session` sobre `FakeBoard` ejecuta `session1.txt` y la salida (con las líneas `> comando`) es idéntica a `session1.expected.txt`; un test por comando de la tabla con su línea exacta.

## Validación

```
cd TP3_FINAL/sw
py -m pytest -q tests/test_cli.py                              → pasa
py -m host.cli --fake --script tests/data/session1.txt          → igual a session1.expected.txt, código 1
```

## Listo cuando

- [ ] La sesión guionada pasa contra la placa simulada.
- [ ] `b16_script.txt` corre contra la placa con el stub sin errores (se marca al cerrar B-17).

## No hacer

- No usar colores ni `curses` (la salida tiene que ser comparable como texto).
- No hablar con el puerto fuera de `Link`.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `ciclos` de `run` no da 34 | Contar de nuevo: 3 inicializaciones + 10 vueltas × 3 + `sw`; si el ISS dice otro número, revisar `suma.s` contra B-22 |
| Rutas relativas no encuentran el archivo | El `cwd` tiene que ser `TP3_FINAL/sw` |

## Commits

1. `sw-host: CLI sobre link`
2. `sw-host: sesión guionada y guion de B-16`

## Depende de / bloquea

Depende de: B-20, B-23, B-24. Bloquea: B-26, cierre de B-17.

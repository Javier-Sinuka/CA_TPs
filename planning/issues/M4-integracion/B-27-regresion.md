# B-27 · Regresión de tres niveles

`M` · etiquetas `test` · milestone M4 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

`py TP3_FINAL/tools/run.py regress` corre cada programa de B-22 en el ISS, en la placa simulada, en simulación RTL y (opcional) en la placa, y compara cada resultado contra el `.expected.json` con un diff legible.

## Antes de empezar

- Leer: [`dump.md`](../../../TP3_FINAL/doc/documentation/dump.md) §6; [`convenciones.md`](../../../TP3_FINAL/doc/documentation/convenciones.md) §3; [B-22](../M3-sw/B-22-programas-prueba.md) paso 2 (`canonical.diff`); [B-28](B-28-tb-system-prog.md) (nivel RTL).
- Precondiciones: B-22, B-24 y B-28 cerrados.
- Rama: `b/B-27-regresion`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/tools/regress.py` | Lógica de la regresión |
| modificar | `TP3_FINAL/tools/run.py` | Objetivo `regress` que llama a `regress.main(args)` |
| crear | `TP3_FINAL/sw/tests/test_regress.py` | Test del bug inyectado (paso 5) |

## Pasos

1. **Invocación:**

   ```
   py TP3_FINAL/tools/run.py regress [--levels iss,fake,rtl,board] [--board COMx] [--program <nombre>] [--iss-mutant sra]
   ```

   Default `--levels iss,fake,rtl`. `board` solo se corre si se pasa `--board`. `--program` limita a un programa (nombre sin `.s`). Salidas en `TP3_FINAL/build/regress/<prog>.<nivel>.json`.

2. **Niveles** (cada uno produce un JSON canónico por programa):

   | Nivel | Cómo |
   | --- | --- |
   | `iss` | `build/iss.exe programs/<p>.hex -o …` (o `build/iss_mut.exe` con `--iss-mutant`) |
   | `fake` | `Link(FakeBoard(build/iss.exe, run_limit=10_000))`: `load`, `run`, `canonical.from_dump` |
   | `rtl` | Si `CPU_FILES` de `tools/tbs.py` está vacío (todavía no hay CPU real): corre una sola vez `run.py tb tb_system_prog_stub` y reporta `rtl: stub (sin CPU real)` como `OK`/`FAIL` según el TB, sin comparar programas. Si no está vacío: por programa, `run.py tb tb_system_prog +prog=<abs .hex> +out=build/regress/<p>.rtl.dump.hex`, decodifica el archivo (un byte hex por línea) con `dump.decode` y `canonical.from_dump` |
   | `board` | `Link.open(COMx)`: `connect`, `load`, `run`, `canonical.from_dump` |

   Los programas se toman de `TP3_FINAL/programs/*.s` en orden alfabético; se usan sus `.hex` y `.bin` versionados (B-22 garantiza que están al día).

3. **Comparación:** cada JSON contra `programs/<p>.expected.json` con `canonical.diff(expected, obtenido, "esperado", nivel)`. Salida en consola:

   ```
   programa      iss   fake  rtl   board
   alu_nodep     OK    OK    -     -
   branches      OK    OK    -     -
   ...
   rtl: stub (sin CPU real) OK

   FALLAS:
   alu_nodep [iss] x10: esperado=0xffffffff iss=0x01ffffff
   alu_nodep [iss] x21: esperado=0xfffffffe iss=0x7ffffffe
   ```

   (`-` = nivel no corrido para ese programa; `ERR` = el nivel tiró una excepción, con el mensaje en FALLAS.) Código de salida 1 si hay alguna falla o `ERR`.

4. **Mutante del ISS** (`--iss-mutant sra`): copia `sw/iss/iss.cpp` a `build/mut/iss.cpp` reemplazando la línea que contiene `// MUT:sra` por

   ```cpp
   static uint32_t op_sra(uint32_t a, uint32_t sh) { return a >> (sh & 31); } // MUT:sra
   ```

   compila `build/iss_mut.exe` con `build/mut/iss.cpp` + `sw/iss/iss_main.cpp` (con `-I TP3_FINAL/sw/iss`) y lo usa en el nivel `iss` (los demás niveles no cambian). Si no encuentra el marcador: `ERR: falta // MUT:sra en iss.cpp (B-21)`.

5. **Test** (`test_regress.py`, usa `subprocess`): `run.py regress --levels iss --iss-mutant sra` devuelve 1 y su salida contiene la línea `alu_nodep [iss] x10: esperado=0xffffffff iss=0x01ffffff`; `run.py regress --levels iss,fake` devuelve 0.

## Validación

```
py TP3_FINAL/tools/run.py regress                               → tabla todo OK, código 0
py TP3_FINAL/tools/run.py regress --levels iss --iss-mutant sra → código 1, nombra alu_nodep, x10 y valores
py TP3_FINAL/tools/run.py regress --board COM3                  → (con la placa con el stub conectada) board: ERR/diferencias esperadas: el stub no ejecuta programas; solo verifica que el nivel corre. Con el CPU real (Fase 11) tiene que dar OK
```

## Listo cuando

- [ ] La regresión corre de punta a punta con los niveles `iss`, `fake` y `rtl` (stub) y da OK.
- [ ] El bug inyectado se detecta con un mensaje que nombra programa, registro y valores (test).
- [ ] Agregar los archivos del CPU real a `CPU_FILES` es el único cambio para que el nivel `rtl` compare programas (lo verifica B-28).

## No hacer

- No comparar ciclos ni `instret`.
- No regenerar `.expected.json` desde la regresión.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `no_halt` falla en `fake` por tiempo | Debe usar `run_limit=10_000`; con `stop = "limit"` en los dos lados `diff` da `[]` |
| El mutante no compila | Verificar el `-I` a `sw/iss` para `iss.hpp` |

## Commits

1. `tools: regresión de tres niveles`
2. `tools: mutante sra del ISS y test`

## Depende de / bloquea

Depende de: B-22, B-24, B-28. Bloquea: B-29, Fase 10.

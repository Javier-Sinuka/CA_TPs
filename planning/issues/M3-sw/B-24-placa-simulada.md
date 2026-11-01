# B-24 · Placa simulada

`S` · etiquetas `sw-host` `test` · milestone M3 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

`sw/host/fakeboard.py`: un objeto con la API de puerto de B-23 que responde el protocolo v1 ejecutando el ISS (`build/iss.exe`), para desarrollar la CLI y la GUI sin FPGA.

## Antes de empezar

- Leer: [`protocolo.md`](../../../TP3_FINAL/doc/documentation/protocolo.md) §2-§4; [`dump.md`](../../../TP3_FINAL/doc/documentation/dump.md) §1-§3, §6; [B-21](B-21-golden-model.md) pasos 2 y 3 (CLI con `--max-instr` y `--full`); [B-23](B-23-link.md) paso 1 (API de puerto).
- Precondiciones: B-21, B-22 y B-23 cerrados.
- Rama: `b/B-24-placa-simulada`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/host/fakeboard.py` | `FakeBoard` |
| crear | `TP3_FINAL/sw/tests/test_fakeboard.py` | Tests |

## Diseño (decidido)

No hay un segundo ISS en Python. La placa simulada guarda imem, la cantidad de instrucciones ejecutadas `k` y vuelve a correr `iss.exe` desde cero cada vez que necesita el estado: `iss.exe prog.hex --max-instr k --full`. Los programas son chicos y cada corrida tarda milisegundos.

Equivalencias con la placa real:

| Dump real | FakeBoard |
| --- | --- |
| W1 ciclos | `k` (instrucciones ejecutadas) |
| W2 `dbg_pc` | `next_pc` del JSON |
| x0..x31 | `x` del JSON |
| latches 0..14 | 0, salvo `latches[11] = pc` del HALT y `latches[14] = 0x80000000` (`halt` en WB) cuando está detenido |
| latch 15 | `0x00000008` (`valid_wb`) si no está detenido y `k` < límite; `0x00000018` (`valid_wb` + `halted`) si está detenido |
| pares de dmem | `mem` del JSON |
| `halted` | `stop == "halt"` |

Así `canonical.from_dump()` funciona igual que con la placa (toma el `pc` de la palabra de latch 11) y la GUI (B-26) cuenta instrucciones retiradas con `valid_wb` (cada paso retira una).

## Pasos

1. API:

   ```python
   class FakeBoard:
       def __init__(self, iss_exe: str | Path, run_limit: int = 1_000_000,
                    fault: dict[str, int] | None = None) -> None: ...
       timeout: float | None
       def write(self, data: bytes) -> int: ...
       def read(self, n: int) -> bytes: ...          # devuelve lo que haya (hasta n); nunca bloquea
       def reset_input_buffer(self) -> None: ...
       def close(self) -> None: ...
   ```

   `fault = {"x5": 0xdead}` reemplaza ese registro en **todos** los dumps que se generen (para la prueba de divergencia de B-26). Claves válidas: `"x1"`…`"x31"`.

2. Estado interno: `imem` (256 palabras, al crear todas `0x00000073`), `k = 0`, `halted`, `timeout_flag`, `aborted_flag`, buffer de salida, estado del parser de comandos (reposo, `L` esperando `N`, `L` esperando datos con contador).

3. `write(data)` procesa byte a byte, sin hilos, y deja las respuestas en el buffer de salida:

   | Entrada | Acción | Respuesta |
   | --- | --- | --- |
   | `V` | — | `56 01 00 01 00 01` |
   | `X` | `k = 0`, flags en 0 | `4B` |
   | `L NL NH` | `N > 256` → nada | `45 02` |
   | `L NL NH` (válido) | pasa a esperar `4·N` bytes | `4B` |
   | palabra `i` completa | `imem[i] = palabra` | — |
   | último byte de datos | `imem[N..255] = HALT`, `k = 0`, flags en 0 | `4B` |
   | `S` | si no está detenido, `k += 1`; flags en 0 | dump |
   | `R` | flags en 0; corre con `--max-instr run_limit`; si `stop == "limit"` → `timeout_flag = 1`; `k = instret` | dump |
   | `A` | se ignora (la `R` simulada es instantánea) | — |
   | `D` | — | dump |
   | otro en reposo | — | `45 01` |

   No simula `E 03` (no hay tiempo real entre bytes).

4. Para cada dump: escribir imem en un `.hex` temporal (`tempfile`, las 256 palabras), correr `iss.exe <hex> --max-instr k --full`, leer el JSON, armar `Dump` con la tabla de equivalencias (versión 1, `aborted` en 0), aplicar `fault`, y `dump.encode()`. `S` con el CPU detenido no cambia `k`, así que el dump es el mismo.

5. Tests (`test_fakeboard.py`, fixture `iss_exe`):
   - `Link(FakeBoard(iss_exe)).connect()` → `Version(1, 256, 256)`.
   - **Los 9 programas de B-22:** `load(words)`, `run()`, `canonical.from_dump(d)` vs `canonical.load(<prog>.expected.json)` → `diff == []`. Para `no_halt` se usa `FakeBoard(iss_exe, run_limit=10_000)` y se espera `stop == "limit"`.
   - **Paso a paso:** `suma`: `load`, 3 × `step()`: `cycles == 3`, `x[1] == 0`, `x[2] == 1`, `x[3] == 11`; seguir con `step()` hasta `halted` y verificar el mismo estado final que `run()`; un `step()` más deja el dump idéntico.
   - **Errores:** `load` de 257 palabras levanta `LinkError` en `Link` (no llega a la placa); un `L` manual con `N = 257` vía `port.write(b"\x4c\x01\x01")` deja `45 02` en el buffer; `raw_error(0x7A) == 1`.
   - **fault:** `FakeBoard(iss_exe, fault={"x5": 0xdead})` → `run()` sobre `branches` da `x[5] == 0xdead`.

## Validación

```
cd TP3_FINAL/sw && py -m pytest -q tests/test_fakeboard.py     → todos pasan
```

## Listo cuando

- [ ] Los 9 programas dan, a través de `link.py` y la placa simulada, el mismo estado final que su `.expected.json`.
- [ ] El paso a paso de `suma` y la inyección de `fault` funcionan.

## No hacer

- No reimplementar instrucciones en Python.
- No usar hilos ni `time.sleep`.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| `iss.exe` no existe | Usar la fixture `iss_exe` de `conftest.py`, que lo compila |
| `next_pc` no está en el JSON | Falta `--full` en la llamada |

## Commits

1. `sw-host: placa simulada sobre el ISS`
2. `sw-host: tests de la placa simulada`

## Depende de / bloquea

Depende de: B-21, B-22, B-23. Bloquea: B-25, B-26, B-27.

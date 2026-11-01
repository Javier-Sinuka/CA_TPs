# B-23 · Enlace serie: `link.py`

`M` · etiquetas `sw-host` · milestone M3 · **Modelo sugerido:** Sonnet · [índice](../README.md)

## Objetivo

`sw/host/link.py` habla el protocolo v1 sobre cualquier objeto con la API de `serial.Serial` y devuelve objetos `Dump`, sin nada de interfaz.

## Antes de empezar

- Leer: [`protocolo.md`](../../../TP3_FINAL/doc/documentation/protocolo.md) completo; [`dump.md`](../../../TP3_FINAL/doc/documentation/dump.md) §1, §4, §5.
- Precondiciones:
  - B-06 y B-07 cerrados: existen `sw/host/proto.py` (constantes del protocolo) y `sw/host/dump.py` (`Dump`, `encode`, `decode`, `expected_length`, `DumpError`).
  - B-09 cerrado: existe `sw/host/stub_model.py` con `stub_dump(cycles, halt_at, timeout=False, aborted=False) -> Dump`.
  - B-16 cerrado: `py TP3_FINAL/tools/run.py tb tb_system_debug` pasa y deja `TP3_FINAL/build/tb_system_debug.bytes.log`.
- Rama: `b/B-23-link`.

## Archivos

| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/host/link.py` | `Link` y errores |
| crear | `TP3_FINAL/sw/host/replay.py` | `ReplayPort` (puerto falso que reproduce un log) |
| crear | `TP3_FINAL/sw/tests/data/tb_system_debug.bytes.log` | Copia del log de B-16 |
| crear | `TP3_FINAL/sw/tests/test_link.py` | Tests |

## Pasos

1. **Interfaz de puerto que usa `Link`** (la cumplen `serial.Serial`, `ReplayPort` y `FakeBoard` de B-24): `write(data: bytes) -> int`, `read(n: int) -> bytes` (devuelve hasta `n` bytes; menos si vence `port.timeout`), atributo `timeout: float | None`, `reset_input_buffer() -> None`, `close() -> None`. `Link` no usa nada más.

2. **Errores:**

   ```python
   class LinkError(Exception): ...
   class LinkTimeout(LinkError): ...      # "timeout esperando <qué> (<n> de <m> bytes)"
   class ProtocolError(LinkError): ...    # byte inesperado: "se esperaba 0x4b, llegó 0x45"
   class DeviceError(LinkError):          # la placa respondió E <code>
       code: int                          # str: "la placa respondió E 02 (N fuera de rango)"
   class ChecksumError(LinkError): ...    # envuelve DumpError
   ```

3. **API de `Link`** (timeouts de `protocolo.md` §6, en segundos, como constantes de módulo):

   ```python
   @dataclass(frozen=True)
   class Version:
       proto: int; imem_words: int; dmem_words: int

   class Link:
       def __init__(self, port) -> None: ...
       @classmethod
       def open(cls, name: str, baud: int = 115200) -> "Link": ...   # serial.Serial(name, baud, timeout=0.05)
       def close(self) -> None: ...
       def connect(self) -> Version: ...          # V; ProtocolError si la cabecera no es 0x56 o proto != 1
       def reset(self) -> None: ...               # X → K
       def load(self, words: list[int]) -> None: ...
       def step(self) -> Dump: ...                # S → dump
       def run(self, abort_after: float | None = None) -> Dump: ...
       def dump(self) -> Dump: ...                # D → dump
       def raw_error(self, cmd: int) -> int: ...  # envía un byte de comando y espera E <code>; devuelve code
       stats: dict[str, int]                      # "discarded": bytes descartados al resincronizar
   ```

   Reglas:
   - **Antes de cada comando**: `port.reset_input_buffer()` (descarta restos de una respuesta anterior rota).
   - Lectura con plazo: `_read_exact(n, timeout, what)` acumula `port.read()` hasta tener `n` bytes o hasta que pase `timeout` (medido con `time.monotonic()`); si no llega, `LinkTimeout`.
   - `load(words)`: si `len(words) > 256` levanta `LinkError("programa de N palabras excede imem (256)")` **sin enviar nada**. Envía `4C NL NH`; lee 1 byte (200 ms): `0x4B` sigue, `0x45` → lee el código y levanta `DeviceError`; otro → `ProtocolError`. Envía las palabras LE en una sola escritura. Lee el `K` final con timeout `0.2 + 4·N·87e-6`.
   - **Lectura de un dump** (`_read_dump(timeout)`): lee de a 1 byte descartando hasta encontrar `0xA5` (cada descartado suma `stats["discarded"]`; si el descartado es `0x45`, lee el siguiente byte y levanta `DeviceError`); después lee 208 bytes (W0..W51), calcula `M` de W51, lee `8·M + 1` bytes más y llama `dump.decode(b"\xa5" + todo)`. `DumpError` → `ChecksumError`. Todo dentro del mismo plazo.
   - `step()`/`dump()`: timeout 0.5 s. `run()`: 4.0 s. Con `abort_after`, si en `abort_after` segundos no llegó ningún byte, envía `0x41` una vez y sigue leyendo el dump en el mismo plazo de 4 s.
   - `connect()`: 6 bytes en 200 ms; guarda `self.version`.

4. **`ReplayPort`** (`replay.py`): reproduce un log de B-16.

   Formato del log (lo escribe el TB de B-16): una línea por byte o por grupo de bytes, `> xx xx ...` lo que mandó el host y `< xx xx ...` lo que respondió la placa, hex en minúsculas o mayúsculas; líneas vacías o que empiezan con `#` se ignoran.

   ```python
   class ReplayPort:
       def __init__(self, log: str | Path, corrupt: dict[int, int] | None = None, truncate_at: int | None = None) -> None: ...
       timeout: float | None
       def write(self, data: bytes) -> int: ...   # compara con los próximos bytes '>' esperados; AssertionError con posición si difiere
       def read(self, n: int) -> bytes: ...       # entrega bytes '<' solo después de que se escribieron todos los '>' que los preceden
       def reset_input_buffer(self) -> None: ...  # descarta los '<' ya liberados y no leídos
       def close(self) -> None: ...
   ```

   `corrupt = {i: v}` reemplaza el i-ésimo byte `<` del log (contando desde 0) por `v`. `truncate_at = i` hace que los `<` desde el índice `i` no se entreguen nunca (simula una respuesta cortada).

5. Copiar `TP3_FINAL/build/tb_system_debug.bytes.log` a `TP3_FINAL/sw/tests/data/` (se versiona; si B-16 cambia el guion, se vuelve a copiar).

6. **Tests** (`test_link.py`):
   - **Guion de B-16 completo** sobre `ReplayPort`: llamar los métodos de `Link` en el mismo orden que el guion de B-16 (`connect`, `load(progA)`, 5 × `step`, `run`, `dump`, `reset`, `load(progB)`, `run`, `raw_error(0x7A)`, `dump`; las palabras de `progA`/`progB` son las del guion de B-16) y comparar cada `Dump` con el esperado de `stub_model.stub_dump(...)` con los mismos argumentos que usa B-16. `raw_error(0x7A) == 1`.
   - **Checksum malo:** `corrupt` sobre un byte de datos del primer dump → `ChecksumError`; el comando siguiente sobre un `ReplayPort` nuevo posicionado ahí funciona (basta verificar que después de la excepción `link.dump()` con un log de un solo `D` válido devuelve el dump).
   - **Respuesta cortada:** `truncate_at` en mitad de un dump → `LinkTimeout` en menos de 0.6 s.
   - **Resincronización:** un puerto falso mínimo (clase en el test) que entrega `b"\x00\x13" + dump_valido` ante `D` → devuelve el dump y `stats["discarded"] == 2`.
   - **`load` sin enviar:** 257 palabras → `LinkError` y el puerto no recibió ningún byte.
   - **`DeviceError`:** puerto falso que responde `45 02` al `L` → `DeviceError` con `code == 2`.
   - **`abort_after`:** puerto falso que no responde a `R` hasta recibir `41` y entonces entrega un dump con `aborted = 1` → `run(abort_after=0.1)` lo devuelve.

## Validación

```
cd TP3_FINAL/sw && py -m pytest -q tests/test_link.py     → todos pasan
```

## Listo cuando

- [ ] El log de B-16 se decodifica a los mismos dumps que verifica el TB (`stub_model`).
- [ ] Checksum incorrecto y timeout levantan errores claros, y el comando siguiente funciona.
- [ ] El guion de B-16 corre contra la placa con el stub (se cierra junto con B-17: `py -m host.cli --port COMx --script tests/data/b16_script.txt`, ver B-25; o un script equivalente en el PR de B-17).

## No hacer

- No usar hilos: `abort_after` se resuelve con el plazo de lectura.
- No importar `tkinter` ni nada de interfaz.
- No duplicar constantes del protocolo: importarlas de `proto.py`.

## Si algo falla

| Síntoma | Qué hacer |
| --- | --- |
| El log de B-16 no tiene el formato del paso 4 | Adaptar solo el parser de `ReplayPort` y anotar el formato real en el PR; no cambiar el TB |
| `proto.py` no tiene una constante que hace falta | Detenerse y preguntar (es un contrato de B-06) |

## Commits

1. `sw-host: link.py con timeouts y resincronización`
2. `sw-host: ReplayPort y tests contra el log de B-16`

## Depende de / bloquea

Depende de: B-06, B-07, B-09, B-16. Bloquea: B-24, B-25, B-26, B-27, cierre de B-17.

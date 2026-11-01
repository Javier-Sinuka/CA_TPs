# B-06 · Protocolo UART v1: revisar, codificar en Python y congelar

`S` · etiquetas `contrato` `bloquea-A` · milestone M1 · **Modelo sugerido:** Haiku · [índice](../README.md)

## Objetivo
`protocolo.md` aprobado por A y marcado "v1 congelada", y `sw/host/proto.py` con sus constantes exactas, probado con pytest.

## Antes de empezar
- Leer: `TP3_FINAL/doc/documentation/protocolo.md` (completo), `convenciones.md` §2, §6, §7.
- Precondiciones: ninguna (M1 arranca en paralelo con M0). Python: `py --version` → `Python 3.14.x`.
- Rama: `b/B-06-protocolo`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/requirements.txt` | Si no existe: el contenido de `convenciones.md` §2 |
| crear | `TP3_FINAL/sw/host/__init__.py` | Vacío (si no existe) |
| crear | `TP3_FINAL/sw/host/proto.py` | Código de abajo, literal |
| crear | `TP3_FINAL/sw/tests/test_proto.py` | Código de abajo, literal |
| modificar | `TP3_FINAL/doc/documentation/protocolo.md` | Solo la línea de estado (paso 4) y lo que pida A |

## Pasos
1. Instalar dependencias: `py -m pip install -r TP3_FINAL/sw/requirements.txt`.
   Verificar: `py -m pytest --version` → `pytest 8.x`.
2. Crear `TP3_FINAL/sw/host/proto.py`:

```python
"""Constantes del protocolo UART v1 (doc/documentation/protocolo.md).

No editar sin cambiar antes el contrato y avisar a A.
"""

BAUD_RATE = 115_200

# Comandos (protocolo.md §3)
CMD_VERSION = 0x56  # 'V'
CMD_RESET = 0x58    # 'X'
CMD_LOAD = 0x4C     # 'L'
CMD_STEP = 0x53     # 'S'
CMD_RUN = 0x52      # 'R'
CMD_ABORT = 0x41    # 'A'
CMD_DUMP = 0x44     # 'D'

# Respuestas
RESP_OK = 0x4B          # 'K'
RESP_ERR = 0x45         # 'E'
DUMP_HEADER = 0xA5
VERSION_HEADER = 0x56

# Códigos de error (protocolo.md §3)
ERR_UNKNOWN_CMD = 0x01
ERR_N_RANGE = 0x02
ERR_BYTE_TIMEOUT = 0x03

PROTO_VERSION = 0x01
IMEM_WORDS = 256
DMEM_WORDS = 256
HALT_WORD = 0x0000_0073

VERSION_RESPONSE = bytes([
    VERSION_HEADER, PROTO_VERSION,
    IMEM_WORDS & 0xFF, IMEM_WORDS >> 8,
    DMEM_WORDS & 0xFF, DMEM_WORDS >> 8,
])

# Timeouts del host en segundos (protocolo.md §6)
TIMEOUT_SHORT_S = 0.2
TIMEOUT_DUMP_S = 0.5
TIMEOUT_RUN_S = 4.0


def timeout_load_final_s(n_words: int) -> float:
    """Timeout para el 'K' final de L con n_words palabras."""
    return 0.2 + 4 * n_words * 87e-6
```

3. Crear `TP3_FINAL/sw/tests/test_proto.py`:

```python
from host import proto


def test_version_response_literal() -> None:
    assert proto.VERSION_RESPONSE == bytes.fromhex("560100010001")


def test_command_bytes_are_ascii() -> None:
    assert [chr(c) for c in (proto.CMD_VERSION, proto.CMD_RESET, proto.CMD_LOAD,
                             proto.CMD_STEP, proto.CMD_RUN, proto.CMD_ABORT,
                             proto.CMD_DUMP)] == list("VXLSRAD")
    assert chr(proto.RESP_OK) == "K" and chr(proto.RESP_ERR) == "E"


def test_headers_do_not_collide() -> None:
    assert proto.DUMP_HEADER not in (proto.VERSION_HEADER, proto.RESP_OK, proto.RESP_ERR)


def test_load_timeout_grows_with_n() -> None:
    assert proto.timeout_load_final_s(0) == 0.2
    assert abs(proto.timeout_load_final_s(256) - (0.2 + 0.089088)) < 1e-9
```

   Verificar (desde `TP3_FINAL/sw`): `py -m pytest tests/test_proto.py -q` → `4 passed`.
4. Revisión con A. Abrir el PR con `protocolo.md` y pedirle a A que confirme, uno por uno, estos puntos (pegar la lista en la descripción del PR):
   - [ ] Comandos y bytes de §3, errores 01/02/03.
   - [ ] `L` en dos fases (§4) y relleno con HALT de `imem[N..255]`.
   - [ ] Reglas de byte pendiente y de `A` (§2).
   - [ ] Parámetros de §5 (`RUN_TIMEOUT` = 150 000 000, `BYTE_TIMEOUT` = `CLOCK_FREQ/10`).
   - [ ] Vectores de §7.
   Si A pide un cambio: aplicarlo **en `protocolo.md` y en `proto.py` en el mismo commit**, y anotar el porqué en `decisiones.md`. Si el cambio toca algo de `debug_unit` ya escrito, detenerse y avisar.
5. Con la aprobación, cambiar la primera línea en negrita de `protocolo.md` a: `**Estado: v1 congelada (aprobada por A el AAAA-MM-DD, PR #n).**`

## Validación
- `cd TP3_FINAL/sw; py -m pytest tests/test_proto.py -q` → `4 passed`.
- `py TP3_FINAL/tools/run.py pytest` → código 0 (si el runner de B-04 todavía no existe, alcanza con el comando anterior).

## Listo cuando
- [ ] `proto.py` y `test_proto.py` existen con el contenido de arriba y los 4 tests pasan.
- [ ] A aprobó el PR (la lista del paso 4 tildada en el PR).
- [ ] `protocolo.md` dice "v1 congelada" con fecha y PR.

## No hacer
- No escribir `link.py` ni nada de comunicación serie (eso es B-23).
- No cambiar valores de `proto.py` sin cambiar `protocolo.md` en el mismo commit.

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| `ModuleNotFoundError: host` | Correr pytest con `cwd = TP3_FINAL/sw` y verificar que existe `sw/host/__init__.py` |
| `python` abre la Microsoft Store | Usar `py` (convenciones.md §2) |
| A propone un cambio de protocolo grande (comandos nuevos) | Detenerse; anotar el pedido y consultar antes de editar |

## Commits
1. `sw-host: constantes del protocolo v1 en proto.py`
2. `docs: protocolo v1 congelado` (solo la línea de estado y cambios pedidos por A)

## Depende de / bloquea
Depende de: nada. Bloquea: B-10, B-13, B-23, B-24.

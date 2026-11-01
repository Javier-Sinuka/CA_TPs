# B-07 · Formato del dump v1: `dump.py`, `canonical.py` y congelar

`M` · etiquetas `contrato` `bloquea-A` · milestone M1 · **Modelo sugerido:** Haiku (el código está dado) · [índice](../README.md)

## Objetivo
`sw/host/dump.py` y `sw/host/canonical.py` implementan exactamente `dump.md`, con round-trip probado, y `dump.md` queda aprobado por A con un ejemplo hex real.

## Antes de empezar
- Leer: `TP3_FINAL/doc/documentation/dump.md` (completo), `convenciones.md` §6.
- Precondiciones: B-06 tiene `sw/host/__init__.py` y `requirements.txt` (si B-06 no está mergeado, crearlos igual que ahí).
- Rama: `b/B-07-dump`.

## Archivos
| Acción | Ruta | Contenido |
| --- | --- | --- |
| crear | `TP3_FINAL/sw/host/dump.py` | Código de abajo, literal |
| crear | `TP3_FINAL/sw/host/canonical.py` | Código de abajo, literal |
| crear | `TP3_FINAL/sw/tests/test_dump.py` | Código de abajo, literal |
| crear | `TP3_FINAL/sw/tests/test_canonical.py` | Código de abajo, literal |
| modificar | `TP3_FINAL/doc/documentation/dump.md` | Agregar §7 "Ejemplos" (paso 5) y la línea de estado (paso 7) |

## Pasos
1. Crear `TP3_FINAL/sw/host/dump.py`:

```python
"""Codificación y decodificación del dump v1 (doc/documentation/dump.md)."""
from __future__ import annotations

import struct
from dataclasses import dataclass

HEADER = 0xA5
FORMAT_VERSION = 0x01
N_FIXED_WORDS = 52          # W0..W51
N_REGS = 32
N_LATCHES = 16
MAX_DIRTY = 256
MASK32 = 0xFFFF_FFFF


class DumpError(Exception):
    """Dump mal formado: cabecera, largo o checksum."""


# (campo, bit menos significativo, ancho) — dump.md §3.1
_INFO_FIELDS: tuple[tuple[str, int, int], ...] = (
    ("rd", 0, 5), ("rs1", 5, 5), ("rs2", 10, 5), ("funct3", 15, 3),
    ("alu_op", 18, 4), ("alu_src_b", 22, 1), ("mem_read", 23, 1),
    ("mem_write", 24, 1), ("mem_to_reg", 25, 1), ("reg_write", 26, 1),
    ("branch", 27, 1), ("jump", 28, 1), ("jalr", 29, 1), ("lui", 30, 1),
    ("halt", 31, 1),
)


@dataclass(frozen=True)
class LatchInfo:
    rd: int = 0
    rs1: int = 0
    rs2: int = 0
    funct3: int = 0
    alu_op: int = 0
    alu_src_b: bool = False
    mem_read: bool = False
    mem_write: bool = False
    mem_to_reg: bool = False
    reg_write: bool = False
    branch: bool = False
    jump: bool = False
    jalr: bool = False
    lui: bool = False
    halt: bool = False

    @staticmethod
    def unpack(word: int) -> "LatchInfo":
        fields: dict[str, int | bool] = {}
        for name, lsb, width in _INFO_FIELDS:
            value = (word >> lsb) & ((1 << width) - 1)
            fields[name] = bool(value) if width == 1 else value
        return LatchInfo(**fields)  # type: ignore[arg-type]

    def pack(self) -> int:
        word = 0
        for name, lsb, width in _INFO_FIELDS:
            value = int(getattr(self, name))
            if not 0 <= value < (1 << width):
                raise ValueError(f"{name}={value} no entra en {width} bits")
            word |= value << lsb
        return word


@dataclass(frozen=True)
class Dump:
    halted: bool
    timeout: bool
    aborted: bool
    version: int
    cycles: int
    pc: int
    x: tuple[int, ...]                  # 32 valores
    latches: tuple[int, ...]            # 16 palabras crudas
    mem: tuple[tuple[int, int], ...]    # (dirección en bytes, dato), ascendente

    @property
    def info_ex(self) -> LatchInfo:
        return LatchInfo.unpack(self.latches[6])

    @property
    def info_mem(self) -> LatchInfo:
        return LatchInfo.unpack(self.latches[10])

    @property
    def info_wb(self) -> LatchInfo:
        return LatchInfo.unpack(self.latches[14])

    def _flag(self, bit: int) -> bool:
        return bool((self.latches[15] >> bit) & 1)

    @property
    def valid_id(self) -> bool:
        return self._flag(0)

    @property
    def valid_ex(self) -> bool:
        return self._flag(1)

    @property
    def valid_mem(self) -> bool:
        return self._flag(2)

    @property
    def valid_wb(self) -> bool:
        return self._flag(3)

    @property
    def load_use_stall(self) -> bool:
        return self._flag(5)

    @property
    def take_ex(self) -> bool:
        return self._flag(6)

    @property
    def stop_fetch(self) -> bool:
        return self._flag(7)


def expected_length(m: int) -> int:
    """Largo total en bytes de un dump con m palabras sucias."""
    return 1 + 4 * N_FIXED_WORDS + 8 * m + 1


def _status_word(d: Dump) -> int:
    return (int(d.halted) | (int(d.timeout) << 1) | (int(d.aborted) << 2)
            | ((d.version & 0xFF) << 8))


def encode(d: Dump) -> bytes:
    if len(d.x) != N_REGS or len(d.latches) != N_LATCHES:
        raise ValueError("x debe tener 32 valores y latches 16")
    if len(d.mem) > MAX_DIRTY:
        raise ValueError("más de 256 palabras sucias")
    words = [_status_word(d), d.cycles, d.pc, *d.x, *d.latches, len(d.mem)]
    for addr, data in d.mem:
        words += [addr, data]
    body = b"".join(struct.pack("<I", w & MASK32) for w in words)
    return bytes([HEADER]) + body + bytes([sum(body) & 0xFF])


def decode(b: bytes) -> Dump:
    b = bytes(b)
    if len(b) < expected_length(0):
        raise DumpError(f"dump corto: {len(b)} bytes, mínimo {expected_length(0)}")
    if b[0] != HEADER:
        raise DumpError(f"cabecera 0x{b[0]:02x}, se esperaba 0x{HEADER:02x}")
    m = struct.unpack_from("<I", b, 1 + 4 * 51)[0]
    if m > MAX_DIRTY:
        raise DumpError(f"M = {m} > {MAX_DIRTY}")
    if len(b) != expected_length(m):
        raise DumpError(f"largo {len(b)}, se esperaba {expected_length(m)} para M = {m}")
    body = b[1:-1]
    if sum(body) & 0xFF != b[-1]:
        raise DumpError(f"checksum 0x{b[-1]:02x}, calculado 0x{sum(body) & 0xFF:02x}")
    words = struct.unpack(f"<{len(body) // 4}I", body)
    status = words[0]
    pairs = words[N_FIXED_WORDS:]
    return Dump(
        halted=bool(status & 1),
        timeout=bool((status >> 1) & 1),
        aborted=bool((status >> 2) & 1),
        version=(status >> 8) & 0xFF,
        cycles=words[1],
        pc=words[2],
        x=tuple(words[3:35]),
        latches=tuple(words[35:51]),
        mem=tuple((pairs[2 * i], pairs[2 * i + 1]) for i in range(m)),
    )
```

2. Crear `TP3_FINAL/sw/host/canonical.py`:

```python
"""Formato canónico de resultados (doc/documentation/dump.md §6)."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from host.dump import Dump


def hex32(value: int) -> str:
    return f"0x{value & 0xFFFF_FFFF:08x}"


def from_dump(d: Dump) -> dict[str, Any]:
    """Dump de una parada (halted o timeout) a formato canónico."""
    if d.halted:
        stop = "halt"
    elif d.timeout:
        stop = "limit"
    else:
        raise ValueError("el dump no es de una parada: ni halted ni timeout")
    return {
        "stop": stop,
        "pc": hex32(d.latches[11]) if stop == "halt" else None,
        "x": [hex32(v) for v in d.x],
        "mem": [[hex32(a), hex32(v)] for a, v in d.mem],
    }


def load(path: str | Path) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def save(result: dict[str, Any], path: str | Path) -> None:
    Path(path).write_text(json.dumps(result, indent=1) + "\n", encoding="utf-8")


def diff(a: dict[str, Any], b: dict[str, Any], la: str = "a", lb: str = "b") -> list[str]:
    """Una línea por diferencia. Lista vacía = iguales."""
    if a["stop"] != b["stop"]:
        return [f"stop: {la}={a['stop']} {lb}={b['stop']}"]
    if a["stop"] == "limit":
        return []
    out: list[str] = []
    if a["pc"] != b["pc"]:
        out.append(f"pc: {la}={a['pc']} {lb}={b['pc']}")
    for i, (va, vb) in enumerate(zip(a["x"], b["x"])):
        if va != vb:
            out.append(f"x{i}: {la}={va} {lb}={vb}")
    ma = {addr: val for addr, val in a["mem"]}
    mb = {addr: val for addr, val in b["mem"]}
    for addr in sorted(set(ma) | set(mb), key=lambda s: int(s, 16)):
        va, vb = ma.get(addr, "-"), mb.get(addr, "-")
        if va != vb:
            out.append(f"mem[{addr}]: {la}={va} {lb}={vb}")
    return out
```

3. Crear `TP3_FINAL/sw/tests/test_dump.py`:

```python
import random

import pytest

from host.dump import Dump, DumpError, LatchInfo, decode, encode, expected_length


def random_dump(rng: random.Random) -> Dump:
    m = rng.choice([0, 1, 3, 256, rng.randint(0, 256)])
    idxs = sorted(rng.sample(range(256), m))
    return Dump(
        halted=rng.random() < 0.5, timeout=rng.random() < 0.5,
        aborted=rng.random() < 0.5, version=rng.randint(0, 255),
        cycles=rng.getrandbits(32), pc=rng.getrandbits(32),
        x=tuple(rng.getrandbits(32) for _ in range(32)),
        latches=tuple(rng.getrandbits(32) for _ in range(16)),
        mem=tuple((i * 4, rng.getrandbits(32)) for i in idxs),
    )


def test_round_trip_1000() -> None:
    rng = random.Random(1234)
    for _ in range(1000):
        d = random_dump(rng)
        b = encode(d)
        assert len(b) == expected_length(len(d.mem))
        assert decode(b) == d


@pytest.mark.parametrize("m,length", [(0, 210), (1, 218), (3, 234), (256, 2258)])
def test_expected_length(m: int, length: int) -> None:
    assert expected_length(m) == length


def test_any_altered_byte_is_rejected() -> None:
    b = encode(random_dump(random.Random(7)))
    for i in range(len(b)):
        bad = bytearray(b)
        bad[i] ^= 0x01
        with pytest.raises(DumpError):
            decode(bytes(bad))


def test_truncated_is_rejected() -> None:
    b = encode(random_dump(random.Random(8)))
    with pytest.raises(DumpError):
        decode(b[:-1])


def test_latch_info_layout() -> None:
    assert LatchInfo(rd=5, reg_write=True, halt=True).pack() == 0x8400_0005
    assert LatchInfo(rs1=31).pack() == 31 << 5
    assert LatchInfo(alu_op=0xF, funct3=7).pack() == (0xF << 18) | (7 << 15)
    rng = random.Random(9)
    for _ in range(200):
        w = rng.getrandbits(32)
        assert LatchInfo.unpack(w).pack() == w


def test_status_bits() -> None:
    d = decode(encode(Dump(True, False, True, 1, 0, 0, (0,) * 32, (0,) * 16, ())))
    assert (d.halted, d.timeout, d.aborted, d.version) == (True, False, True, 1)
    assert encode(Dump(True, False, True, 1, 0, 0, (0,) * 32, (0,) * 16, ()))[1:5] == bytes([0x05, 0x01, 0, 0])
```

4. Crear `TP3_FINAL/sw/tests/test_canonical.py`:

```python
from host import canonical
from host.dump import Dump


def make(halted: bool = True, timeout: bool = False, x5: int = 5) -> Dump:
    x = tuple(x5 if i == 5 else 0 for i in range(32))
    latches = tuple(0x40 if k == 11 else 0 for k in range(16))
    return Dump(halted, timeout, False, 1, 10, 0x44, x, latches, ((0, 55),))


def test_from_dump_halt() -> None:
    c = canonical.from_dump(make())
    assert c["stop"] == "halt" and c["pc"] == "0x00000040"
    assert c["x"][5] == "0x00000005" and c["mem"] == [["0x00000000", "0x00000037"]]


def test_from_dump_limit_has_null_pc() -> None:
    c = canonical.from_dump(make(halted=False, timeout=True))
    assert c["stop"] == "limit" and c["pc"] is None


def test_diff() -> None:
    a = canonical.from_dump(make())
    b = canonical.from_dump(make(x5=6))
    assert canonical.diff(a, a) == []
    assert canonical.diff(a, b, "iss", "rtl") == ["x5: iss=0x00000005 rtl=0x00000006"]


def test_diff_limit_only_compares_stop() -> None:
    a = canonical.from_dump(make(halted=False, timeout=True))
    b = canonical.from_dump(make(halted=False, timeout=True, x5=9))
    assert canonical.diff(a, b) == []
```

   Verificar (desde `TP3_FINAL/sw`): `py -m pytest tests/test_dump.py tests/test_canonical.py -q` → `13 passed` (9 de `test_dump.py`, contando los 4 casos parametrizados, y 4 de `test_canonical.py`).
5. Ejemplos en `dump.md`. Desde `TP3_FINAL/sw` correr:

```
py -c "from host.dump import Dump, encode; d = Dump(False, False, False, 1, 0, 0, tuple(range(32)), tuple(0x1A000000 | (k << 16) for k in range(16)), ()); b = encode(d); print(len(b)); print(' '.join(f'{v:02x}' for v in b))"
py -c "from host.dump import Dump, encode; d = Dump(False, False, False, 1, 1, 4, tuple([0] + [(1 << 8) | i for i in range(1, 32)]), tuple(0x1A000000 | (k << 16) | 1 for k in range(16)), ((16, 0xD0000004), (64, 0xD0000010), (252, 0xD000003F))); b = encode(d); print(len(b)); print(' '.join(f'{v:02x}' for v in b))"
```

   El primero tiene que imprimir `210` y el segundo `234`. Son los dumps del `cpu_stub` con 0 y 1 ciclos (B-09 los vuelve a generar con `stub_dump(0, 20)` y `stub_dump(1, 20)` y tienen que dar idénticos). Agregar al final de `dump.md` una sección `## 7. Ejemplos` con dos bloques de código titulados `stub_dump(0, 20)` y `stub_dump(1, 20)`, cada uno con la salida hex partida en líneas de 16 bytes.
6. Revisión con A. Pegar en el PR y pedir que A tilde:
   - [ ] Mapa de §1 (52 palabras fijas, pares en bytes, checksum §4).
   - [ ] Palabras de latch de §3 y nombres de señales (`pc_id`, `rs1_data_ex`, ...).
   - [ ] Layout de info §3.1, con los nombres de puertos de `control.v`.
   - [ ] Palabra 15 (§3.2): A va a exponer `load_use_stall`, `take_ex`, `stop_fetch`.
   - [ ] Formato canónico §6 (`pc` sale de `pc_wb`).
   Si A cambia un layout: actualizar `dump.md` **y** `_INFO_FIELDS` / índices de `dump.py` en el mismo commit, y volver a correr el paso 5.
7. Con la aprobación: primera línea de `dump.md` → `**Estado: v1 congelada (aprobada por A el AAAA-MM-DD, PR #n).**`

## Validación
- `cd TP3_FINAL/sw; py -m pytest tests/test_dump.py tests/test_canonical.py -q` → 0 failed.
- Los dos comandos del paso 5 imprimen `210` y `234`.

## Listo cuando
- [ ] Round-trip `decode(encode(x)) == x` para 1000 dumps aleatorios (`test_round_trip_1000`).
- [ ] Cualquier byte alterado se rechaza (`test_any_altered_byte_is_rejected`) y el largo es `210 + 8·M`.
- [ ] `dump.md` tiene la §7 con los dos ejemplos.
- [ ] A aprobó el layout (lista del paso 6 tildada) y `dump.md` dice "v1 congelada".

## No hacer
- No agregar campos al dump ni cambiar el checksum.
- No escribir `stub_model.py` (B-09).

## Si algo falla
| Síntoma | Qué hacer |
| --- | --- |
| `test_any_altered_byte_is_rejected` no levanta en algún índice | Revisar que `decode` verifique cabecera, largo y checksum en ese orden, como el código dado |
| Error de sintaxis `int | bool` | Confirmar Python 3.14 con `py --version` |

## Commits
1. `sw-host: dump.py y canonical.py con tests`
2. `docs: ejemplos y congelado del dump v1`

## Depende de / bloquea
Depende de: B-06 (estructura de `sw/host`). Bloquea: B-09, B-14, B-23, B-24, B-27.

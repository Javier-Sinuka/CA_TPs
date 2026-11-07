"""Puerto falso que reproduce un log de bytes del TB de B-16 (tb_system_debug.bytes.log).

Formato: una línea por byte o grupo de bytes, `> xx xx` lo que mandó el host y
`< xx xx` lo que respondió la placa. Las líneas vacías o que empiezan con `#`
se ignoran.
"""
from __future__ import annotations

import time
from pathlib import Path


class ReplayPort:
    def __init__(self, log: str | Path, corrupt: dict[int, int] | None = None,
                 truncate_at: int | None = None) -> None:
        self.timeout: float | None = 0.05
        self._out: list[int] = []         # bytes '>' (host -> placa), en orden
        self._in: list[int] = []          # bytes '<' (placa -> host), en orden
        self._need: list[int] = []        # '>' que preceden a cada '<'
        for n, raw in enumerate(Path(log).read_text().splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            kind, _, rest = line.partition(" ")
            if kind not in (">", "<"):
                raise ValueError(f"{log}:{n}: línea inválida: {raw!r}")
            values = [int(tok, 16) for tok in rest.split()]
            if kind == ">":
                self._out += values
            else:
                self._in += values
                self._need += [len(self._out)] * len(values)
        self._corrupt = dict(corrupt or {})
        self._limit = len(self._in) if truncate_at is None else min(truncate_at, len(self._in))
        self._written = 0
        self._read = 0

    @property
    def written(self) -> int:
        """Cantidad de bytes '>' que el host ya escribió."""
        return self._written

    @property
    def done(self) -> bool:
        """El host escribió todos los '>' y leyó todos los '<' del log."""
        return self._written == len(self._out) and self._read == len(self._in)

    def _available(self) -> int:
        end = self._read
        while end < self._limit and self._need[end] <= self._written:
            end += 1
        return end - self._read

    def write(self, data: bytes) -> int:
        for b in data:
            if self._written >= len(self._out):
                raise AssertionError(
                    f"byte {self._written} escrito (0x{b:02x}): el log no esperaba más")
            if b != self._out[self._written]:
                raise AssertionError(
                    f"byte {self._written} escrito: 0x{b:02x}, "
                    f"el log esperaba 0x{self._out[self._written]:02x}")
            self._written += 1
        return len(data)

    def read(self, n: int) -> bytes:
        avail = self._available()
        if avail < n and self.timeout:
            time.sleep(self.timeout)
        k = min(n, avail)
        out = bytes(self._corrupt.get(i, self._in[i])
                    for i in range(self._read, self._read + k))
        self._read += k
        return out

    def reset_input_buffer(self) -> None:
        self._read += self._available()

    def close(self) -> None:
        pass

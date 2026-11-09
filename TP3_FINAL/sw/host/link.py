"""Enlace serie del protocolo UART v1 (doc/documentation/protocolo.md).

`Link` usa solo la API mínima de `serial.Serial`: write(data), read(n),
timeout, reset_input_buffer() y close(). Sin hilos ni interfaz gráfica.
"""
from __future__ import annotations

import struct
import time
from dataclasses import dataclass

from host import proto
from host.dump import (HEADER, MAX_DIRTY, N_FIXED_WORDS, Dump, DumpError,
                       decode)

_ERROR_TEXT = {
    proto.ERR_UNKNOWN_CMD: "comando desconocido",
    proto.ERR_N_RANGE: "N fuera de rango",
    proto.ERR_BYTE_TIMEOUT: "timeout entre bytes en L",
}


class LinkError(Exception):
    """Error genérico del enlace."""


class LinkTimeout(LinkError):
    """La placa no respondió a tiempo."""


class ProtocolError(LinkError):
    """Llegó un byte que el protocolo no permite en ese momento."""


class DeviceError(LinkError):
    """La placa respondió `E <code>`."""

    def __init__(self, code: int) -> None:
        self.code = code
        text = _ERROR_TEXT.get(code, "código desconocido")
        super().__init__(f"la placa respondió E {code:02x} ({text})")


class ChecksumError(LinkError):
    """Dump mal formado (envuelve DumpError)."""


@dataclass(frozen=True)
class Version:
    proto: int
    imem_words: int
    dmem_words: int


class Link:
    def __init__(self, port) -> None:
        self.port = port
        self.version: Version | None = None
        self.stats: dict[str, int] = {"discarded": 0}

    @classmethod
    def open(cls, name: str, baud: int = proto.BAUD_RATE) -> "Link":
        import serial

        return cls(serial.Serial(name, baud, timeout=0.05))

    def close(self) -> None:
        self.port.close()

    # ------------------------------------------------------------------ comandos

    def connect(self) -> Version:
        self._start(proto.CMD_VERSION)
        r = self._read_exact(len(proto.VERSION_RESPONSE), proto.TIMEOUT_SHORT_S,
                             "versión")
        if r[0] != proto.VERSION_HEADER:
            raise ProtocolError(
                f"se esperaba 0x{proto.VERSION_HEADER:02x}, llegó 0x{r[0]:02x}")
        if r[1] != proto.PROTO_VERSION:
            raise ProtocolError(
                f"protocolo {r[1]}, este host habla {proto.PROTO_VERSION}")
        self.version = Version(r[1], r[2] | (r[3] << 8), r[4] | (r[5] << 8))
        return self.version

    def reset(self) -> None:
        self._start(proto.CMD_RESET)
        self._expect_ok(proto.TIMEOUT_SHORT_S, "K de reset")

    def load(self, words: list[int]) -> None:
        n = len(words)
        if n > proto.IMEM_WORDS:
            raise LinkError(
                f"programa de {n} palabras excede imem ({proto.IMEM_WORDS})")
        if any(not 0 <= w <= 0xFFFF_FFFF for w in words):
            raise LinkError("palabra fuera de 32 bits")
        self._start(proto.CMD_LOAD, bytes([n & 0xFF, n >> 8]))
        self._expect_ok(proto.TIMEOUT_SHORT_S, "primer K de L")
        if n:
            self.port.write(struct.pack(f"<{n}I", *words))
        self._expect_ok(proto.timeout_load_final_s(n), "K final de L")

    def step(self) -> Dump:
        self._start(proto.CMD_STEP)
        return self._read_dump(proto.TIMEOUT_DUMP_S)

    def run(self, abort_after: float | None = None) -> Dump:
        self._start(proto.CMD_RUN)
        return self._read_dump(proto.TIMEOUT_RUN_S, abort_after)

    def dump(self) -> Dump:
        self._start(proto.CMD_DUMP)
        return self._read_dump(proto.TIMEOUT_DUMP_S)

    def raw_error(self, cmd: int) -> int:
        self._start(cmd)
        b = self._read_exact(1, proto.TIMEOUT_SHORT_S, "E de error")
        if b[0] != proto.RESP_ERR:
            raise ProtocolError(f"se esperaba 0x{proto.RESP_ERR:02x}, llegó 0x{b[0]:02x}")
        return self._read_exact(1, proto.TIMEOUT_SHORT_S, "código de error")[0]

    # ------------------------------------------------------------------ interno

    def _start(self, cmd: int, extra: bytes = b"") -> None:
        self.port.reset_input_buffer()
        self.port.write(bytes([cmd]) + extra)

    def _read_exact(self, n: int, timeout: float, what: str) -> bytes:
        return self._read_by(n, time.monotonic() + timeout, what)

    def _read_by(self, n: int, deadline: float, what: str) -> bytes:
        buf = bytearray()
        while True:
            buf += self.port.read(n - len(buf))
            if len(buf) >= n:
                return bytes(buf)
            if time.monotonic() >= deadline:
                raise LinkTimeout(
                    f"timeout esperando {what} ({len(buf)} de {n} bytes)")

    def _expect_ok(self, timeout: float, what: str) -> None:
        deadline = time.monotonic() + timeout
        b = self._read_by(1, deadline, what)[0]
        if b == proto.RESP_ERR:
            raise DeviceError(self._read_by(1, deadline + proto.TIMEOUT_SHORT_S,
                                            "código de error")[0])
        if b != proto.RESP_OK:
            raise ProtocolError(f"se esperaba 0x{proto.RESP_OK:02x}, llegó 0x{b:02x}")

    def _read_dump(self, timeout: float, abort_after: float | None = None) -> Dump:
        start = time.monotonic()
        deadline = start + timeout
        abort_pending = abort_after is not None
        while True:
            b = self.port.read(1)
            if b:
                abort_pending = False
                if b[0] == HEADER:
                    break
                self.stats["discarded"] += 1
                if b[0] == proto.RESP_ERR:
                    raise DeviceError(self._read_by(1, deadline, "código de error")[0])
                continue
            now = time.monotonic()
            if abort_pending and now - start >= abort_after:
                self.port.write(bytes([proto.CMD_ABORT]))
                abort_pending = False
            if now >= deadline:
                raise LinkTimeout("timeout esperando cabecera del dump (0 de 1 bytes)")
        fixed = self._read_by(4 * N_FIXED_WORDS, deadline, "cuerpo fijo del dump")
        m = struct.unpack_from("<I", fixed, 4 * (N_FIXED_WORDS - 1))[0]
        if m > MAX_DIRTY:
            raise ChecksumError(f"dump con M = {m} > {MAX_DIRTY}")
        tail = self._read_by(8 * m + 1, deadline, "palabras sucias y checksum del dump")
        try:
            return decode(bytes([HEADER]) + fixed + tail)
        except DumpError as e:
            raise ChecksumError(str(e)) from e

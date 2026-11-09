"""Tests de host/link.py contra el log de B-16 y puertos falsos."""
import time
from pathlib import Path

import pytest

from host import proto
from host.dump import encode
from host.link import (ChecksumError, DeviceError, Link, LinkError,
                       LinkTimeout, ProtocolError, Version)
from host.replay import ReplayPort
from host.stub_model import stub_dump

LOG = Path(__file__).parent / "data" / "tb_system_debug.bytes.log"
HALT_AT = 20
PROG_A = [0xA000_0000 + i for i in range(37)]
PROG_B = [0x0050_0093, 0x0000_0073]
# Indices '<' del log: V = 0..5, K K de `L A` = 6..7, primer dump (`S 1`) desde 8.
FIRST_DUMP = 8


def _log_bytes(kind: str) -> list[int]:
    out: list[int] = []
    for line in LOG.read_text().splitlines():
        if line.startswith(kind + " "):
            out += [int(t, 16) for t in line[2:].split()]
    return out


class ScriptPort:
    """Puerto falso mínimo: `on_write(port, data)` decide qué responde."""

    def __init__(self, on_write=None) -> None:
        self.timeout = 0.01
        self.rx = bytearray()
        self.tx = bytearray()
        self.on_write = on_write

    def write(self, data: bytes) -> int:
        self.tx += data
        if self.on_write:
            self.on_write(self, bytes(data))
        return len(data)

    def read(self, n: int) -> bytes:
        if len(self.rx) < n:
            time.sleep(self.timeout)
        out = bytes(self.rx[:n])
        del self.rx[:n]
        return out

    def reset_input_buffer(self) -> None:
        self.rx.clear()

    def close(self) -> None:
        pass


def test_guion_b16_completo():
    port = ReplayPort(LOG)
    link = Link(port)
    assert link.connect() == Version(proto=1, imem_words=256, dmem_words=256)
    link.load(PROG_A)
    for k in range(1, 6):
        assert link.step() == stub_dump(k, HALT_AT)
    final = stub_dump(HALT_AT, HALT_AT)
    assert link.run() == final
    assert link.dump() == final
    link.reset()
    link.load(PROG_B)
    assert link.run() == final
    assert link.raw_error(0x7A) == proto.ERR_UNKNOWN_CMD == 1
    assert link.dump() == final
    assert port.done
    assert link.stats["discarded"] == 0


def test_checksum_malo_y_comando_siguiente(tmp_path):
    i = FIRST_DUMP + 100
    bad = _log_bytes("<")[i] ^ 0xFF
    link = Link(ReplayPort(LOG, corrupt={i: bad}))
    link.connect()
    link.load(PROG_A)
    with pytest.raises(ChecksumError, match="checksum"):
        link.step()

    d = stub_dump(HALT_AT, HALT_AT)
    one = tmp_path / "un_dump.log"
    one.write_text("> 44\n< " + " ".join(f"{b:02x}" for b in encode(d)) + "\n")
    link.port = ReplayPort(one)
    assert link.dump() == d


def test_respuesta_cortada_da_timeout():
    port = ReplayPort(LOG, truncate_at=FIRST_DUMP + 100)
    port.timeout = 0.01
    link = Link(port)
    link.connect()
    link.load(PROG_A)
    t0 = time.monotonic()
    with pytest.raises(LinkTimeout, match="de .* bytes"):
        link.step()
    assert time.monotonic() - t0 < 0.6


def test_resincronizacion_descarta_basura():
    d = stub_dump(3, HALT_AT)

    def on_write(port, data):
        if data == b"D":
            port.rx += b"\x00\x13" + encode(d)

    link = Link(ScriptPort(on_write))
    assert link.dump() == d
    assert link.stats["discarded"] == 2


def test_load_demasiado_grande_no_envia_nada():
    port = ScriptPort()
    link = Link(port)
    with pytest.raises(LinkError, match="257 palabras excede imem"):
        link.load([0] * 257)
    assert bytes(port.tx) == b""


def test_load_error_de_la_placa():
    def on_write(port, data):
        if data[:1] == b"L":
            port.rx += b"\x45\x02"

    port = ScriptPort(on_write)
    link = Link(port)
    with pytest.raises(DeviceError, match="E 02 .N fuera de rango.") as e:
        link.load([0x13])
    assert e.value.code == 2
    assert bytes(port.tx) == b"\x4c\x01\x00"


def test_run_con_abort_after():
    d = stub_dump(7, HALT_AT, aborted=True)

    def on_write(port, data):
        if data == b"A":
            port.rx += encode(d)

    port = ScriptPort(on_write)
    link = Link(port)
    got = link.run(abort_after=0.1)
    assert got == d and got.aborted
    assert bytes(port.tx) == b"RA"


def test_run_sin_abort_after_no_manda_a():
    d = stub_dump(HALT_AT, HALT_AT)

    def on_write(port, data):
        if data == b"R":
            port.rx += encode(d)

    port = ScriptPort(on_write)
    assert Link(port).run(abort_after=1.0) == d
    assert bytes(port.tx) == b"R"


def test_connect_rechaza_otro_protocolo():
    def on_write(port, data):
        port.rx += bytes([0x56, 0x02, 0, 1, 0, 1])

    with pytest.raises(ProtocolError, match="protocolo 2"):
        Link(ScriptPort(on_write)).connect()


def test_reset_byte_inesperado():
    def on_write(port, data):
        port.rx += b"\x41"

    with pytest.raises(ProtocolError, match="se esperaba 0x4b, llegó 0x41"):
        Link(ScriptPort(on_write)).reset()

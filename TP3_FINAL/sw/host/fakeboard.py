"""Placa simulada: responde el protocolo UART v1 ejecutando el ISS (build/iss.exe).

No hay un segundo ISS en Python: la placa guarda imem y la cantidad de
instrucciones ejecutadas `k`, y cada vez que necesita el estado corre
`iss.exe <hex> --max-instr k --full` desde cero. Tiene la API de puerto que
usa `host.link.Link` (write, read, reset_input_buffer, close, timeout).
"""
from __future__ import annotations

import json
import re
import subprocess
import tempfile
from pathlib import Path

from host import proto
from host.dump import FORMAT_VERSION, MASK32, Dump, encode

_HALT_INFO = 0x8000_0000    # palabra info con el bit `halt` (dump.md §3.1)
_VALID_WB = 0x0000_0008     # latch 15, bit 3 (dump.md §3.2)
_HALTED = 0x0000_0010       # latch 15, bit 4


class FakeBoard:
    def __init__(self, iss_exe: str | Path, run_limit: int = 1_000_000,
                 fault: dict[str, int] | None = None) -> None:
        self.timeout: float | None = None
        self._exe = str(iss_exe)
        self._run_limit = run_limit
        self._fault: dict[int, int] = {}
        for key, value in (fault or {}).items():
            m = re.fullmatch(r"x(\d+)", key)
            if not m or not 1 <= int(m.group(1)) <= 31:
                raise ValueError(f"fault: clave inválida {key!r} (se espera x1..x31)")
            self._fault[int(m.group(1))] = value & MASK32
        self._tmp = tempfile.TemporaryDirectory(prefix="fakeboard_")
        self._hex = Path(self._tmp.name) / "prog.hex"
        self._imem = [proto.HALT_WORD] * proto.IMEM_WORDS
        self._k = 0
        self._halted = False
        self._timeout_flag = False
        self._aborted_flag = False
        self._out = bytearray()
        self._state = "idle"        # idle, l_lo, l_hi, l_data
        self._n = 0
        self._data = bytearray()

    # ------------------------------------------------------------------ API de puerto

    def write(self, data: bytes) -> int:
        for b in data:
            self._byte(b)
        return len(data)

    def read(self, n: int) -> bytes:
        out = bytes(self._out[:n])
        del self._out[:n]
        return out

    def reset_input_buffer(self) -> None:
        self._out.clear()

    def close(self) -> None:
        self._tmp.cleanup()

    # ------------------------------------------------------------------ comandos

    def _byte(self, b: int) -> None:
        if self._state == "idle":
            self._command(b)
        elif self._state == "l_lo":
            self._n = b
            self._state = "l_hi"
        elif self._state == "l_hi":
            self._n |= b << 8
            if self._n > proto.IMEM_WORDS:
                self._out += bytes([proto.RESP_ERR, proto.ERR_N_RANGE])
                self._state = "idle"
                return
            self._out.append(proto.RESP_OK)
            self._data.clear()
            if self._n == 0:
                self._finish_load()
            else:
                self._state = "l_data"
        else:
            self._data.append(b)
            if len(self._data) == 4 * self._n:
                self._finish_load()

    def _command(self, b: int) -> None:
        if b == proto.CMD_VERSION:
            self._out += proto.VERSION_RESPONSE
        elif b == proto.CMD_RESET:
            self._k = 0
            self._clear_state()
            self._out.append(proto.RESP_OK)
        elif b == proto.CMD_LOAD:
            self._state = "l_lo"
        elif b == proto.CMD_STEP:
            if not self._halted:
                self._k += 1
            self._timeout_flag = self._aborted_flag = False
            self._emit(self._run_iss(self._k))
        elif b == proto.CMD_RUN:
            self._timeout_flag = self._aborted_flag = False
            res = self._run_iss(self._run_limit)
            self._timeout_flag = res["stop"] == "limit"
            self._k = res["instret"]
            self._emit(res)
        elif b == proto.CMD_ABORT:
            pass    # la R simulada es instantánea
        elif b == proto.CMD_DUMP:
            self._emit(self._run_iss(self._k))
        else:
            self._out += bytes([proto.RESP_ERR, proto.ERR_UNKNOWN_CMD])

    def _finish_load(self) -> None:
        for i in range(self._n):
            self._imem[i] = int.from_bytes(self._data[4 * i:4 * i + 4], "little")
        for i in range(self._n, proto.IMEM_WORDS):
            self._imem[i] = proto.HALT_WORD
        self._k = 0
        self._clear_state()
        self._out.append(proto.RESP_OK)
        self._state = "idle"

    def _clear_state(self) -> None:
        self._halted = False
        self._timeout_flag = self._aborted_flag = False

    # ------------------------------------------------------------------ ISS

    def _run_iss(self, max_instr: int) -> dict:
        self._hex.write_text("".join(f"{w:08x}\n" for w in self._imem), encoding="ascii")
        r = subprocess.run([self._exe, str(self._hex), "--max-instr", str(max_instr),
                            "--full"], capture_output=True)
        if r.returncode != 0:
            raise RuntimeError(f"iss.exe terminó con código {r.returncode}: "
                               f"{r.stderr.decode('utf-8', 'replace').strip()}")
        return json.loads(r.stdout)

    def _emit(self, res: dict) -> None:
        self._halted = res["stop"] == "halt"
        x = [int(v, 16) for v in res["x"]]
        for i, v in self._fault.items():
            x[i] = v
        latches = [0] * 16
        if self._halted:
            latches[11] = int(res["pc"], 16)
            latches[14] = _HALT_INFO
            latches[15] = _VALID_WB | _HALTED
        elif self._k < self._run_limit:
            latches[15] = _VALID_WB
        d = Dump(halted=self._halted, timeout=self._timeout_flag,
                 aborted=self._aborted_flag, version=FORMAT_VERSION,
                 cycles=self._k, pc=int(res["next_pc"], 16), x=tuple(x),
                 latches=tuple(latches),
                 mem=tuple((int(a, 16), int(v, 16)) for a, v in res["mem"]))
        self._out += encode(d)

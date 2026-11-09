"""Prueba de eco contra top_uart_echo (B-05).

Uso (cwd = TP3_FINAL/sw):
    py -m host.echo_test --port COM5 --count 100000 --burst 256 --seed 1
Devuelve 0 si no hubo bytes errados ni perdidos, 1 si los hubo, 2 si no se pudo usar el puerto.
"""
from __future__ import annotations

import argparse
import random
import sys
import time

import serial


def run(port: str, baud: int, count: int, burst: int, seed: int) -> tuple[int, int, int, int, float]:
    """Envía count bytes pseudoaleatorios en ráfagas y compara el eco de cada ráfaga."""
    rng = random.Random(seed)
    sent = received = wrong = lost = 0
    t0 = time.monotonic()
    with serial.Serial(port, baud, timeout=0.05) as ser:
        time.sleep(0.1)
        ser.reset_input_buffer()
        remaining = count
        while remaining > 0:
            n = min(burst, remaining)
            data = bytes(rng.randrange(256) for _ in range(n))
            ser.write(data)
            sent += n
            # Tiempo de línea de la ráfaga (10 bits por byte) dos veces, más 0,5 s de margen.
            deadline = time.monotonic() + 0.5 + 2 * n * 10 / baud
            buf = bytearray()
            while len(buf) < n and time.monotonic() < deadline:
                buf += ser.read(n - len(buf))
            received += len(buf)
            lost += n - len(buf)
            wrong += sum(1 for a, b in zip(data, buf) if a != b)
            if len(buf) < n:
                # Faltaron bytes: descartar lo que llegue tarde para que la ráfaga siguiente arranque limpia.
                time.sleep(0.1)
                ser.reset_input_buffer()
            remaining -= n
    return sent, received, wrong, lost, time.monotonic() - t0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Eco UART contra top_uart_echo")
    p.add_argument("--port", required=True, help="por ejemplo COM5")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--count", type=int, default=100_000)
    p.add_argument("--burst", type=int, default=256)
    p.add_argument("--seed", type=int, default=1)
    a = p.parse_args(argv)
    try:
        sent, received, wrong, lost, dt = run(a.port, a.baud, a.count, a.burst, a.seed)
    except serial.SerialException as e:
        print(f"ERROR: no se pudo usar {a.port}: {e}", file=sys.stderr)
        return 2
    print(f"sent={sent} received={received} wrong={wrong} lost={lost} "
          f"time={dt:.1f}s port={a.port} baud={a.baud} burst={a.burst} seed={a.seed}")
    return 0 if wrong == 0 and lost == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

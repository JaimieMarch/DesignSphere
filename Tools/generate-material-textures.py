#!/usr/bin/env python3
"""Generate original, seamless tangent-space normal maps; no source images.

The PNG assets are project-owned output of the mathematical fields below.
Only Python's standard library is required. Run from any working directory.
"""

import math
from pathlib import Path
import struct
import zlib


SIZE = 256
OUTPUT = Path(__file__).resolve().parents[1] / "Demo App Vision" / "Textures"
TAU = math.tau


def wood(u: float, v: float) -> float:
    grain = 14 * u + 0.35 * math.sin(TAU * v) + 0.12 * math.sin(TAU * 3 * v)
    return 0.004 * math.sin(TAU * grain) + 0.0007 * math.sin(TAU * 47 * u)


def fabric(u: float, v: float) -> float:
    return 0.002 * (math.cos(TAU * 32 * u) + math.cos(TAU * 32 * v))


def leather(u: float, v: float) -> float:
    return sum(
        math.sin(TAU * (a * u + b * v) + phase) * amplitude
        for a, b, phase, amplitude in [
            (17, 23, 0.2, 0.0012), (31, -19, 1.7, 0.001),
            (43, 37, 3.1, 0.0006), (11, -41, 2.4, 0.0007),
        ]
    )


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def normal_map(field) -> bytes:
    rows = bytearray()
    step = 1 / SIZE
    for y in range(SIZE):
        rows.append(0)  # PNG filter: none
        v = y / SIZE
        for x in range(SIZE):
            u = x / SIZE
            nx = -(field(u + step, v) - field(u - step, v)) / (2 * step)
            ny = -(field(u, v + step) - field(u, v - step)) / (2 * step)
            length = math.sqrt(nx * nx + ny * ny + 1)
            rows.extend(round((component / length + 1) * 127.5) for component in (nx, ny, 1))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows, level=9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, field in [("wood_grain", wood), ("fabric", fabric), ("leather", leather)]:
        path = OUTPUT / f"{name}.png"
        path.write_bytes(normal_map(field))
        print(f"{path.name}: {path.stat().st_size} bytes")

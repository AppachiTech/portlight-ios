#!/usr/bin/env python3
"""Draws the Portlight app icon (1024x1024 PNG) with no image libraries:
a brass portlight with eight bolts around dark glass and a >_ prompt.
Rendered at 2x and box-filtered down for anti-aliasing."""
import math
import pathlib
import struct
import zlib

SIZE = 1024
SS = 2  # supersampling factor
N = SIZE * SS
C = N / 2


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


BG_TOP, BG_BOTTOM = hexrgb("#16262F"), hexrgb("#0A1116")
BRASS_LIGHT, BRASS_DARK = hexrgb("#FFD27A"), hexrgb("#B87708")
BOLT, BOLT_HI = hexrgb("#7A4E08"), hexrgb("#E9B04C")
GLASS_CENTER, GLASS_EDGE = hexrgb("#24465A"), hexrgb("#0C1820")
PROMPT = hexrgb("#F5A524")

R_OUTER, R_INNER = 0.40 * N, 0.295 * N
R_BOLT_RING, R_BOLT = 0.3475 * N, 0.024 * N


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


# The prompt: a chevron and an underscore, in units of N.
STROKE = 0.045 * N
CHEVRON = [(0.385 * N, 0.415 * N), (0.485 * N, 0.5 * N), (0.385 * N, 0.585 * N)]
UNDERSCORE = [(0.53 * N, 0.585 * N), (0.635 * N, 0.585 * N)]
bolts = [(C + R_BOLT_RING * math.cos(k * math.pi / 4 + math.pi / 8),
          C + R_BOLT_RING * math.sin(k * math.pi / 4 + math.pi / 8)) for k in range(8)]


def pixel(x, y):
    dx, dy = x - C, y - C
    r = math.hypot(dx, dy)
    color = mix(BG_TOP, BG_BOTTOM, y / N)
    # Soft shadow under the portlight.
    if r < R_OUTER * 1.06:
        shade = max(0.0, 1 - (r - R_OUTER) / (R_OUTER * 0.06)) if r > R_OUTER else 1.0
        color = mix(color, (0, 0, 0), 0.35 * shade)
    if r <= R_OUTER:
        if r >= R_INNER:
            # Brass: lit from the top left, with a bevel toward each edge.
            light = 0.5 - 0.5 * (dx + dy) / (math.sqrt(2) * R_OUTER)
            bevel = abs((r - R_INNER) / (R_OUTER - R_INNER) - 0.5) * 2
            color = mix(BRASS_DARK, BRASS_LIGHT, light * (1 - 0.35 * bevel) + 0.1)
            for bx, by in bolts:
                d = math.hypot(x - bx, y - by)
                if d <= R_BOLT:
                    hi = max(0.0, 1 - math.hypot(x - (bx - R_BOLT * 0.35), y - (by - R_BOLT * 0.35)) / R_BOLT)
                    color = mix(BOLT, BOLT_HI, hi)
        else:
            # Glass: radial gradient plus a highlight arc at the top left.
            color = mix(GLASS_CENTER, GLASS_EDGE, (r / R_INNER) ** 1.4)
            ang = math.atan2(dy, dx)
            if 0.72 * R_INNER < r < 0.86 * R_INNER and -2.6 < ang < -1.7:
                fade = 1 - abs((ang + 2.15) / 0.45)
                color = mix(color, (255, 255, 255), 0.10 * max(0.0, fade))
            d = min(seg_dist(x, y, *CHEVRON[0], *CHEVRON[1]), seg_dist(x, y, *CHEVRON[1], *CHEVRON[2]),
                    seg_dist(x, y, *UNDERSCORE[0], *UNDERSCORE[1]))
            if d <= STROKE / 2:
                color = PROMPT
    return color


def main():
    rows = []
    for Y in range(SIZE):
        row = bytearray([0])  # PNG filter: none
        for X in range(SIZE):
            acc = [0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    c = pixel(X * SS + sx + 0.5, Y * SS + sy + 0.5)
                    acc[0] += c[0]
                    acc[1] += c[1]
                    acc[2] += c[2]
            row += bytes(int(round(v / (SS * SS))) for v in acc)
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    out = pathlib.Path(__file__).resolve().parent.parent / "App/Portlight/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png)
    print(f"wrote {out} ({len(png)} bytes)")


if __name__ == "__main__":
    main()

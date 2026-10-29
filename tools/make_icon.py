#!/usr/bin/env python3
"""Generates the Guild Census addon icon (pie chart on a gold-bordered tile).

Pure standard library. Usage: python3 tools/make_icon.py [OUT_DIR] [--preview-dir DIR]
Writes OUT_DIR/icon.tga (default: GuildCensus/), which the TOC references via IconTexture.
"""
import math
import struct
import sys
import zlib
from pathlib import Path

SIZE = 64        # WoW textures must be power-of-two
SAMPLES = 8      # SAMPLES x SAMPLES supersampling per pixel

BACKGROUND = (27, 31, 42)
BORDER = (212, 160, 23)
SEPARATOR = (27, 31, 42)
# (fraction, colour): roughly a believable roles pie, clockwise from 12 o'clock.
SLICES = [
    (0.45, (52, 152, 219)),   # DPS
    (0.25, (46, 204, 113)),   # healers
    (0.18, (231, 76, 60)),    # tanks
    (0.12, (241, 196, 15)),   # other
]

CORNER_RADIUS = 11.0
BORDER_WIDTH = 3.0
PIE_RADIUS = 22.0
GAP_DEGREES = 2.5


def in_rounded_square(x, y, inset=0.0):
    half = SIZE / 2 - inset
    radius = max(CORNER_RADIUS - inset, 0.0)
    dx, dy = abs(x - SIZE / 2) - (half - radius), abs(y - SIZE / 2) - (half - radius)
    if dx <= 0 or dy <= 0:
        return abs(x - SIZE / 2) <= half and abs(y - SIZE / 2) <= half
    return dx * dx + dy * dy <= radius * radius


def slice_colour(angle_degrees):
    """Colour of the pie at an angle measured clockwise from 12 o'clock, or None on a gap."""
    start = 0.0
    for fraction, colour in SLICES:
        end = start + fraction * 360.0
        if start <= angle_degrees < end:
            near_edge = min(angle_degrees - start, end - angle_degrees)
            return SEPARATOR if near_edge < GAP_DEGREES / 2 else colour
        start = end
    return SLICES[-1][1]


def sample(x, y):
    """RGBA of the point (x, y), y down."""
    if not in_rounded_square(x, y):
        return (0, 0, 0, 0)
    if not in_rounded_square(x, y, BORDER_WIDTH):
        return BORDER + (255,)
    dx, dy = x - SIZE / 2, y - SIZE / 2
    if dx * dx + dy * dy <= PIE_RADIUS * PIE_RADIUS:
        angle = math.degrees(math.atan2(dx, -dy)) % 360.0
        return slice_colour(angle) + (255,)
    return BACKGROUND + (255,)


def render():
    pixels = []
    for py in range(SIZE):
        row = []
        for px in range(SIZE):
            r = g = b = a = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    cr, cg, cb, ca = sample(px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES)
                    # premultiply so transparent samples don't bleed black into edges
                    r, g, b, a = r + cr * ca, g + cg * ca, b + cb * ca, a + ca
            n = SAMPLES * SAMPLES
            if a == 0:
                row.append((0, 0, 0, 0))
            else:
                row.append((round(r / a), round(g / a), round(b / a), round(a / n)))
        pixels.append(row)
    return pixels


def write_tga(path, pixels):
    # Uncompressed 32-bit, bottom-left origin (rows written bottom to top).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x08)
    body = bytearray()
    for row in reversed(pixels):
        for r, g, b, a in row:
            body += bytes((b, g, r, a))
    Path(path).write_bytes(header + bytes(body))


def write_png(path, pixels):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    Path(path).write_bytes(png)


def main(argv):
    preview_dir = None
    args = list(argv)
    if "--preview-dir" in args:
        i = args.index("--preview-dir")
        preview_dir = Path(args[i + 1])
        del args[i:i + 2]
    out_dir = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "GuildCensus"

    pixels = render()
    out_dir.mkdir(parents=True, exist_ok=True)
    write_tga(out_dir / "icon.tga", pixels)
    print("wrote", out_dir / "icon.tga")
    if preview_dir:
        preview_dir.mkdir(parents=True, exist_ok=True)
        write_png(preview_dir / "icon.png", pixels)
        print("wrote", preview_dir / "icon.png")


if __name__ == "__main__":
    main(sys.argv[1:])

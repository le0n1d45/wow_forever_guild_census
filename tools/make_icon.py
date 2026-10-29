#!/usr/bin/env python3
"""Generates the Guild Census addon icon (pie chart on a gold-bordered tile).

Usage: python3 tools/make_icon.py [OUT_DIR] [--preview-dir DIR] [--size N] [--jpeg PATH]

Writes OUT_DIR/icon.tga (default: GuildCensus/), which the TOC references via IconTexture.
The TGA is always 64x64 (WoW wants small power-of-two textures). --size only affects the
PNG preview and the JPEG. The default run needs only the standard library; --jpeg needs
Pillow (pip install pillow), since JPEG encoding isn't in the standard library. JPEG has
no alpha, so the transparent corners are flattened onto white.
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


def render(size=SIZE):
    """Renders at `size` pixels square; the design is defined on the 64x64 grid and scaled."""
    samples = SAMPLES if size <= 128 else 3
    scale = SIZE / size
    pixels = []
    for py in range(size):
        row = []
        for px in range(size):
            r = g = b = a = 0.0
            for sy in range(samples):
                for sx in range(samples):
                    cr, cg, cb, ca = sample((px + (sx + 0.5) / samples) * scale,
                                            (py + (sy + 0.5) / samples) * scale)
                    # premultiply so transparent samples don't bleed black into edges
                    r, g, b, a = r + cr * ca, g + cg * ca, b + cb * ca, a + ca
            n = samples * samples
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
    size = len(pixels)
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw += bytes((r, g, b, a))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    Path(path).write_bytes(png)


def write_jpeg(path, pixels):
    try:
        from PIL import Image
    except ImportError:
        sys.exit("--jpeg needs Pillow: pip install pillow")
    size = len(pixels)
    image = Image.new("RGBA", (size, size))
    image.putdata([px for row in pixels for px in row])
    flat = Image.new("RGB", (size, size), (255, 255, 255))
    flat.paste(image, mask=image.getchannel("A"))
    flat.save(path, "JPEG", quality=95, subsampling=0)


def take_option(args, name):
    if name not in args:
        return None
    i = args.index(name)
    value = args[i + 1]
    del args[i:i + 2]
    return value


def main(argv):
    args = list(argv)
    preview_dir = take_option(args, "--preview-dir")
    jpeg_path = take_option(args, "--jpeg")
    size = int(take_option(args, "--size") or SIZE)
    out_dir = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "GuildCensus"

    out_dir.mkdir(parents=True, exist_ok=True)
    write_tga(out_dir / "icon.tga", render())
    print("wrote", out_dir / "icon.tga")

    if preview_dir or jpeg_path:
        large = render(size) if size != SIZE else render()
        if preview_dir:
            Path(preview_dir).mkdir(parents=True, exist_ok=True)
            write_png(Path(preview_dir) / "icon.png", large)
            print("wrote", Path(preview_dir) / "icon.png")
        if jpeg_path:
            write_jpeg(jpeg_path, large)
            print("wrote", jpeg_path)


if __name__ == "__main__":
    main(sys.argv[1:])

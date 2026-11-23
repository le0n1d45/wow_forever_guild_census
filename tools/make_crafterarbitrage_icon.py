#!/usr/bin/env python3
"""Generates the CrafterArbitrage addon icon (a gold coin on the same gold-bordered tile as Guild Census).

Usage: python3 tools/make_crafterarbitrage_icon.py [OUT_DIR] [--preview-dir DIR] [--size N]

Writes OUT_DIR/icon.tga (default: CrafterArbitrage/), which the TOC references via IconTexture, and with
--preview-dir a PNG at --size pixels. Reuses the tile, border and renderer from make_icon.py, so it
needs only the standard library.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_icon as base  # noqa: E402

COIN, COIN_EDGE, COIN_MARK = (241, 196, 15), (183, 134, 11), (120, 85, 8)
COIN_RADIUS, RIM = 21.0, 3.0
MARK_HALF_WIDTH, MARK_HEIGHT = 2.2, 11.0  # the vertical bar of a "$"-like mark
ARROW_HALF = 8.0  # an arrow pointing up inside the coin: profit


def sample(x, y):
    """RGBA of the point (x, y), y down: the base tile with a coin drawn over it."""
    r, g, b, a = base_sample(x, y)
    if a == 0 or (r, g, b) == base.BORDER:
        return (r, g, b, a)
    dx, dy = x - base.SIZE / 2, y - base.SIZE / 2
    distance = (dx * dx + dy * dy) ** 0.5
    if distance > COIN_RADIUS:
        return (r, g, b, a)
    if distance > COIN_RADIUS - RIM:
        return COIN_EDGE + (255,)
    shaft = abs(dx) <= MARK_HALF_WIDTH and -MARK_HEIGHT <= dy <= MARK_HEIGHT
    head = dy < -MARK_HEIGHT + 6 and dy >= -MARK_HEIGHT - 2 and abs(dx) <= (dy + MARK_HEIGHT + 2) * 1.0 + 0.0
    if shaft or head:
        return COIN_MARK + (255,)
    return COIN + (255,)


def main(argv):
    args = list(argv)
    preview_dir = base.take_option(args, "--preview-dir")
    size = int(base.take_option(args, "--size") or base.SIZE)
    out_dir = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "CrafterArbitrage"

    base.PIE_RADIUS = 0.0  # the base tile has a pie chart; draw our own background instead
    out_dir.mkdir(parents=True, exist_ok=True)
    base.write_tga(out_dir / "icon.tga", base.render())
    print("wrote", out_dir / "icon.tga")
    if preview_dir:
        Path(preview_dir).mkdir(parents=True, exist_ok=True)
        base.write_png(Path(preview_dir) / "crafterarbitrage-icon.png", base.render(size))
        print("wrote", Path(preview_dir) / "crafterarbitrage-icon.png")


base_sample = base.sample
base.sample = sample

if __name__ == "__main__":
    main(sys.argv[1:])

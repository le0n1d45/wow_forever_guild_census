#!/usr/bin/env python3
"""Generates the MobHunter addon icon (a red crosshair on the same gold-bordered tile as Guild Census).

Usage: python3 tools/make_mobhunter_icon.py [OUT_DIR] [--preview-dir DIR] [--size N]

Writes OUT_DIR/icon.tga (default: MobHunter/), which the TOC references via IconTexture, and with
--preview-dir a PNG at --size pixels. Reuses the tile, border and renderer from make_icon.py, so it
needs only the standard library.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_icon as base  # noqa: E402

RETICLE = (231, 76, 60)
RING_INNER, RING_OUTER = 17.5, 21.0
TICK_START, TICK_END, TICK_HALF_WIDTH = 8.0, 27.0, 1.6
DOT_RADIUS = 3.2


def sample(x, y):
    """RGBA of the point (x, y), y down: the base tile with a crosshair drawn over it."""
    r, g, b, a = base_sample(x, y)
    if a == 0 or (r, g, b) == base.BORDER:
        return (r, g, b, a)
    dx, dy = x - base.SIZE / 2, y - base.SIZE / 2
    distance = (dx * dx + dy * dy) ** 0.5
    on_ring = RING_INNER <= distance <= RING_OUTER
    on_tick = ((TICK_START <= abs(dx) <= TICK_END and abs(dy) <= TICK_HALF_WIDTH)
               or (TICK_START <= abs(dy) <= TICK_END and abs(dx) <= TICK_HALF_WIDTH))
    if on_ring or on_tick or distance <= DOT_RADIUS:
        return RETICLE + (255,)
    return (r, g, b, a)


def main(argv):
    args = list(argv)
    preview_dir = base.take_option(args, "--preview-dir")
    size = int(base.take_option(args, "--size") or base.SIZE)
    out_dir = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "MobHunter"

    # The base tile has a pie chart; draw our own background instead of its pie.
    base.PIE_RADIUS = 0.0
    out_dir.mkdir(parents=True, exist_ok=True)
    base.write_tga(out_dir / "icon.tga", base.render())
    print("wrote", out_dir / "icon.tga")
    if preview_dir:
        Path(preview_dir).mkdir(parents=True, exist_ok=True)
        base.write_png(Path(preview_dir) / "mobhunter-icon.png", base.render(size))
        print("wrote", Path(preview_dir) / "mobhunter-icon.png")


base_sample = base.sample
base.sample = sample

if __name__ == "__main__":
    main(sys.argv[1:])

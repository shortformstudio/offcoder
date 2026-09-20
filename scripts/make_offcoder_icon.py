#!/usr/bin/env python3
"""
Offcoder icon — moonpond language: deep ink field, alchemy-gradient ring, gold pond mark.
Generates Offcoder.iconset and compiles Offcoder.icns via iconutil.
"""

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

INK = (18, 24, 22, 255)
ALCHEMY = [
    (230, 208, 206, 255),
    (212, 223, 216, 255),
    (196, 201, 214, 255),
    (232, 213, 181, 255),
]
GOLD = (201, 164, 92, 255)
EGGSHELL = (252, 252, 252, 255)

SIZE = 1024
ICONSET_SIZES = [16, 32, 64, 128, 256, 512, 1024]


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_icon(size: int = SIZE) -> Image.Image:
    scale = size / SIZE
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    radius = int(230 * scale)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=INK)

    # alchemy-gradient ring (four arcs, one per pigment)
    inset = int(196 * scale)
    ring_width = max(2, int(30 * scale))
    bbox = [inset, inset, size - inset - 1, size - inset - 1]
    for index, color in enumerate(ALCHEMY):
        start = 90 * index - 45
        draw.arc(bbox, start=start, end=start + 90, fill=color, width=ring_width)

    # pond mark — gold center, eggshell echo
    center = size / 2
    dot = int(58 * scale)
    draw.ellipse([center - dot, center - dot, center + dot, center + dot], fill=GOLD)
    echo = int(20 * scale)
    draw.ellipse([center - echo, center - echo, center + echo, center + echo], fill=EGGSHELL)

    return img


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "dist"
    iconset = out_dir / "Offcoder.iconset"
    iconset.mkdir(parents=True, exist_ok=True)

    master = draw_icon()
    master = Image.composite(master, Image.new("RGBA", master.size, (0, 0, 0, 0)), rounded_mask(SIZE, 230))

    for base in ICONSET_SIZES:
        for suffix, px in ((f"{base}x{base}", base), (f"{base}x{base}@2x", base * 2)):
            if px > SIZE:
                continue
            resized = master.resize((px, px), Image.LANCZOS)
            resized.save(iconset / f"icon_{suffix}.png")

    icns_path = out_dir / "Offcoder.icns"
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns_path)], check=True)
    print(f"[icon] wrote {icns_path}")


if __name__ == "__main__":
    main()

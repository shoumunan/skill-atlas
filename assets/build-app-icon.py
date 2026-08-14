#!/usr/bin/env python3
"""Build a Dock-sized Skill Atlas icon for macOS that does not auto-mask icns.

Tahoe draws a traditional icns at bitmap size. A full-bleed square therefore
appears as a huge white tile next to WeChat. Keep the original rounded plate
and shrink it onto a transparent 1024 canvas so the optical mass matches
other dock icons.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent
SOURCE = ROOT / "SkillAtlas-AppIcon-clean-1024.png"
MASTER = ROOT / "SkillAtlas-AppIcon-1024.png"
PREVIEW = ROOT / "SkillAtlas-AppIcon-preview.png"
DOCK_PROOF = ROOT / "SkillAtlas-AppIcon-dock-proof.png"
ICONSET = PROJECT / "native" / "SkillAtlas.iconset"

# 900/1024 ≈ 88%. 98% overflowed the dock; 75% sat smaller than Word.
PLATE = 900

ICONSET_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def compose_master(src: Image.Image) -> Image.Image:
    src = src.convert("RGBA")
    if src.size != (1024, 1024):
        src = src.resize((1024, 1024), Image.Resampling.LANCZOS)
    scaled = src.resize((PLATE, PLATE), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    offset = (1024 - PLATE) // 2
    canvas.paste(scaled, (offset, offset), scaled)
    return canvas


def downscale(master: Image.Image, size: int) -> Image.Image:
    image = master.resize((size, size), Image.Resampling.LANCZOS)
    if size <= 64:
        image = ImageEnhance.Contrast(image).enhance(1.08)
        image = image.filter(ImageFilter.UnsharpMask(radius=0.55, percent=90, threshold=2))
    return image


def write_preview(master: Image.Image) -> None:
    board = Image.new("RGB", (1280, 720), (236, 236, 240))
    draw = ImageDraw.Draw(board)
    draw.rounded_rectangle((48, 48, 1232, 672), radius=28, fill=(255, 255, 255))

    light_bg = Image.new("RGBA", (320, 320), (236, 236, 240, 255))
    light = master.resize((320, 320), Image.Resampling.LANCZOS)
    light_bg.alpha_composite(light)
    board.paste(light_bg.convert("RGB"), (100, 130))

    dark_bg = Image.new("RGBA", (320, 320), (28, 28, 30, 255))
    dark = master.resize((320, 320), Image.Resampling.LANCZOS)
    dark_bg.alpha_composite(dark)
    board.paste(dark_bg.convert("RGB"), (460, 130))

    x = 1000
    for size in (16, 32, 64, 128):
        thumb = downscale(master, size)
        y = 560 - size
        slot = Image.new("RGBA", (size, size), (236, 236, 240, 255))
        slot.alpha_composite(thumb)
        board.paste(slot.convert("RGB"), (x - size // 2, y))
        x -= max(36, size + 18)

    board.save(PREVIEW, "PNG")

    dock = Image.new("RGB", (720, 168), (186, 190, 196))
    dock_draw = ImageDraw.Draw(dock)
    dock_draw.rounded_rectangle((16, 20, 704, 148), radius=28, fill=(210, 214, 220))
    tile = 84
    gap = 22
    start = 40
    for index, color in enumerate(((10, 132, 255), (46, 181, 93), (120, 92, 214), None)):
        x = start + index * (tile + gap)
        y = 42
        if color is None:
            slot = Image.new("RGBA", (tile, tile), (210, 214, 220, 255))
            icon = master.resize((tile, tile), Image.Resampling.LANCZOS)
            slot.alpha_composite(icon)
            dock.paste(slot.convert("RGB"), (x, y))
        else:
            dock_draw.rounded_rectangle((x, y, x + tile, y + tile), radius=19, fill=color)
    dock.save(DOCK_PROOF, "PNG")


def main() -> None:
    master = compose_master(Image.open(SOURCE))
    master.save(MASTER, "PNG")
    ICONSET.mkdir(parents=True, exist_ok=True)
    for name, size in ICONSET_SIZES.items():
        downscale(master, size).save(ICONSET / name, "PNG")
    write_preview(master)
    print(f"wrote {MASTER} plate={PLATE}")
    print(f"wrote {ICONSET}")


if __name__ == "__main__":
    main()

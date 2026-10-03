"""Tile route 3 check: procedural flat ground at true game scale beside the style anchor.

    python tools/comfy/ground_check.py

Writes docs/mockups/bakeoff/ground_procedural.png (each fill tiled 3 x 3) and
docs/mockups/bakeoff/ground_scene.png (a small road scene at 1:1 game scale next to a
crop of the style anchor). Colours are sampled from the anchor, not invented.
"""
from pathlib import Path

from PIL import Image, ImageDraw

import postprocess as pp

ROOT = Path(__file__).resolve().parents[2]
MOCKUPS = ROOT / "docs" / "mockups"
OUT = MOCKUPS / "bakeoff"
TILE = 128

# Sampled from style_anchor.png: clean road patches have a std of only 1-2, and the
# grass runs olive (130,155,58) in shade to lime (202,216,79) in light.
FILLS = {
    "asphalt": dict(base=(102, 109, 116), variation=0.015, speckle_density=0.002, speckle_shift=8, seed=1),
    "grass": dict(base=(168, 190, 68), variation=0.022, waves=7, speckle_density=0.0015, speckle_shift=14, seed=2),
    "grass_shade": dict(base=(140, 165, 60), variation=0.022, waves=7, speckle_density=0.0015, speckle_shift=14, seed=3),
    "sand": dict(base=(232, 204, 122), variation=0.04, speckle_density=0.004, speckle_shift=10, seed=4),
}
KERB_RED = (196, 47, 47)
KERB_CREAM = (231, 231, 171)


def scene(fills: dict[str, Image.Image]) -> Image.Image:
    w_tiles, h_tiles = 8, 5
    img = Image.new("RGB", (w_tiles * TILE, h_tiles * TILE))
    for ty in range(h_tiles):
        for tx in range(w_tiles):
            road = 1 <= ty <= 3
            img.paste(fills["asphalt" if road else "grass"], (tx * TILE, ty * TILE))
    kerb = pp.kerb_strip(w_tiles * TILE, red=KERB_RED, cream=KERB_CREAM)
    img.paste(kerb, (0, TILE - 4), kerb)
    bottom = kerb.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    img.paste(bottom, (0, 4 * TILE - kerb.height + 4), bottom)
    draw = ImageDraw.Draw(img)
    for x in range(40, w_tiles * TILE, 220):  # lane dashes, as in the anchor
        draw.rounded_rectangle((x, int(2.5 * TILE) - 6, x + 90, int(2.5 * TILE) + 6), radius=6, fill=(236, 236, 225))
    car = Image.open(MOCKUPS / "raw" / "car_sports_cutout.png").rotate(90, expand=True)
    car = pp.fit_sprite(car, (128, 72))
    img.paste(car, (int(3.2 * TILE), int(1.8 * TILE)), car)
    return img


def main() -> None:
    fills = {name: pp.flat_fill(TILE, **kw) for name, kw in FILLS.items()}
    for name, tile in fills.items():
        tile.save(OUT / f"ground_{name}_128.png")
    cells = [(pp.tile_grid(tile), f"{name}: procedural, 3x3") for name, tile in fills.items()]
    pp.contact_sheet(cells, 4, (384, 384), "ROUTE 3: FLAT PROCEDURAL FILLS, ANCHOR COLOURS").save(OUT / "ground_procedural.png")

    ours = scene(fills)
    anchor = Image.open(MOCKUPS / "style_anchor.png").convert("RGB").crop((440, 430, 840, 680))  # 8:5, same aspect as the scene
    sheet = pp.contact_sheet([(ours, "procedural ground, 1:1 game scale"), (anchor, "style anchor (frame 04), scaled")],
                             2, (ours.width // 2, ours.height // 2), "GROUND CHECK")
    sheet.save(OUT / "ground_scene.png")
    print("wrote ground_procedural.png and ground_scene.png")


if __name__ == "__main__":
    main()

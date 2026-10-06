"""Free Drive's drawn town textures (docs/DESIGN.md §19): the pavement and the zebra crossing,
and the title's TOWN button icon (the built candy shop with room round it, so it sits inside
the button's rounded end).

    python tools/layouts/town_art.py

Like the ground fills (tools/comfy/pipeline.json `ground`) these are flat procedural colour,
not generated: FLUX cannot make tileable ground. The pavement is the shared flat-fill noise
with paving-slab joints drawn on top, every 64 px so the 128 px tile wraps.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "comfy"))
import postprocess as pp  # noqa: E402

OUT = ROOT / "art" / "town"
PAVEMENT = (222, 214, 200)
JOINT = (198, 189, 174)
SLAB = 64


def pavement() -> Image.Image:
    tile = pp.flat_fill(128, PAVEMENT, variation=0.025, waves=4, speckle_density=0.003, speckle_shift=8, seed=7)
    draw = ImageDraw.Draw(tile)
    for k in range(0, 128, SLAB):
        draw.rectangle((k, 0, k + 1, 127), fill=JOINT)
        draw.rectangle((0, k, 127, k + 1), fill=JOINT)
    return tile


def zebra(along: int = 96, across: int = 296, bar: int = 26, gap: int = 22) -> Image.Image:
    """White bars across the road, as the sprite lies before turning to the road's heading
    (x along the road, y across it)."""
    img = Image.new("RGBA", (along, across), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    y = (across - ((across + gap) // (bar + gap)) * (bar + gap) + gap) // 2
    while y + bar <= across:
        draw.rounded_rectangle((0, y, along - 1, y + bar - 1), 6, fill=(244, 244, 238, 235))
        y += bar + gap
    return img


def button_icon() -> Image.Image:
    shop = Image.open(OUT / "buildings" / "candy_shop.png").convert("RGBA")
    shop.thumbnail((96, 96), Image.LANCZOS)
    icon = Image.new("RGBA", (150, 128), (0, 0, 0, 0))
    icon.paste(shop, (150 - shop.width - 6, (128 - shop.height) // 2), shop)
    return icon


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    pavement().save(OUT / "pavement.png")
    zebra().save(OUT / "zebra.png")
    button_icon().save(ROOT / "art" / "ui" / "town_button.png")
    print("wrote art/town/pavement.png, art/town/zebra.png, art/ui/town_button.png")


if __name__ == "__main__":
    main()

"""Stand-in pictures for Phase 23's new town art (docs/DESIGN.md §23), until Gate B.

The real pictures come from the frozen recipe (tools/comfy/asset_manifest.json: paint_shop,
ice_cream_cone, pizza), four seeds each, one pick. These are flat drawings in the same
size and view, so the game can be built and played before then, and Gate B only has to
replace the files:
  - the paint shop: its block sketch (postprocess.building_sketch), trimmed and fitted to
    its box, exactly what Kontext will be given;
  - an ice cream cone and a pizza: simple shapes, seen from above.

    python tools/layouts/town_placeholders.py
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "comfy"))
import postprocess  # noqa: E402

PAPER = (250, 250, 248)


def manifest_entry(asset_id: str) -> dict:
    manifest = json.loads((ROOT / "tools/comfy/asset_manifest.json").read_text())
    for group in manifest.values():
        if isinstance(group, list):
            for entry in group:
                if isinstance(entry, dict) and entry.get("id") == asset_id:
                    return entry
    raise KeyError(asset_id)


def cut_out(img: Image.Image) -> Image.Image:
    """The drawing without its paper or its grey shadow, trimmed to its edges."""
    rgba = img.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, _ = pixels[x, y]
            if min(r, g, b) >= 215 and max(r, g, b) - min(r, g, b) < 12:
                pixels[x, y] = (0, 0, 0, 0)
    return rgba.crop(rgba.getbbox())


def fit(img: Image.Image, box: tuple[int, int]) -> Image.Image:
    scale = min(box[0] / img.width, box[1] / img.height)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def paint_shop() -> None:
    entry = manifest_entry("paint_shop")
    sketch = cut_out(postprocess.building_sketch(entry["sketch"], 768))
    fit(sketch, tuple(entry["box"])).save(ROOT / entry["out"])


def ice_cream_cone() -> None:
    entry = manifest_entry("ice_cream_cone")
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(70, 110), (186, 110), (128, 248)], fill=(222, 168, 92), outline=(150, 100, 50), width=6)
    for k in range(4):
        d.line([(84 + k * 26, 116), (128 + k * 10, 230)], fill=(176, 120, 60), width=4)
    d.ellipse((58, 58, 152, 140), fill=(255, 182, 206), outline=(200, 110, 140), width=6)
    d.ellipse((104, 50, 198, 132), fill=(255, 244, 214), outline=(200, 170, 120), width=6)
    d.ellipse((92, 8, 170, 82), fill=(140, 90, 60), outline=(90, 55, 35), width=6)
    d.ellipse((122, 4, 148, 30), fill=(230, 40, 60))
    fit(img.crop(img.getbbox()), tuple(entry["box"])).save(ROOT / entry["out"])


def pizza() -> None:
    entry = manifest_entry("pizza")
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((8, 8, 248, 248), fill=(226, 170, 92), outline=(170, 110, 50), width=6)
    d.ellipse((30, 30, 226, 226), fill=(226, 70, 50))
    d.ellipse((40, 40, 216, 216), fill=(252, 214, 110))
    for at in [(80, 80), (160, 76), (120, 128), (72, 160), (170, 160), (124, 190)]:
        d.ellipse((at[0] - 18, at[1] - 18, at[0] + 18, at[1] + 18), fill=(196, 48, 48))
    for k in range(4):
        d.line([(128, 128), (128 + 120 * [1, 0, -1, 0][k], 128 + 120 * [0, 1, 0, -1][k])], fill=(200, 150, 80), width=3)
    fit(img, tuple(entry["box"])).save(ROOT / entry["out"])


if __name__ == "__main__":
    paint_shop()
    ice_cream_cone()
    pizza()
    print("placeholders written")

"""Builds every track theme's textures from tools/layouts/themes.json (docs/DESIGN.md §7.5).

    python tools/layouts/theme_art.py

For each theme: the base and patch ground fills it needs (flat procedural fills, as Phase 2
settled — generated fills cannot tile), its kerb strip, and its ground atlas + TileSet with
every corner combination of base and patch. Plus two theme-free pieces: the boost pad and
the ice that lies on Snowy Peak's road. Meadow's outputs are Track 01's existing files and
come out byte-identical.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools" / "comfy"))
import postprocess as pp  # noqa: E402
import build_tileset as bt  # noqa: E402

THEMES = json.loads((HERE / "themes.json").read_text(encoding="utf-8"))
GROUND = json.loads((ROOT / "tools" / "comfy" / "pipeline.json").read_text(encoding="utf-8"))["ground"]
RIMS = {"sand": (201, 162, 74), "grass": (78, 143, 46), "ice": (127, 191, 216)}


def fill_path(name: str) -> Path:
    return ROOT / "art" / "tiles" / f"{name}.png"


def build_fill(name: str) -> None:
    """A ground fill, made exactly the way generate_assets.py makes the original three."""
    params = {k: v for k, v in GROUND[name].items() if not k.startswith("_")}
    params["base"] = tuple(params["base"])
    pp.flat_fill(GROUND["tile_px"], seed=len(name), **params).save(fill_path(name))


def godot_colour(rgb) -> str:
    r, g, b = (round(c / 255, 2) for c in rgb)
    return f"Color({r:g}, {g:g}, {b:g}, 1)"


def boost_pad(size=(160, 224)) -> Image.Image:
    """A rounded orange pad with three white chevrons pointing +X, the way cars travel."""
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((2, 2, w - 3, h - 3), radius=28, fill=(255, 150, 30, 255), outline=(14, 20, 28, 255), width=5)
    d.rounded_rectangle((14, 14, w - 15, h - 15), radius=20, fill=(255, 196, 40, 255))
    for k in range(3):
        x0 = 22 + k * 40
        pts = [(x0, 40), (x0 + 30, h // 2), (x0, h - 40), (x0 + 16, h - 40), (x0 + 46, h // 2), (x0 + 16, 40)]
        d.polygon(pts, fill=(255, 255, 255, 255), outline=(14, 20, 28, 255))
    return img


def road_ice(size=128) -> Image.Image:
    """Tileable sheet ice for the road: pale blue, a few white streaks, partly see-through
    so the asphalt shows that this is still the road."""
    rng = np.random.default_rng(7)
    img = Image.new("RGBA", (size, size), (196, 232, 246, 215))
    streaks = Image.new("RGBA", (size * 3, size * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(streaks)
    for _ in range(14):
        x, y = rng.integers(0, size, 2) + size
        length = rng.integers(20, 60)
        d.line((x, y, x + length, y - length // 3), fill=(255, 255, 255, 170), width=int(rng.integers(2, 5)))
    streaks = streaks.filter(ImageFilter.GaussianBlur(0.8))
    # Fold the 3x3 sheet onto one tile so streaks crossing an edge wrap round.
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for ox in range(3):
        for oy in range(3):
            tile.alpha_composite(streaks.crop((ox * size, oy * size, (ox + 1) * size, (oy + 1) * size)))
    img.alpha_composite(tile)
    return img


def main() -> None:
    needed = {t[k] for t in THEMES.values() if isinstance(t, dict) for k in ("base", "patch")}
    for name in sorted(needed):
        if not fill_path(name).exists():
            build_fill(name)
            print(f"  fill {name}")
    built = set()
    for theme_id, t in THEMES.items():
        if theme_id.startswith("_"):
            continue
        k = GROUND["kerb"]
        kerb = pp.kerb_strip(4 * k["block"] * 2, k["thickness"], k["block"], tuple(t["kerb"]["red"]), tuple(t["kerb"]["cream"]))
        out = ROOT / t["kerb_out"]
        out.parent.mkdir(parents=True, exist_ok=True)
        kerb.save(out)
        if t["tileset_out"] in built:  # shares another theme's tiles (Toy Town uses the meadow's)
            print(f"  theme {theme_id}: {t['kerb_out']} (tiles shared)")
            continue
        built.add(t["tileset_out"])
        bt.build_atlas(fill_path(t["base"]), fill_path(t["patch"]), ROOT / t["atlas_out"], RIMS.get(t["patch"], bt.RIM))
        tres = bt.tileset_tres(t["atlas_out"], t["base"].capitalize(), t["patch"].capitalize(),
                               godot_colour(GROUND[t["base"]]["base"]), godot_colour(GROUND[t["patch"]]["base"]))
        if theme_id == "meadow":  # Track 01's original names, so its tileset stays byte-identical
            tres = bt.tileset_tres()
        out = ROOT / t["tileset_out"]
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(tres, encoding="utf-8", newline="\n")
        print(f"  theme {theme_id}: {t['atlas_out']}, {t['tileset_out']}, {t['kerb_out']}")
    boost_pad().save(ROOT / "art/tiles/boost_pad.png")
    out = ROOT / "art/tiles/snow/road_ice.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    road_ice().save(out)
    print("  boost_pad.png, snow/road_ice.png")


if __name__ == "__main__":
    main()

"""Phase 3 check: every production asset from art/ in one scene at true game scale.

    python tools/comfy/asset_overview.py

Writes docs/mockups/asset_overview.png: a 12 x 6 tile slice of track with all four cars and
every prop, above the setup cards and the coin. If these do not read as one game, the
recipe or a pick is wrong.
"""
from pathlib import Path

from PIL import Image, ImageDraw

import postprocess as pp

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "art"
TILE = 128


def art(rel: str) -> Image.Image:
    return Image.open(ART / rel).convert("RGBA")


def tiled(fill: Image.Image, size: tuple[int, int]) -> Image.Image:
    out = Image.new("RGB", size)
    for y in range(0, size[1], fill.height):
        for x in range(0, size[0], fill.width):
            out.paste(fill, (x, y))
    return out


def scene() -> Image.Image:
    w, h = 12 * TILE, 6 * TILE
    img = tiled(art("tiles/grass.png").convert("RGB"), (w, h))
    sand = tiled(art("tiles/sand.png").convert("RGB"), (w, h))
    sand_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(sand_mask).ellipse((int(8.6 * TILE), int(4.3 * TILE), int(12.4 * TILE), int(6.6 * TILE)), fill=255)
    img.paste(sand, (0, 0), sand_mask)

    road_top, road_bottom = int(1.2 * TILE), int(4.2 * TILE)
    asphalt = tiled(art("tiles/asphalt.png").convert("RGB"), (w, road_bottom - road_top))
    img.paste(asphalt, (0, road_top))
    kerb = tiled(art("tiles/kerb.png"), (w, 38))
    kerb_rgba = art("tiles/kerb.png")
    for x in range(0, w, kerb_rgba.width):
        img.paste(kerb_rgba, (x, road_top - 4), kerb_rgba)
        flipped = kerb_rgba.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        img.paste(flipped, (x, road_bottom - kerb_rgba.height + 4), flipped)
    draw = ImageDraw.Draw(img)
    mid = (road_top + road_bottom) // 2
    for x in range(60, w, 240):
        draw.rounded_rectangle((x, mid - 6, x + 100, mid + 6), radius=6, fill=(236, 236, 225))
    finish = tiled(art("tiles/finish_line.png").convert("RGB"), (64, road_bottom - road_top))
    img.paste(finish, (int(1.2 * TILE), road_top))
    del kerb

    for name, (x, y) in {"red": (3.0, 1.75), "blue": (4.6, 2.75), "yellow": (6.3, 1.85), "green": (7.9, 2.85)}.items():
        car = art(f"cars/car_{name}.png")
        img.paste(car, (int(x * TILE), int(y * TILE)), car)

    props = [("props/tree.png", (0.2, -0.6)), ("props/tree.png", (9.8, -0.5)), ("props/hay_bale.png", (3.2, 4.45)),
             ("props/hay_bale.png", (4.2, 4.5)), ("props/straw_ring.png", (6.0, 4.6)), ("props/straw_ring.png", (6.85, 4.55))]
    props += [("props/tyre_stack.png", (x, 0.25)) for x in (4.0, 4.7, 5.4, 6.1, 6.8)]
    for rel, (x, y) in props:
        p = art(rel)
        img.paste(p, (int(x * TILE), int(y * TILE)), p)
    return img


def main() -> None:
    world = scene()
    cards = [(art(f"ui/cards/{k}.png"), k) for k in ("starter", "grippy", "slider", "rocket", "kart", "banana")]
    cards.append((art("ui/coin.png"), "coin"))
    card_sheet = pp.contact_sheet(cards, 7, (156, 95), "SETUP CARDS + COIN (50%)", bg=(30, 42, 58))
    top = pp.contact_sheet([(world, "art/ at true game scale, shown at 50%")], 1, (world.width // 2, world.height // 2),
                           "ASSET OVERVIEW")
    sheet = Image.new("RGB", (max(top.width, card_sheet.width), top.height + card_sheet.height), (40, 44, 52))
    sheet.paste(top, (0, 0))
    sheet.paste(card_sheet, (0, top.height))
    sheet.save(ROOT / "docs" / "mockups" / "asset_overview.png")
    world.save(ROOT / "docs" / "mockups" / "asset_overview_fullsize.png")
    print("wrote docs/mockups/asset_overview.png")


if __name__ == "__main__":
    main()

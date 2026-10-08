"""Every vehicle with its driver, drawn the way actors/car/driver_rider.gd draws them, for
tuning the seats in game/configs/driver_seats.gd (docs/DESIGN.md §22) without running the game.

    python tools/layouts/driver_sheet.py   ->  docs/mockups/drivers/driver_sheet.png
"""
import math
import re
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ZOOM = 3
SS = 4  # supersampling for the hole and glass shapes

# Only the vehicles that show a driver (the closed roofs keep theirs hidden).
CARS = ["kart", "bubble", "formula", "soapbox"]
BOATS = ["speedboat", "jetski", "duck", "swan", "tugboat", "pirate", "banana_boat"]
TRAFFIC = {"bus": "bus", "fire_engine": "fire", "garbage_truck": "garbage"}
KIDS = ["vicky", "blue", "yellow", "green", "p2"]


def seats() -> dict:
    """SEATS from driver_seats.gd."""
    src = (ROOT / "game/configs/driver_seats.gd").read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r'"(\w+)": \{"pos": Vector2\(([-\d.]+), ([-\d.]+)\), "mode": (\w+)(.*?)\},?\n', src):
        seat = {"pos": (float(m[2]), float(m[3])), "mode": m[4].lower()}
        rest = m[5]
        if w := re.search(r'"window": Rect2\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)', rest):
            seat["window"] = tuple(float(v) for v in w.groups())
        if s := re.search(r'"scale": ([\d.]+)', rest):
            seat["scale"] = float(s[1])
        out[m[1]] = seat
    return out


def shape_mask(size, draw) -> Image.Image:
    m = Image.new("L", (size[0] * SS, size[1] * SS), 0)
    draw(ImageDraw.Draw(m), SS)
    return m.resize(size, Image.LANCZOS)


def fill(base, mask, rgba):
    layer = Image.new("RGBA", base.size, rgba[:3] + (0,))
    layer.putalpha(mask.point(lambda v: v * rgba[3] // 255))
    base.alpha_composite(layer)


def driver_layer(size, driver, centre, scale):
    d = driver.resize((max(1, round(driver.width * scale)), max(1, round(driver.height * scale))), Image.LANCZOS)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.alpha_composite(d, (round(centre[0] - d.width / 2), round(centre[1] - d.height / 2)))
    return layer


def seat_driver(body: Image.Image, seat: dict, driver: Image.Image) -> Image.Image:
    im = body.copy()
    c = (im.width / 2 + seat["pos"][0], im.height / 2 + seat["pos"][1])
    scale = 0.75 * seat.get("scale", 1.0)
    fig = driver_layer(im.size, driver, c, scale)
    if seat["mode"] == "glass":
        x, y, w, h = seat["window"]
        x += im.width / 2
        y += im.height / 2
        r = min(6.0, min(w, h) / 2)
        win = shape_mask(im.size, lambda d, s: d.rounded_rectangle([x * s, y * s, (x + w) * s, (y + h) * s], r * s, fill=255))
        fill(im, win, (40, 60, 90, 199))
        fig.putalpha(ImageChops.multiply(fig.getchannel("A"), win))
        im.alpha_composite(fig)
        fill(im, win, (40, 60, 90, 69))
        sheen = shape_mask(im.size, lambda d, s: d.polygon([((x + w * .15) * s, (y + h) * s), ((x + w * .55) * s, y * s),
                                                            ((x + w * .75) * s, y * s), ((x + w * .35) * s, (y + h) * s)], fill=255))
        fill(im, ImageChops.multiply(sheen, win), (255, 255, 255, 77))
    else:
        im.alpha_composite(fig)
    return im


def driver_png(folder, who):
    for path in (ROOT / f"art/drivers/{folder}/{who}.png", ROOT / f"art/drivers/car/{who}.png", ROOT / "art/drivers/car/vicky.png"):
        if path.exists():
            return Image.open(path).convert("RGBA")
    raise SystemExit("no driver art built yet")


def main():
    table = seats()
    cells = []
    for i, car in enumerate(CARS):
        cells.append((f"setups/{car}", Image.open(ROOT / f"art/cars/setups/{car}.png").convert("RGBA"), table[car], driver_png("car", KIDS[i % 5])))
    for i, boat in enumerate(BOATS):
        cells.append((boat, Image.open(ROOT / f"art/boats/{boat}.png").convert("RGBA"), table[boat], driver_png("boat", KIDS[i % 5])))
    for name, who in TRAFFIC.items():
        cells.append((name, Image.open(ROOT / f"art/town/vehicles/{name}.png").convert("RGBA"), table[name], driver_png("traffic", who)))
    try:
        font = ImageFont.truetype("arialbd.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    cw, ch, cols = 212 * ZOOM, 84 * ZOOM + 30, 3
    sheet = Image.new("RGBA", (cw * cols, ch * math.ceil(len(cells) / cols)), (126, 186, 96, 255))
    for i, (label, body, seat, driver) in enumerate(cells):
        im = seat_driver(body, seat, driver)
        big = im.resize((im.width * ZOOM, im.height * ZOOM), Image.NEAREST)
        x0, y0 = (i % cols) * cw, (i // cols) * ch
        sheet.alpha_composite(big, (x0 + (cw - big.width) // 2, y0 + 4))
        ImageDraw.Draw(sheet).text((x0 + 8, y0 + 84 * ZOOM + 6), f"{label} ({seat['mode']})", fill=(20, 30, 20), font=font)
    out = ROOT / "docs/mockups/drivers/driver_sheet.png"
    sheet.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()

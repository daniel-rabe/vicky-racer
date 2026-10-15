"""Stand-in pictures for the open world's two new buildings (docs/DESIGN.md §28): the garage and
the trophy house. Drawn flat in the street view (roof above, front wall below), the size of a
shop, so the town places them like the rest. They are placeholders until the Kontext versions
are picked (the frozen recipe, building_sketch + details), as for every other building.

    python tools/layouts/world_buildings.py

Writes art/town/buildings/garage.png and trophy_house.png.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/town/buildings"
SS = 3  # drawn this many times bigger, then shrunk: soft edges


def rounded(draw, box, radius, fill, outline=None, width=0):
    draw.rounded_rectangle([v * SS for v in box], radius * SS, fill=fill, outline=outline, width=width * SS)


def shaded(img, box, radius, colour, shade=0.78):
    """A clay-ish slab: a darker rim under a lighter top."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    dark = tuple(int(c * shade) for c in colour[:3]) + (255,)
    rounded(d, (x0, y0 + 10, x1, y1), radius, dark)
    rounded(d, (x0, y0, x1, y1 - 10), radius, colour)
    light = tuple(min(255, int(c * 1.12)) for c in colour[:3]) + (255,)
    rounded(d, (x0 + 14, y0 + 8, x1 - 14, y0 + 26), 9, light)


def paste(img, path, centre, height, angle=0.0):
    sprite = Image.open(ROOT / path).convert("RGBA")
    if angle:
        sprite = sprite.rotate(angle, expand=True, resample=Image.BICUBIC)
    scale = height * SS / sprite.height
    sprite = sprite.resize((int(sprite.width * scale), int(sprite.height * scale)), Image.LANCZOS)
    img.alpha_composite(sprite, (int(centre[0] * SS - sprite.width / 2), int(centre[1] * SS - sprite.height / 2)))


def shadow(img):
    alpha = img.getchannel("A").filter(ImageFilter.GaussianBlur(6 * SS))
    under = Image.new("RGBA", img.size, (0, 0, 0, 0))
    under.putalpha(alpha.point(lambda a: a * 0.35))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(under, (0, 6 * SS))
    out.alpha_composite(img)
    return out


def finish(img, name):
    img = shadow(img)
    img = img.resize((img.width // SS, img.height // SS), Image.LANCZOS)
    img.save(OUT / name)
    print("wrote", OUT / name)


def garage():
    w, h = 520, 430
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    shaded(img, (8, 380, w - 8, h - 6), 18, (150, 156, 166, 255))  # the forecourt slab
    rounded(d, (30, 190, w - 30, 400), 20, (246, 226, 178, 255))  # the front wall
    # Two roll-up doors, the left one open with the child's red car inside.
    for x0 in (60, 280):
        rounded(d, (x0, 230, x0 + 180, 392), 14, (70, 76, 90, 255))
    for k in range(6):
        y = 236 + k * 13
        rounded(d, (286, y, 434, y + 8), 4, (120, 150, 196, 255))
    for k in range(6, 12):
        y = 236 + k * 13
        rounded(d, (286, y, 434, y + 8), 4, (98, 128, 176, 255))
    paste(img, "art/cars/car_red.png", (150, 320), 150, angle=-90)
    shaded(img, (14, 20, w - 14, 214), 30, (245, 140, 40, 255))  # the roof
    # On the roof: a big tyre and a spanner.
    cx, cy = 150, 112
    d.ellipse([(cx - 62) * SS, (cy - 62) * SS, (cx + 62) * SS, (cy + 62) * SS], fill=(40, 40, 46, 255))
    d.ellipse([(cx - 30) * SS, (cy - 30) * SS, (cx + 30) * SS, (cy + 30) * SS], fill=(196, 200, 210, 255))
    d.ellipse([(cx - 12) * SS, (cy - 12) * SS, (cx + 12) * SS, (cy + 12) * SS], fill=(120, 124, 134, 255))
    spanner = Image.new("RGBA", (200 * SS, 60 * SS), (0, 0, 0, 0))
    s = ImageDraw.Draw(spanner)
    rounded(s, (30, 22, 170, 38), 8, (210, 214, 224, 255))
    s.ellipse([0, 0, 60 * SS, 60 * SS], fill=(210, 214, 224, 255))
    s.ellipse([18 * SS, -8 * SS, 46 * SS, 26 * SS], fill=(0, 0, 0, 0))
    s.ellipse([150 * SS, 6 * SS, 196 * SS, 54 * SS], fill=(210, 214, 224, 255))
    spanner = spanner.rotate(28, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(spanner, (250 * SS, 40 * SS))
    finish(img, "garage.png")


def trophy_house():
    w, h = 480, 430
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    shaded(img, (8, 380, w - 8, h - 6), 18, (240, 196, 70, 255))  # golden steps
    rounded(d, (30, 190, w - 30, 400), 20, (250, 240, 222, 255))
    for x in (60, 130, 320, 390):  # columns
        rounded(d, (x, 214, x + 30, 392), 10, (236, 222, 196, 255))
        rounded(d, (x - 6, 206, x + 36, 222), 6, (220, 200, 170, 255))
    rounded(d, (190, 250, 290, 392), 40, (140, 70, 170, 255))  # the door
    d.ellipse([272 * SS, 316 * SS, 282 * SS, 326 * SS], fill=(255, 214, 63, 255))
    shaded(img, (14, 20, w - 14, 214), 30, (150, 90, 200, 255))  # the roof
    for x, y in ((70, 70), (410, 70), (90, 160), (390, 160)):  # stars
        star = [(x + r * (1 if k % 2 == 0 else 0.45) * cos, y + r * (1 if k % 2 == 0 else 0.45) * sin)
                for k, (cos, sin) in enumerate(_star_points())
                for r in (24,)]
        d.polygon([(px * SS, py * SS) for px, py in star], fill=(255, 214, 63, 255))
    paste(img, "art/ui/cups/trophy_gold.png", (w / 2, 108), 190)
    finish(img, "trophy_house.png")


def _star_points():
    import math
    return [(math.cos(-math.pi / 2 + k * math.pi / 5), math.sin(-math.pi / 2 + k * math.pi / 5)) for k in range(10)]


if __name__ == "__main__":
    garage()
    trophy_house()

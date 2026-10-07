"""Gate A mockup for drivers (docs/DESIGN.md §22): rough placeholder drivers drawn onto the
real vehicle sprites, to settle seat positions and how a closed roof shows its driver.
The heads here are placeholders; Gate B replaces them with generated art.

    python tools/layouts/driver_mockup.py   ->  docs/mockups/drivers/driver_mockup.png
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/mockups/drivers"
SS = 8          # supersampling for the placeholder drawings
ZOOM = 3        # mockup magnification (plus a 1x strip)

COLOURS = {"vicky": (230, 57, 70), "p2": (158, 89, 242), "blue": (58, 134, 255),
           "yellow": (255, 210, 63), "green": (46, 196, 107)}
SKIN = (246, 205, 170)
VEST = (255, 140, 40)


def _shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def driver(kind: str, colour, arms=True) -> Image.Image:
    """A 32x32 top-down head-and-shoulders placeholder facing +X, head at the centre."""
    s = 32 * SS
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = s // 2
    u = SS
    body = VEST if kind == "boat" else _shade(colour, 0.75)
    if kind == "adult":
        body = (90, 110, 160)
    # shoulders: wide across the car, a little behind the head
    d.ellipse([c - 9 * u, c - 11 * u, c + 3 * u, c + 11 * u], fill=body, outline=_shade(body, 0.7), width=u)
    if arms:
        for side in (-1, 1):
            d.line([c - 2 * u, c + side * 8 * u, c + 8 * u, c + side * 5 * u], fill=body, width=4 * u)
            d.ellipse([c + 7 * u, c + side * 5 * u - 2 * u, c + 11 * u, c + side * 5 * u + 2 * u], fill=SKIN)
        if kind != "boat":  # steering wheel
            d.arc([c + 7 * u, c - 7 * u, c + 13 * u, c + 7 * u], -80, 80, fill=(40, 40, 46), width=2 * u)
    if kind == "car":
        d.ellipse([c - 7 * u, c - 7 * u, c + 7 * u, c + 7 * u], fill=colour, outline=_shade(colour, 0.6), width=u)
        d.rectangle([c - 7 * u, c - u, c + 6 * u, c + u], fill=(255, 255, 255))           # stripe
        d.chord([c - 2 * u, c - 6 * u, c + 7 * u, c + 6 * u], -70, 70, fill=(30, 36, 60))  # visor
    else:
        d.ellipse([c - 6 * u, c - 6 * u, c + 6 * u, c + 6 * u], fill=(120, 72, 40))        # hair
        cap = colour if kind == "boat" else (40, 60, 120)
        d.ellipse([c - 6 * u, c - 6 * u, c + 5 * u, c + 6 * u], fill=cap, outline=_shade(cap, 0.6), width=u)
        d.chord([c + 1 * u, c - 6 * u, c + 10 * u, c + 6 * u], -60, 60, fill=_shade(cap, 0.8))  # brim
    return im.resize((32, 32), Image.LANCZOS)


def paste_centred(base, sprite, pos, mask=None):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.alpha_composite(sprite, (int(pos[0] - sprite.width / 2), int(pos[1] - sprite.height / 2)))
    if mask is not None:
        a = ImageChops.multiply(layer.getchannel("A"), mask)
        layer.putalpha(a)
    base.alpha_composite(layer)


def rounded_mask(size, box, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, r, fill=255)
    return m


def glass(base, mask, alpha):
    tint = Image.new("RGBA", base.size, (40, 60, 90, 0))
    tint.putalpha(mask.point(lambda v: v * alpha // 255))
    base.alpha_composite(tint)


def sheen(base, mask):
    w, h = base.size
    s = Image.new("L", base.size, 0)
    ImageDraw.Draw(s).polygon([(0, h), (w * 0.45, 0), (w * 0.55, 0), (w * 0.12, h)], fill=90)
    s = s.filter(ImageFilter.GaussianBlur(1))
    layer = Image.new("RGBA", base.size, (255, 255, 255, 0))
    layer.putalpha(ImageChops.multiply(s, mask))
    base.alpha_composite(layer)


def load(rel):
    return Image.open(ROOT / rel).convert("RGBA")


def open_seat(rel, seat, who="vicky", kind="car", arms=True):
    im = load(rel)
    paste_centred(im, driver(kind, COLOURS[who], arms), seat)
    return im


def sunroof(rel, seat, who="vicky"):
    im = load(rel)
    x, y = seat
    hole = [x - 9, y - 11, x + 8, y + 11]
    d = ImageDraw.Draw(im)
    d.ellipse([hole[0] - 1, hole[1] - 1, hole[2] + 1, hole[3] + 1], fill=(60, 60, 66))
    d.ellipse(hole, fill=(22, 24, 30))
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).ellipse([hole[0], hole[1] - 4, hole[2], hole[3] + 4], fill=255)
    paste_centred(im, driver("car", COLOURS[who], arms=False), seat, m)
    return im


def glass_roof(rel, seat, box, who="vicky"):
    im = load(rel)
    m = rounded_mask(im.size, box, 6)
    glass(im, m, 235)
    paste_centred(im, driver("car", COLOURS[who]), seat, m)
    sheen(im, m)
    return im


def windscreen(rel, seat, box, who="vicky", kind="car"):
    im = load(rel)
    m = rounded_mask(im.size, box, 5)
    glass(im, m, 200)
    paste_centred(im, driver(kind, COLOURS[who] if who in COLOURS else (0, 0, 0)), seat, m)
    glass(im, m, 70)
    sheen(im, m)
    return im


CELLS = [
    ("Speedboat: open seat", lambda: open_seat("art/boats/speedboat.png", (67, 30), "blue", "boat")),
    ("Jet ski: open seat", lambda: open_seat("art/boats/jetski.png", (70, 36), "vicky", "boat")),
    ("Bubble car: under its dome", lambda: windscreen("art/cars/setups/bubble.png", (64, 36), (46, 18, 82, 54), "green")),
    ("Starter A: pop-up sunroof", lambda: sunroof("art/cars/setups/starter.png", (60, 36))),
    ("Starter B: glass roof", lambda: glass_roof("art/cars/setups/starter.png", (62, 36), (44, 21, 76, 51))),
    ("Starter C: through the windscreen", lambda: windscreen("art/cars/setups/starter.png", (70, 36), (72, 19, 88, 53))),
    ("Police A: pop-up sunroof", lambda: sunroof("art/cars/setups/police.png", (66, 36), "yellow")),
    ("Police B: glass roof", lambda: glass_roof("art/cars/setups/police.png", (66, 36), (52, 20, 80, 52), "yellow")),
    ("Police C: through the windscreen", lambda: windscreen("art/cars/setups/police.png", (76, 36), (80, 18, 94, 54), "yellow")),
    ("Tugboat: captain on deck", lambda: open_seat("art/boats/tugboat.png", (49, 36), "green", "boat")),
    ("Swan: on the bench", lambda: open_seat("art/boats/swan.png", (63, 36), "p2", "boat")),
    ("Fire engine: through the windscreen", lambda: windscreen("art/town/vehicles/fire_engine.png", (140, 42), (143, 23, 154, 61), "adult", "adult")),
]


def main():
    from PIL import ImageFont
    try:
        font = ImageFont.truetype("arialbd.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    cw, ch = 210 * ZOOM, 84 * ZOOM + 40
    cols = 3
    rows = (len(CELLS) + cols - 1) // cols
    sheet = Image.new("RGBA", (cw * cols + 20, ch * rows + 20), (126, 186, 96, 255))  # grass
    strip = Image.new("RGBA", (len(CELLS) * 140 + 10, 100), (126, 186, 96, 255))
    for i, (label, make) in enumerate(CELLS):
        im = make()
        big = im.resize((im.width * ZOOM, im.height * ZOOM), Image.NEAREST)
        x0 = 10 + (i % cols) * cw
        y0 = 10 + (i // cols) * ch
        sheet.alpha_composite(big, (x0 + (cw - big.width) // 2, y0))
        ImageDraw.Draw(sheet).text((x0 + 8, y0 + 84 * ZOOM + 6), f"{i + 1}. {label}", fill=(20, 30, 20), font=font)
        strip.alpha_composite(im if im.width <= 136 else im.resize((136, int(im.height * 136 / im.width))), (10 + i * 140, 14))
    sheet.save(OUT / "driver_mockup.png")
    strip.save(OUT / "driver_mockup_1x.png")
    print("wrote", OUT / "driver_mockup.png")


if __name__ == "__main__":
    main()

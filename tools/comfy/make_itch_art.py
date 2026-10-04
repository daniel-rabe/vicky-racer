"""The itch.io page's cover image and header banner, composed from approved game art — nothing new is generated:
ground tiles, car masters, props and the title's font and colours.

    python tools/comfy/make_itch_art.py

Writes docs/itch/cover.png and cover_alt.png (630x500, itch.io's recommended cover size) and
banner.png (960x300, the default page width), each with a _2x twin for high-DPI screens, plus
background.png: a 960 px seamless tile for the page background (set it to repeat).
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

import postprocess as pp

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "itch"
MASTERS = Path(__file__).parent / "masters"
FONT = ROOT / "ui" / "fonts" / "PublicPixel.ttf"
TILES = ROOT / "art" / "tiles"
YELLOW = (255, 210, 63)
RED = (230, 57, 70)
OUTLINE = (14, 20, 28)
ASPHALT = (92, 98, 112)
KERB_RED = (214, 50, 56)
KERB_WHITE = (240, 236, 220)
LINE = (238, 236, 226)

SS = 4             # everything is drawn at 4x the final size, then downscaled
KERB = 46


def bezier(p, t):
    u = 1 - t
    return (u ** 3 * p[0][0] + 3 * u * u * t * p[1][0] + 3 * u * t * t * p[2][0] + t ** 3 * p[3][0],
            u ** 3 * p[0][1] + 3 * u * u * t * p[1][1] + 3 * u * t * t * p[2][1] + t ** 3 * p[3][1])


def samples(curve, n=1200):
    pts = [bezier(curve, i / n) for i in range(n + 1)]
    out = []
    for i, (x, y) in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        out.append((x, y, dx / length, dy / length))
    return out


def offset(pts, d):
    return [(x - ty * d, y + tx * d, tx, ty) for x, y, tx, ty in pts]


def band(draw, pts, inner, outer, fill):
    """Fill the strip between lateral offsets `inner` and `outer` along `pts`."""
    a, b = offset(pts, inner), offset(pts, outer)
    draw.polygon([(x, y) for x, y, *_ in a] + [(x, y) for x, y, *_ in reversed(b)], fill=fill)


def runs(pts, on_len, off_len=None):
    """Split `pts` by arc length into alternating runs; yields (index, run)."""
    off_len = on_len if off_len is None else off_len
    travelled, i, run = 0.0, 0, [pts[0]]
    for a, b in zip(pts, pts[1:]):
        travelled += math.hypot(b[0] - a[0], b[1] - a[1])
        run.append(b)
        if travelled >= (on_len if i % 2 == 0 else off_len):
            yield i, run
            travelled, i, run = 0.0, i + 1, [b]
    yield i, run


def ground(w: int, h: int, tile_name: str) -> Image.Image:
    tile = Image.open(TILES / f"{tile_name}.png").convert("RGBA").resize((320, 320), Image.LANCZOS)
    img = Image.new("RGBA", (w, h))
    for y in range(0, h, tile.height):
        for x in range(0, w, tile.width):
            img.paste(tile, (x, y))
    return img


def road(img: Image.Image, pts, width: int) -> None:
    draw = ImageDraw.Draw(img)
    edge = width / 2 + KERB
    band(draw, pts, -edge - 8, edge + 8, OUTLINE)
    for i, run in runs(pts, 80):
        for side in (-1, 1):
            band(draw, run, side * (width / 2), side * edge, KERB_WHITE if i % 2 == 0 else KERB_RED)
    band(draw, pts, -width / 2 - 6, width / 2 + 6, OUTLINE)
    band(draw, pts, -width / 2, width / 2, ASPHALT)
    for i, run in runs(pts, 110, 90):
        if i % 2 == 0:
            band(draw, run, -10, 10, LINE)


def shadowed(sprite: Image.Image, offset_xy=(18, 24), blur=14, alpha=110) -> tuple[Image.Image, int]:
    pad = blur * 3 + max(map(abs, offset_xy))
    out = Image.new("RGBA", (sprite.width + 2 * pad, sprite.height + 2 * pad))
    shade = Image.new("RGBA", sprite.size, (0, 0, 0, 255))
    shade.putalpha(sprite.getchannel("A").point(lambda v: v * alpha // 255))
    out.alpha_composite(shade, (pad + offset_xy[0], pad + offset_xy[1]))
    out = out.filter(ImageFilter.GaussianBlur(blur))
    out.alpha_composite(sprite, (pad, pad))
    return out, pad


def place(img, sprite, centre):
    s, _ = shadowed(sprite)
    img.alpha_composite(s, (int(centre[0] - s.width / 2), int(centre[1] - s.height / 2)))


def car(name: str, pts, t: float, lateral: float, length: int, wiggle=0.0):
    """A car master (nose down in the file) sat on the curve at `t`, nose along the road.
    `wiggle` turns it off the road's line, e.g. into a drift."""
    x, y, tx, ty = pts[int(t * (len(pts) - 1))]
    heading = math.degrees(math.atan2(-ty, tx)) + wiggle
    sprite = Image.open(MASTERS / f"{name}.png").convert("RGBA")
    sprite = sprite.resize((round(sprite.width * length / sprite.height), length), Image.LANCZOS)
    sprite = sprite.rotate(heading + 90, expand=True, resample=Image.BICUBIC)
    return sprite, (x - ty * lateral, y + tx * lateral)


def title(img: Image.Image, size: int, lines) -> None:
    """`lines` is [(top, [(text, colour), ...]), ...]; each line is centred horizontally."""
    layer = Image.new("RGBA", img.size)
    draw = ImageDraw.Draw(layer)
    font = ImageFont.truetype(str(FONT), size)
    for top, parts in lines:
        x = (img.width - draw.textlength("".join(t for t, _ in parts), font=font)) / 2
        for text, colour in parts:
            draw.text((x, top), text, font=font, fill=colour, stroke_width=size // 6, stroke_fill=OUTLINE)
            x += draw.textlength(text, font=font)
    s, pad = shadowed(layer, (0, size // 9), 18, 120)
    img.alpha_composite(s.crop((pad, pad, pad + img.width, pad + img.height)))


def scene(size, tile, curve, road_width, props, cars, car_length) -> Image.Image:
    """`props` is [(master, centre, box side)], `cars` is [(master, t, lateral, wiggle)]."""
    img = ground(*size, tile)
    pts = samples(curve)
    road(img, pts, road_width)
    for name, centre, side in props:
        place(img, pp.fit_sprite(Image.open(MASTERS / f"{name}.png"), (side, side)), centre)
    for name, t, lateral, wiggle in cars:
        sprite, centre = car(name, pts, t, lateral, car_length, wiggle)
        place(img, sprite, centre)
    return img


def cover() -> Image.Image:
    """One S-bend in from the bottom left and out past the right edge, the pack chasing up it."""
    img = scene((630 * SS, 500 * SS), "grass", [(-300, 2500), (1700, 2100), (500, 1050), (3000, 820)], 560,
                [("tree", (260, 1260), 420), ("tree", (2330, 1620), 520), ("tree", (1950, 1980), 300)],
                [("car_green", 0.40, -110, 6), ("car_blue", 0.50, 120, -4),
                 ("car_yellow", 0.61, -100, 8), ("car_red", 0.76, 60, -8)], 340)
    title(img, 300, [(150, [("VICKY", YELLOW)]), (520, [("RACER", RED)])])
    return img


def cover_alt() -> Image.Image:
    """The beach track: a hairpin dropping in from the top left, turning at the bottom and climbing
    out to the top right, with roster cars from the paint shop drifting round the turn."""
    img = scene((630 * SS, 500 * SS), "beach", [(380, -300), (300, 2330), (2220, 2330), (2140, -300)], 500,
                [("palm_tree", (2380, 1500), 560), ("parasol", (1260, 1000), 400),
                 ("beach_ball", (1010, 1270), 150), ("palm_tree", (120, 1800), 480)],
                [("paint_rocket_purple", 0.30, 90, 4), ("paint_icecream_pink", 0.44, -110, 24),
                 ("paint_monster_green", 0.55, 100, 28), ("paint_banana_yellow", 0.70, -60, 14)], 330)
    title(img, 300, [(110, [("VICKY", YELLOW)]), (480, [("RACER", RED)])])
    return img


def banner() -> Image.Image:
    """The title on one line over a long sweeping straight, the pack racing left to right."""
    img = scene((960 * SS, 300 * SS), "grass", [(-300, 1150), (1300, 600), (2500, 1250), (4150, 700)], 400,
                [("tree", (200, 330), 360), ("tree", (3640, 300), 340)],
                [("car_green", 0.22, 90, 8), ("car_blue", 0.37, -95, -6),
                 ("car_yellow", 0.53, 95, 6), ("car_red", 0.71, -60, -8)], 260)
    title(img, 260, [(110, [("VICKY ", YELLOW), ("RACER", RED)])])
    return img


def background() -> Image.Image:
    """Grass with trackside props scattered over it at seeded-random spots and angles, spaced with
    wrap-around distances and drawn wrapped across the edges, so the tile repeats seamlessly.
    Darkened a touch to sit behind the page's content column."""
    side = 960 * 2  # drawn at 2x: the grass tile is 320 px here, so six tiles fit exactly
    img = ground(side, side, "grass")
    rng = random.Random(7)
    # (master, box range, how many) — the big ones go down first so they always find room
    kinds = [("tree", 260, 320, 4), ("pine_tree", 240, 290, 3), ("toy_house", 210, 240, 1),
             ("tree", 190, 230, 3), ("hay_bale", 140, 160, 3), ("tyre_stack", 120, 140, 3),
             ("traffic_cone", 90, 100, 3)]
    placed = []
    for name, lo, hi, count in kinds:
        for _ in range(count):
            for _attempt in range(2000):
                box, x, y = rng.randint(lo, hi), rng.randrange(side), rng.randrange(side)
                def gap(o):
                    dx = min(abs(x - o[1]), side - abs(x - o[1]))
                    dy = min(abs(y - o[2]), side - abs(y - o[2]))
                    return math.hypot(dx, dy) - (box + o[3]) / 2
                if all(gap(o) > 170 for o in placed):
                    placed.append((name, x, y, box))
                    break
    for name, x, y, box in placed:
        sprite = pp.fit_sprite(Image.open(MASTERS / f"{name}.png"), (box, box))
        sprite, _ = shadowed(sprite.rotate(rng.uniform(-25, 25), expand=True, resample=Image.BICUBIC))
        for dx in (-side, 0, side):
            for dy in (-side, 0, side):
                img.alpha_composite(sprite, (x + dx - sprite.width // 2, y + dy - sprite.height // 2))                     if -sprite.width < x + dx < side + sprite.width and -sprite.height < y + dy < side + sprite.height                     else None
    img = Image.blend(img, Image.new("RGBA", img.size, (20, 32, 46, 255)), 0.18)
    return img.convert("RGB").resize((960, 960), Image.LANCZOS)


def save(img: Image.Image, name: str, size: tuple[int, int]) -> None:
    img = img.convert("RGB")
    img.resize((size[0] * 2, size[1] * 2), Image.LANCZOS).save(OUT / f"{name}_2x.png")
    img.resize(size, Image.LANCZOS).save(OUT / f"{name}.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    save(cover(), "cover", (630, 500))
    save(cover_alt(), "cover_alt", (630, 500))
    save(banner(), "banner", (960, 300))
    background().save(OUT / "background.png")
    print("wrote docs/itch/cover.png, cover_alt.png, banner.png (each with a _2x twin), background.png")


if __name__ == "__main__":
    main()

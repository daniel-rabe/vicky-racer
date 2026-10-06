"""Look probe for the boat courses (docs/DESIGN.md §20), drawn before any game code exists.

    python tools/layouts/water_probe.py

Writes docs/mockups/boat/01_water_look.png: one 1920x1080 view of Duck Pond at race scale
(camera zoom 1.0, a 4.5-tile channel), and 02_water_themes.png: the four water themes side
by side. Grounds are the real flat fills from tools/comfy/pipeline.json; boats are plain
placeholder hulls until their sprites are generated (Gate B).
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools" / "comfy"))
import postprocess as pp  # noqa: E402

GROUND = json.loads((ROOT / "tools" / "comfy" / "pipeline.json").read_text(encoding="utf-8"))["ground"]
THEMES = json.loads((HERE / "themes.json").read_text(encoding="utf-8"))
OUT = ROOT / "docs" / "mockups" / "boat"
FONT = Path("G:/Godot/external_assets/fonts/Public_Pixel_Font_1_24/PublicPixel.ttf")
SS = 2  # supersampling for smooth edges
TILE = 128
FOAM = (255, 255, 255)


def fill(name: str) -> Image.Image:
    params = {k: v for k, v in GROUND[name].items() if not k.startswith("_")}
    params["base"] = tuple(params["base"])
    return pp.flat_fill(GROUND["tile_px"], seed=len(name), **params).convert("RGBA")


def tiled(name: str, size) -> Image.Image:
    t = fill(name).resize((TILE * SS, TILE * SS), Image.NEAREST)
    img = Image.new("RGBA", size)
    for x in range(0, size[0], t.width):
        for y in range(0, size[1], t.height):
            img.paste(t, (x, y))
    return img


def bezier(points, n=200):
    """A Catmull-Rom curve through `points` (open)."""
    out = []
    pts = [points[0]] + points + [points[-1]]
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for s in range(n):
            t = s / n
            out.append(tuple(0.5 * (2 * p1[a] + (-p0[a] + p2[a]) * t + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * t * t
                                    + (-p0[a] + 3 * p1[a] - 3 * p2[a] + p3[a]) * t ** 3) for a in range(2)))
    out.append(points[-1])
    return out


def stroke(draw, line, width, colour):
    """A wide stroke as overlapping discs: PIL's wide lines leave seams between segments."""
    r = width / 2
    for x, y in line[::2]:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=colour)


def mask_of(size, line, width):
    m = Image.new("L", size, 0)
    stroke(ImageDraw.Draw(m), line, width, 255)
    return m


def tangent_at(line, i):
    a, b = line[max(i - 2, 0)], line[min(i + 2, len(line) - 1)]
    d = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
    return (b[0] - a[0]) / d, (b[1] - a[1]) / d


def channel(img, theme, line, width):
    """Shallows everywhere, then the deep channel with a soft pale lip and wavelets."""
    size = img.size
    t = THEMES[theme]
    lip = mask_of(size, line, width + 34 * SS).filter(ImageFilter.GaussianBlur(10 * SS))
    img.alpha_composite(Image.new("RGBA", size, (255, 255, 255, 0)))
    pale = Image.new("RGBA", size, FOAM + (0,))
    pale.putalpha(lip.point(lambda v: int(v * 0.35)))
    img.alpha_composite(pale)
    deep = tiled(t["road"], size)
    deep.putalpha(mask_of(size, line, width).filter(ImageFilter.GaussianBlur(3 * SS)))
    img.alpha_composite(deep)
    d = ImageDraw.Draw(img)
    # Wavelets: short pale arcs scattered on the deep water.
    for k in range(18, len(line) - 18, 37):
        tx, ty = tangent_at(line, k)
        for off in (-0.3, 0.05, 0.32):
            x, y = line[k][0] - ty * off * width, line[k][1] + tx * off * width
            x += ((k * 37) % 23 - 11) * SS
            d.arc((x - 16 * SS, y - 6 * SS, x + 16 * SS, y + 6 * SS), 200, 340, fill=(255, 255, 255, 90), width=3 * SS)


def sandbank(img, box, theme):
    t = THEMES[theme]
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    m = m.filter(ImageFilter.GaussianBlur(2 * SS))
    rim = Image.new("L", img.size, 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(rim).ellipse((x0 - 14 * SS, y0 - 14 * SS, x1 + 14 * SS, y1 + 14 * SS), fill=255)
    rim = rim.filter(ImageFilter.GaussianBlur(8 * SS))
    foam = Image.new("RGBA", img.size, FOAM + (0,))
    foam.putalpha(rim.point(lambda v: int(v * 0.5)))
    img.alpha_composite(foam)
    bank = tiled(t["patch"], img.size)
    bank.putalpha(m)
    img.alpha_composite(bank)


def buoys(img, line, width, idx, colours):
    d = ImageDraw.Draw(img)
    for j, i in enumerate(idx):
        tx, ty = tangent_at(line, i)
        for side in (1, -1):
            x, y = line[i][0] - ty * side * (width / 2 + 10 * SS), line[i][1] + tx * side * (width / 2 + 10 * SS)
            r = 15 * SS
            d.ellipse((x - r + 4 * SS, y - r + 6 * SS, x + r + 4 * SS, y + r + 6 * SS), fill=(0, 0, 0, 50))
            d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(colours[j % 2]) + (255,), outline=(30, 34, 40, 255), width=3 * SS)
            d.ellipse((x - r * 0.45, y - r * 0.6, x - r * 0.05, y - r * 0.2), fill=(255, 255, 255, 170))


def currents(img, line, width, a, b):
    d = ImageDraw.Draw(img)
    for i in range(a, b, 22):
        tx, ty = tangent_at(line, i)
        for off in (-0.25, 0.0, 0.25):
            x, y = line[i][0] - ty * off * width, line[i][1] + tx * off * width
            nx, ny = -ty, tx
            p = [(x - tx * 14 * SS + nx * 16 * SS, y - ty * 14 * SS + ny * 16 * SS), (x + tx * 10 * SS, y + ty * 10 * SS),
                 (x - tx * 14 * SS - nx * 16 * SS, y - ty * 14 * SS - ny * 16 * SS)]
            d.line(p, fill=(255, 255, 255, 150), width=6 * SS, joint="curve")


def ramp(img, at, heading):
    w, h = 150 * SS, 190 * SS
    r = Image.new("RGBA", (w + 40 * SS, h + 40 * SS))
    d = ImageDraw.Draw(r)
    ox, oy = 20 * SS, 20 * SS
    d.polygon([(ox + 6 * SS, oy + 24 * SS), (ox + w, oy), (ox + w, oy + h), (ox + 6 * SS, oy + h - 24 * SS)], fill=(0, 0, 0, 60))
    d.polygon([(ox, oy + 20 * SS), (ox + w - 8 * SS, oy), (ox + w - 8 * SS, oy + h), (ox, oy + h - 20 * SS)],
              fill=(201, 138, 74, 255), outline=(74, 46, 20, 255))
    for k in range(1, 6):
        x = ox + k * (w - 8 * SS) / 6
        d.line([(x, oy + 20 * SS * (1 - k / 6)), (x, oy + h - 20 * SS * (1 - k / 6))], fill=(120, 76, 36, 255), width=3 * SS)
    d.rectangle((ox + w - 18 * SS, oy, ox + w - 8 * SS, oy + h), fill=(255, 210, 63, 255))
    for k in (0, 1):
        cx = ox + 45 * SS + k * 40 * SS
        d.line([(cx, oy + 60 * SS), (cx + 26 * SS, oy + h / 2), (cx, oy + h - 60 * SS)], fill=(255, 210, 63, 255), width=9 * SS)
    r = r.rotate(-math.degrees(heading), expand=True, resample=Image.BICUBIC)
    img.alpha_composite(r, (int(at[0] - r.width / 2), int(at[1] - r.height / 2)))


def wake(img, path, width=60):
    """A V of foam spreading behind a boat, plus a churned strip right behind it."""
    layer = Image.new("RGBA", img.size)
    d = ImageDraw.Draw(layer)
    n = len(path)
    for side in (1, -1):
        pts = []
        for k, (x, y) in enumerate(path):
            tx, ty = tangent_at(path, k)
            spread = (n - k) / n * width * SS + 14 * SS
            pts.append((x - ty * side * spread, y + tx * side * spread))
        d.line(pts, fill=(255, 255, 255, 170), width=7 * SS, joint="curve")
    d.line(path, fill=(255, 255, 255, 120), width=22 * SS, joint="curve")
    layer = layer.filter(ImageFilter.GaussianBlur(2.5 * SS))
    img.alpha_composite(layer)


def hull(img, at, heading, colour, kind="speedboat"):
    """Placeholder top-down hull, 128x72-ish like a car sprite, pointing +X before rotation."""
    w, h = (128, 60) if kind == "speedboat" else (96, 44)
    b = Image.new("RGBA", ((w + 30) * SS, (h + 30) * SS))
    d = ImageDraw.Draw(b)
    o = 15 * SS
    W, H = w * SS, h * SS
    shape = [(o, o + H * 0.15), (o + W * 0.62, o), (o + W, o + H / 2), (o + W * 0.62, o + H), (o, o + H * 0.85)]
    d.polygon([(x + 5 * SS, y + 7 * SS) for x, y in shape], fill=(0, 0, 0, 60))
    d.polygon(shape, fill=(250, 250, 245, 255), outline=(30, 34, 40, 255), width=3 * SS)
    inner = [(o + 8 * SS, o + H * 0.25), (o + W * 0.55, o + H * 0.12), (o + W * 0.86, o + H / 2),
             (o + W * 0.55, o + H * 0.88), (o + 8 * SS, o + H * 0.75)]
    d.polygon(inner, fill=tuple(colour) + (255,))
    d.rounded_rectangle((o + W * 0.3, o + H * 0.3, o + W * 0.5, o + H * 0.7), radius=6 * SS, fill=(150, 210, 240, 255),
                        outline=(30, 34, 40, 255), width=2 * SS)
    d.rectangle((o - 8 * SS, o + H * 0.38, o + 4 * SS, o + H * 0.62), fill=(50, 54, 60, 255))
    b = b.rotate(-math.degrees(heading), expand=True, resample=Image.BICUBIC)
    img.alpha_composite(b, (int(at[0] - b.width / 2), int(at[1] - b.height / 2)))


def prop_circle(img, at, r, fill_c, edge):
    d = ImageDraw.Draw(img)
    x, y = at
    d.ellipse((x - r + 6 * SS, y - r + 8 * SS, x + r + 6 * SS, y + r + 8 * SS), fill=(0, 0, 0, 55))
    d.ellipse((x - r, y - r, x + r, y + r), fill=fill_c, outline=edge, width=4 * SS)


def label(img, text, at, size=18):
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(str(FONT), size * SS)
    x, y = at
    bb = d.textbbox((x, y), text, font=f)
    d.rounded_rectangle((bb[0] - 10 * SS, bb[1] - 8 * SS, bb[2] + 10 * SS, bb[3] + 8 * SS), radius=8 * SS, fill=(20, 32, 46, 210))
    d.text((x, y), text, font=f, fill=(240, 244, 248, 255))


def look_probe():
    W, H = 1920 * SS, 1080 * SS
    img = tiled("pond_water", (W, H))
    width = 4.5 * TILE * SS
    ctrl = [(-200, 980), (400, 900), (900, 760), (1300, 520), (1560, 260), (1800, -120)]
    line = bezier([(x * SS, y * SS) for x, y in ctrl])
    sandbank(img, (1350 * SS, 700 * SS, 1880 * SS, 1000 * SS), "pond")
    sandbank(img, (40 * SS, 60 * SS, 520 * SS, 330 * SS), "pond")
    channel(img, "pond", line, width)
    currents(img, line, width, 120, 330)
    buoys(img, line, width, range(620, 1000, 55), [THEMES["pond"]["kerb"]["red"], THEMES["pond"]["kerb"]["cream"]])
    i = 470
    tx, ty = tangent_at(line, i)
    ramp(img, line[i], math.atan2(ty, tx))
    # Boats: the player's speedboat with a long wake, one rival in the shallows, a jet ski.
    for k, colour, off, kind in ((380, (230, 57, 70), -0.12, "speedboat"), (250, (58, 134, 255), 0.22, "speedboat"),
                                 (150, (255, 210, 63), -0.2, "jetski")):
        tx, ty = tangent_at(line, k)
        path = [(line[j][0] - ty * off * width, line[j][1] + tx * off * width) for j in range(k - 140, k - 10)]
        wake(img, path, 70 if kind == "speedboat" else 45)
        p = (line[k][0] - ty * off * width, line[k][1] + tx * off * width)
        hull(img, p, math.atan2(ty, tx), colour, kind)
    # Shore props at the far side, lily pads and reeds in the shallows.
    for at in ((300, 240), (190, 150)):
        prop_circle(img, (at[0] * SS, at[1] * SS), 50 * SS, (46, 139, 58, 255), (28, 90, 36, 255))
    for at in ((700, 260), (760, 330), (1080, 1000), (130, 760)):
        prop_circle(img, (at[0] * SS, at[1] * SS), 26 * SS, (88, 168, 72, 255), (47, 110, 42, 255))
    for at in ((1640, 820), (1720, 870)):
        prop_circle(img, (at[0] * SS, at[1] * SS), 34 * SS, (110, 158, 58, 255), (63, 100, 32, 255))
    label(img, "SHALLOWS  x0.6", (560 * SS, 120 * SS))
    label(img, "DEEP CHANNEL  full speed", (330 * SS, 640 * SS))
    label(img, "SANDBANK  x0.35 (hovercraft skim it)", (1060 * SS, 1030 * SS), 14)
    label(img, "CURRENT  pushes along", (40 * SS, 1000 * SS), 14)
    label(img, "RAMP  jump!", (1150 * SS, 330 * SS), 14)
    label(img, "BUOYS  bouncy edge on tight bends", (1240 * SS, 40 * SS), 14)
    label(img, "Boats are placeholder hulls - sprites come in Gate B", (40 * SS, 30 * SS), 12)
    OUT.mkdir(parents=True, exist_ok=True)
    img.resize((1920, 1080), Image.LANCZOS).convert("RGB").save(OUT / "01_water_look.png")


def theme_sheet():
    """Each theme drawn at full race scale, then shrunk into a quarter of the sheet."""
    W, H = 1920 * SS, 1080 * SS
    sheet = Image.new("RGB", (1920, 1080))
    for n, theme in enumerate(("pond", "river", "lagoon", "lemonade")):
        t = THEMES[theme]
        img = tiled(t["base"], (W, H))
        sandbank(img, (1150 * SS, 720 * SS, 1820 * SS, 1000 * SS), theme)
        line = bezier([(-200 * SS, 820 * SS), (600 * SS, 700 * SS), (1300 * SS, 420 * SS), (2100 * SS, 260 * SS)])
        width = 4.5 * TILE * SS
        channel(img, theme, line, width)
        buoys(img, line, width, range(230, 400, 40), [t["kerb"]["red"], t["kerb"]["cream"]])
        k = 190
        tx, ty = tangent_at(line, k)
        wake(img, line[k - 140:k - 10], 70)
        hull(img, line[k], math.atan2(ty, tx), (230, 57, 70))
        label(img, t["name"].upper(), (40 * SS, 40 * SS), 36)
        sheet.paste(img.resize((960, 540), Image.LANCZOS).convert("RGB"), ((n % 2) * 960, (n // 2) * 540))
    d = ImageDraw.Draw(sheet)
    d.line((960, 0, 960, 1080), fill=(20, 32, 46), width=6)
    d.line((0, 540, 1920, 540), fill=(20, 32, 46), width=6)
    sheet.save(OUT / "02_water_themes.png")


if __name__ == "__main__":
    look_probe()
    theme_sheet()
    print(OUT / "01_water_look.png", OUT / "02_water_themes.png")

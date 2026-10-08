"""Look probe for the space courses (docs/DESIGN.md §23), drawn before any game code exists.

    python tools/layouts/space_probe.py

Writes docs/mockups/space/01_space_look.png: one 1920x1080 view of Asteroid Alley at race
scale (camera zoom 1.0, a 5.5-tile star lane), and 02_space_themes.png: the four space themes
side by side. Grounds are the real flat fills from tools/comfy/pipeline.json (the stars are
their speckles); ships are plain placeholder shapes until their sprites are generated (Gate B).
"""
import math
import random

from PIL import Image, ImageDraw, ImageFilter

from water_probe import ROOT, SS, THEMES, TILE, bezier, label, mask_of, prop_circle, tangent_at, tiled

OUT = ROOT / "docs" / "mockups" / "space"


def hex_rgb(h: str):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def far_stars(img, seed, count=70):
    """The parallax layer: bigger twinkling stars that drift slower than the ground."""
    rng = random.Random(seed)
    layer = Image.new("RGBA", img.size)
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        x, y = rng.uniform(0, img.width), rng.uniform(0, img.height)
        r = rng.choice((2, 3, 3, 4)) * SS
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 240, 230))
        if r >= 3 * SS:
            for dx, dy in ((1, 0), (0, 1)):
                d.line((x - dx * r * 3, y - dy * r * 3, x + dx * r * 3, y + dy * r * 3), fill=(255, 255, 240, 140), width=SS)
    glow = layer.filter(ImageFilter.GaussianBlur(3 * SS))
    img.alpha_composite(glow)
    img.alpha_composite(layer)


def cloud(img, box, theme, craters=False):
    """A slow patch: moon dust with craters, ring dust, a nebula cloud or cotton candy."""
    t = THEMES[theme]
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    soft = 10 if theme in ("nebula", "candy_galaxy") else 2
    m = m.filter(ImageFilter.GaussianBlur(soft * SS))
    patch = tiled(t["patch"], img.size)
    patch.putalpha(m)
    img.alpha_composite(patch)
    if craters:
        d = ImageDraw.Draw(img)
        rng = random.Random(7)
        x0, y0, x1, y1 = box
        for _ in range(7):
            cx, cy = rng.uniform(x0 + 120 * SS, x1 - 120 * SS), rng.uniform(y0 + 80 * SS, y1 - 80 * SS)
            r = rng.uniform(26, 60) * SS
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(170, 162, 196, 255), outline=(131, 122, 162, 255), width=4 * SS)
            d.ellipse((cx - r * 0.7, cy - r * 0.55, cx + r * 0.75, cy + r * 0.8), fill=(150, 142, 178, 255))


def lane(img, theme, line, width):
    """The star lane: a soft glow on the dust, the lane fill, and a pale sheen down its middle."""
    size = img.size
    t = THEMES[theme]
    glow_c = hex_rgb(t["svg"]["glow"])
    halo = mask_of(size, line, width + 60 * SS).filter(ImageFilter.GaussianBlur(18 * SS))
    g = Image.new("RGBA", size, glow_c + (0,))
    g.putalpha(halo.point(lambda v: int(v * 0.45)))
    img.alpha_composite(g)
    fill = tiled(t["road"], size)
    fill.putalpha(mask_of(size, line, width).filter(ImageFilter.GaussianBlur(2 * SS)))
    img.alpha_composite(fill)
    sheen = Image.new("RGBA", size, glow_c + (0,))
    sheen.putalpha(mask_of(size, line, width * 0.45).filter(ImageFilter.GaussianBlur(26 * SS)).point(lambda v: int(v * 0.35)))
    img.alpha_composite(sheen)
    edge = ImageDraw.Draw(img)
    for side in (1, -1):  # a thin bright rim so the lane's edge reads at speed
        pts = []
        for k in range(0, len(line), 3):
            tx, ty = tangent_at(line, k)
            pts.append((line[k][0] - ty * side * width / 2, line[k][1] + tx * side * width / 2))
        edge.line(pts, fill=glow_c + (200,), width=4 * SS, joint="curve")


def beacons(img, line, width, idx, colours):
    """Beacon lights on the tight bends, where cars have kerbs and boats have buoys."""
    layer = Image.new("RGBA", img.size)
    d = ImageDraw.Draw(layer)
    for j, i in enumerate(idx):
        tx, ty = tangent_at(line, i)
        for side in (1, -1):
            x, y = line[i][0] - ty * side * (width / 2 + 16 * SS), line[i][1] + tx * side * (width / 2 + 16 * SS)
            c = tuple(colours[j % 2])
            d.ellipse((x - 26 * SS, y - 26 * SS, x + 26 * SS, y + 26 * SS), fill=c + (90,))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(8 * SS)))
    d = ImageDraw.Draw(img)
    for j, i in enumerate(idx):
        tx, ty = tangent_at(line, i)
        for side in (1, -1):
            x, y = line[i][0] - ty * side * (width / 2 + 16 * SS), line[i][1] + tx * side * (width / 2 + 16 * SS)
            r = 11 * SS
            d.ellipse((x - r - 4 * SS, y - r - 4 * SS, x + r + 4 * SS, y + r + 4 * SS), fill=(60, 64, 76, 255), outline=(20, 24, 30, 255), width=2 * SS)
            d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(colours[j % 2]) + (255,))
            d.ellipse((x - r * 0.5, y - r * 0.6, x - r * 0.05, y - r * 0.15), fill=(255, 255, 255, 200))


def asteroid(img, at, r, seed, path=None):
    """A lumpy grey rock with a shadow; with `path`, the dashed line it drifts to and fro on."""
    d = ImageDraw.Draw(img)
    if path:
        (ax, ay), (bx, by) = path
        n = int(math.dist(path[0], path[1]) / (18 * SS))
        for k in range(0, n, 2):
            d.line((ax + (bx - ax) * k / n, ay + (by - ay) * k / n, ax + (bx - ax) * (k + 1) / n, ay + (by - ay) * (k + 1) / n),
                   fill=(220, 214, 236, 150), width=3 * SS)
    rng = random.Random(seed)
    x, y = at
    pts = [(x + math.cos(a) * r * rng.uniform(0.8, 1.05), y + math.sin(a) * r * rng.uniform(0.8, 1.05))
           for a in [k * math.tau / 9 for k in range(9)]]
    d.polygon([(px + 8 * SS, py + 12 * SS) for px, py in pts], fill=(0, 0, 0, 70))
    d.polygon(pts, fill=(140, 132, 148, 255), outline=(62, 56, 72, 255), width=4 * SS)
    for _ in range(3):
        cx, cy, cr = x + rng.uniform(-0.45, 0.45) * r, y + rng.uniform(-0.45, 0.45) * r, rng.uniform(0.12, 0.22) * r
        d.ellipse((cx - cr, cy - cr, cx + cr, cy + cr), fill=(106, 98, 116, 255))
    d.arc((x - r * 0.8, y - r * 0.8, x + r * 0.5, y + r * 0.5), 200, 280, fill=(190, 184, 200, 255), width=4 * SS)


def comet(img, a, b, head_at=0.3, warning=True):
    """A comet crossing the course. The dashed streak glows on the lane 1.5 s before it comes."""
    d = ImageDraw.Draw(img)
    (ax, ay), (bx, by) = a, b
    if warning:
        layer = Image.new("RGBA", img.size)
        ImageDraw.Draw(layer).line((ax, ay, bx, by), fill=(255, 228, 92, 120), width=46 * SS)
        img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(10 * SS)))
        n = int(math.dist(a, b) / (30 * SS))
        for k in range(0, n, 2):
            d.line((ax + (bx - ax) * k / n, ay + (by - ay) * k / n, ax + (bx - ax) * (k + 1) / n, ay + (by - ay) * (k + 1) / n),
                   fill=(255, 228, 92, 230), width=6 * SS)
    hx, hy = ax + (bx - ax) * head_at, ay + (by - ay) * head_at
    ux, uy = (bx - ax) / math.dist(a, b), (by - ay) / math.dist(a, b)
    tail = Image.new("RGBA", img.size)
    td = ImageDraw.Draw(tail)
    for k in range(40):
        f = k / 40
        r = (34 - 26 * f) * SS
        cx, cy = hx - ux * f * 420 * SS, hy - uy * f * 420 * SS
        td.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 236 - int(60 * f), 150, int(200 * (1 - f))))
    img.alpha_composite(tail.filter(ImageFilter.GaussianBlur(6 * SS)))
    rng = random.Random(3)
    for _ in range(14):  # sparkles shed by the tail
        f = rng.uniform(0.1, 1.0)
        sx, sy = hx - ux * f * 460 * SS + rng.uniform(-30, 30) * SS, hy - uy * f * 460 * SS + rng.uniform(-30, 30) * SS
        s = rng.uniform(3, 7) * SS
        d.line((sx - s, sy, sx + s, sy), fill=(255, 255, 255, 220), width=2 * SS)
        d.line((sx, sy - s, sx, sy + s), fill=(255, 255, 255, 220), width=2 * SS)
    r = 30 * SS
    d.ellipse((hx - r, hy - r, hx + r, hy + r), fill=(255, 250, 230, 255), outline=(255, 176, 32, 255), width=6 * SS)


def boost_pad(img, at, heading):
    w, h = 110 * SS, 150 * SS
    p = Image.new("RGBA", (w + 20 * SS, h + 20 * SS))
    d = ImageDraw.Draw(p)
    o = 10 * SS
    d.rounded_rectangle((o, o, o + w, o + h), radius=20 * SS, fill=(255, 196, 40, 255), outline=(14, 20, 28, 255), width=4 * SS)
    for k in (0, 1):
        cx = o + 30 * SS + k * 34 * SS
        d.line([(cx, o + 40 * SS), (cx + 26 * SS, o + h / 2), (cx, o + h - 40 * SS)], fill=(255, 255, 255, 255), width=9 * SS)
    p = p.rotate(-math.degrees(heading), expand=True, resample=Image.BICUBIC)
    img.alpha_composite(p, (int(at[0] - p.width / 2), int(at[1] - p.height / 2)))


def thruster_trail(img, path, colour):
    """Behind every ship: a fading glow ribbon from the engine, and stardust puffs."""
    layer = Image.new("RGBA", img.size)
    d = ImageDraw.Draw(layer)
    n = len(path)
    for k, (x, y) in enumerate(path):
        f = k / n
        r = (4 + 9 * f) * SS
        d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(colour) + (int(40 + 150 * f),))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(5 * SS)))


def ship(img, at, heading, colour, kind="fighter"):
    """Placeholder top-down ship, pointing +X before rotation (128x72-ish like a car sprite)."""
    b = Image.new("RGBA", (190 * SS, 140 * SS))
    d = ImageDraw.Draw(b)
    cx, cy = 95 * SS, 70 * SS
    c = tuple(colour) + (255,)
    ink = (30, 34, 40, 255)

    def P(pts):
        return [(cx + x * SS, cy + y * SS) for x, y in pts]

    if kind == "fighter":
        d.polygon(P([(-46, -40), (6, -12), (-46, 40), (-36, 0)]), fill=(240, 242, 246, 255), outline=ink, width=3 * SS)
        d.polygon(P([(-58, -14), (40, -12), (66, 0), (40, 12), (-58, 14)]), fill=c, outline=ink, width=3 * SS)
        d.ellipse((cx + 4 * SS, cy - 9 * SS, cx + 34 * SS, cy + 9 * SS), fill=(150, 210, 240, 255), outline=ink, width=2 * SS)
        d.rectangle((cx - 66 * SS, cy - 8 * SS, cx - 56 * SS, cy + 8 * SS), fill=(255, 176, 32, 255))
    elif kind == "saucer":
        d.ellipse((cx - 56 * SS, cy - 56 * SS, cx + 56 * SS, cy + 56 * SS), fill=(214, 218, 228, 255), outline=ink, width=3 * SS)
        d.ellipse((cx - 40 * SS, cy - 40 * SS, cx + 40 * SS, cy + 40 * SS), fill=c)
        for k in range(8):
            a = k * math.tau / 8
            x, y = cx + math.cos(a) * 48 * SS, cy + math.sin(a) * 48 * SS
            d.ellipse((x - 5 * SS, y - 5 * SS, x + 5 * SS, y + 5 * SS), fill=(255, 228, 92, 255))
        d.ellipse((cx - 22 * SS, cy - 22 * SS, cx + 22 * SS, cy + 22 * SS), fill=(170, 222, 245, 230), outline=ink, width=2 * SS)
    else:  # a cardboard box rocket
        d.rectangle((cx - 50 * SS, cy - 28 * SS, cx + 34 * SS, cy + 28 * SS), fill=(214, 168, 108, 255), outline=ink, width=3 * SS)
        d.polygon(P([(34, -28), (64, 0), (34, 28)]), fill=c, outline=ink, width=3 * SS)
        d.line((cx - 50 * SS, cy, cx + 34 * SS, cy), fill=(150, 110, 60, 255), width=3 * SS)
        d.ellipse((cx - 70 * SS, cy - 14 * SS, cx - 46 * SS, cy + 14 * SS), fill=(120, 120, 128, 255), outline=ink, width=2 * SS)
    shadow = Image.new("RGBA", b.size)
    shadow.putalpha(b.getchannel("A").point(lambda v: int(v * 0.3)))
    b = Image.alpha_composite(Image.new("RGBA", b.size), b)
    s = shadow.rotate(-math.degrees(heading), expand=True, resample=Image.BICUBIC)
    b = b.rotate(-math.degrees(heading), expand=True, resample=Image.BICUBIC)
    img.alpha_composite(s, (int(at[0] - s.width / 2 + 10 * SS), int(at[1] - s.height / 2 + 26 * SS)))  # ships float higher
    img.alpha_composite(b, (int(at[0] - b.width / 2), int(at[1] - b.height / 2)))


def on_line(line, width, k, off):
    tx, ty = tangent_at(line, k)
    return (line[k][0] - ty * off * width, line[k][1] + tx * off * width), math.atan2(ty, tx)


def look_probe():
    W, H = 1920 * SS, 1080 * SS
    theme = "moonbelt"
    img = tiled(THEMES[theme]["base"], (W, H))
    far_stars(img, 4)
    width = 5.5 * TILE * SS
    ctrl = [(-200, 960), (380, 900), (900, 780), (1320, 540), (1580, 260), (1820, -140)]
    line = bezier([(x * SS, y * SS) for x, y in ctrl])
    cloud(img, (1300 * SS, 690 * SS, 2200 * SS, 1240 * SS), theme, craters=True)
    lane(img, theme, line, width)
    beacons(img, line, width, range(620, 1000, 60), [THEMES[theme]["kerb"]["red"], THEMES[theme]["kerb"]["cream"]])
    at, h = on_line(line, width, 520, 0.0)
    boost_pad(img, at, h)
    for k, (pos, r, seed) in enumerate((((120, 140), 46, 1), ((420, 330), 34, 2), ((1760, 520), 40, 3), ((760, 180), 28, 4))):
        asteroid(img, (pos[0] * SS, pos[1] * SS), r * SS, seed)
    asteroid(img, (980 * SS, 330 * SS), 52 * SS, 9, path=((1040 * SS, 110 * SS), (900 * SS, 560 * SS)))
    comet(img, (1900 * SS, 980 * SS), (700 * SS, 280 * SS), head_at=0.42)
    for k, colour, off, kind in ((400, (230, 57, 70), -0.1, "fighter"), (300, (58, 134, 255), -0.3, "saucer"),
                                 (170, (255, 210, 63), -0.18, "box")):
        trail = [on_line(line, width, j, off)[0] for j in range(k - 150, k - 28)]
        thruster_trail(img, trail, (255, 196, 90) if kind != "saucer" else (140, 220, 255))
        p, h = on_line(line, width, k, off)
        ship(img, p, h, colour, kind)
    label(img, "SPACE DUST  x0.6", (520 * SS, 60 * SS))
    label(img, "STAR LANE  full speed", (420 * SS, 900 * SS))
    label(img, "MOON  x0.35", (1560 * SS, 1010 * SS), 14)
    label(img, "BOOST", (1030 * SS, 470 * SS), 14)
    label(img, "DRIFTING ASTEROID  soft bump", (1020 * SS, 140 * SS), 14)
    label(img, "COMET  the streak glows first, then it whooshes by", (900 * SS, 860 * SS), 14)
    label(img, "BEACONS  light the tight bends", (1400 * SS, 40 * SS), 14)
    label(img, "Ships are placeholder shapes - sprites come in Gate B", (40 * SS, 1030 * SS), 12)
    OUT.mkdir(parents=True, exist_ok=True)
    img.resize((1920, 1080), Image.LANCZOS).convert("RGB").save(OUT / "01_space_look.png")


def theme_sheet():
    """Each theme drawn at full race scale, then shrunk into a quarter of the sheet."""
    W, H = 1920 * SS, 1080 * SS
    sheet = Image.new("RGB", (1920, 1080))
    extras = {"moonbelt": "moon", "rings": "ring dust", "nebula": "nebula cloud", "candy_galaxy": "cotton candy"}
    for n, theme in enumerate(("moonbelt", "rings", "nebula", "candy_galaxy")):
        t = THEMES[theme]
        img = tiled(t["base"], (W, H))
        far_stars(img, n + 10)
        cloud(img, (1150 * SS, 700 * SS, 1880 * SS, 1020 * SS), theme, craters=theme == "moonbelt")
        line = bezier([(-200 * SS, 820 * SS), (600 * SS, 700 * SS), (1300 * SS, 420 * SS), (2100 * SS, 260 * SS)])
        width = 5.5 * TILE * SS
        lane(img, theme, line, width)
        beacons(img, line, width, range(230, 400, 45), [t["kerb"]["red"], t["kerb"]["cream"]])
        asteroid(img, (300 * SS, 300 * SS), 44 * SS, n)
        k = 190
        trail = [on_line(line, width, j, 0)[0] for j in range(k - 140, k - 25)]
        thruster_trail(img, trail, (255, 196, 90))
        p, h = on_line(line, width, k, 0)
        ship(img, p, h, (230, 57, 70))
        label(img, t["name"].upper(), (40 * SS, 40 * SS), 36)
        label(img, extras[theme], (1250 * SS, 960 * SS), 20)
        sheet.paste(img.resize((960, 540), Image.LANCZOS).convert("RGB"), ((n % 2) * 960, (n // 2) * 540))
    d = ImageDraw.Draw(sheet)
    d.line((960, 0, 960, 1080), fill=(20, 32, 46), width=6)
    d.line((0, 540, 1920, 540), fill=(20, 32, 46), width=6)
    sheet.save(OUT / "02_space_themes.png")


if __name__ == "__main__":
    look_probe()
    theme_sheet()
    print(OUT / "01_space_look.png", OUT / "02_space_themes.png")

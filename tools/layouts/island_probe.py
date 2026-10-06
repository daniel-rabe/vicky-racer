"""Look probe for Phase 21, the town as an island (docs/DESIGN.md §21), drawn before any game
code exists.

    python tools/layouts/island_probe.py

Runs the game twice to photograph the real town (the whole of it with --overview, and the
south ring road where the harbour road will leave it), then paints round those photographs
what Phase 21 adds: the beach, the shoreline, the ocean out to its outer limit, the harbour
with its quay, pier and two swap pads, and the things to do at sea. Everything is placed in
world pixels, so the positions here are the ones the code will use.

Writes, in docs/mockups/island/:
  01_island_overview.png  the whole island from far out
  02_harbour_closeup.png  the harbour at game scale, from the ring road to the mooring
  03_swap_views.png       what the player sees: the car on the land pad, the boat at the mooring

Everything is the game's art (Gate B, art/town/island/ and the harbour building). Until a
piece is built, a drawn placeholder stands in for it; the harbour's block sketch, the picture
Kontext is given (§19.2), is saved beside the mockups.
"""
import json
import math
import random
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools" / "comfy"))
import postprocess as pp  # noqa: E402

GODOT = "G:/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"
GROUND = json.loads((ROOT / "tools" / "comfy" / "pipeline.json").read_text(encoding="utf-8"))["ground"]
OUT = ROOT / "docs" / "mockups" / "island"
FONT = Path("G:/Godot/external_assets/fonts/Public_Pixel_Font_1_24/PublicPixel.ttf")
ART = ROOT / "art"

# --- the town as it is (TownLayout) ------------------------------------------------------
MARGIN, PITCH, COLS, ROWS = 960.0, 1600.0, 5, 4
ROAD_HALF, SIDEWALK = 160.0, 72.0
WORLD_W, WORLD_H = 2 * MARGIN + COLS * PITCH, 2 * MARGIN + ROWS * PITCH  # 9920 x 8320
STREETS = (MARGIN - ROAD_HALF - SIDEWALK, MARGIN - ROAD_HALF - SIDEWALK,
           MARGIN + COLS * PITCH + ROAD_HALF + SIDEWALK, MARGIN + ROWS * PITCH + ROAD_HALF + SIDEWALK)

# --- Phase 21 ----------------------------------------------------------------------------
CORNER = 1300.0     # the island's rounded corners
COAST = 250.0       # waterline: this far out from today's world edge, give or take the wobble
WOBBLE = 150.0
BEACH = 320.0       # sand from the grass to the waterline
WET = 70.0          # darker wet sand at the water's edge
SHALLOWS = 420.0    # pale water out from the waterline
LIMIT = 2750.0      # the outer limit of buoys and rocks, from today's world edge
# The harbour, on the south coast between the third and fourth avenues.
HARBOUR_X = (4250.0, 5750.0)
QUAY = (4250.0, 8150.0, 5750.0, 8650.0)
DRIVE_X, DRIVE_HALF = 5380.0, 130.0                   # the harbour road down from the ring road
BUILDING = (4380.0, 7700.0, 4940.0, 8140.0)           # front faces down onto the quay
LAND_PAD = (4470.0, 8165.0, 4850.0, 8460.0)
PIER = (4560.0, 8650.0, 4760.0, 9100.0)
MOORING = (4500.0, 9100.0, 4820.0, 9380.0)
SLIPWAY = (5480.0, 8650.0, 5680.0, 8930.0)

# The close-up's world rect: what the south photo shows (1920 px across at zoom 1.0).
CLOSEUP = (4000.0, 7170.0, 5920.0, 9700.0)

SEA_DEEP = (28, 132, 196)
OPEN_SEA = (22, 98, 160)
FOAM = (255, 255, 255)


# --- drawing in world pixels -------------------------------------------------------------

class View:
    """A canvas showing the world rect (x0, y0, x1, y1) at k canvas px per world px."""

    def __init__(self, rect, k):
        self.x0, self.y0, x1, y1 = rect
        self.k = k
        self.img = Image.new("RGBA", (round((x1 - self.x0) * k), round((y1 - self.y0) * k)), OPEN_SEA + (255,))
        self._tiles = {}

    def p(self, x, y):
        return ((x - self.x0) * self.k, (y - self.y0) * self.k)

    def pts(self, points):
        return [self.p(x, y) for x, y in points]

    def box(self, r):
        a, b = self.p(r[0], r[1]), self.p(r[2], r[3])
        return (a[0], a[1], b[0], b[1])

    def s(self, v):
        return v * self.k

    def tiled(self, key, tile: Image.Image):
        """The whole canvas covered in `tile` (128 world px), aligned to the world's origin
        as Godot's texture repeat is."""
        if key not in self._tiles:
            size = max(4, round(128 * self.k))
            t = tile.convert("RGBA").resize((size, size), Image.LANCZOS)
            img = Image.new("RGBA", self.img.size)
            ox = -round((self.x0 * self.k) % size)
            oy = -round((self.y0 * self.k) % size)
            for x in range(ox, img.width, size):
                for y in range(oy, img.height, size):
                    img.paste(t, (x, y))
            self._tiles[key] = img
        return self._tiles[key]

    def fill_poly(self, points, fill, soft=0.6):
        mask = Image.new("L", self.img.size, 0)
        ImageDraw.Draw(mask).polygon(self.pts(points), fill=255)
        if soft:
            mask = mask.filter(ImageFilter.GaussianBlur(soft))
        self.fill_mask(mask, fill)

    def fill_mask(self, mask, fill):
        if isinstance(fill, tuple):
            layer = Image.new("RGBA", self.img.size, fill if len(fill) == 4 else fill + (255,))
        else:
            layer = fill
        self.img.paste(layer, (0, 0), mask)

    def sprite(self, path_or_img, at, size=None, angle=0.0, alpha=1.0):
        """A sprite centred on `at`, `size` world px across its longer side (default: its own
        size at scale 1), turned `angle` radians (sprites point +x)."""
        im = Image.open(path_or_img).convert("RGBA") if not isinstance(path_or_img, Image.Image) else path_or_img
        scale = (size / max(im.size) if size else 1.0) * self.k
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
        if angle:
            im = im.rotate(-math.degrees(angle), expand=True, resample=Image.BICUBIC)
        if alpha < 1.0:
            im.putalpha(im.getchannel("A").point(lambda a: int(a * alpha)))
        x, y = self.p(*at)
        self.img.alpha_composite(im, (int(x - im.width / 2), int(y - im.height / 2)))

    def shadow(self, at, rx, ry, alpha=60):
        layer = Image.new("RGBA", self.img.size)
        x, y = self.p(*at)
        ImageDraw.Draw(layer).ellipse((x - self.s(rx), y - self.s(ry), x + self.s(rx), y + self.s(ry)), fill=(0, 0, 0, alpha))
        self.img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(max(1, self.s(10)))))


def fill_tile(name: str) -> Image.Image:
    params = {k: v for k, v in GROUND[name].items() if not k.startswith("_")}
    params["base"] = tuple(params["base"])
    return pp.flat_fill(GROUND["tile_px"], seed=len(name), **params)


def sea_tile(base) -> Image.Image:
    return pp.flat_fill(128, tuple(base), variation=0.035, waves=5, speckle_density=0.0, speckle_shift=10, seed=31)


# --- the island's outline ----------------------------------------------------------------

def _rounded_rect_path(rect, radius, step=40.0):
    """Points round a rounded rectangle, clockwise from the top-left corner's end, each with
    its outward normal and its distance along the perimeter."""
    x0, y0, x1, y1 = rect
    out = []
    s = 0.0
    corners = [((x1 - radius, y0 + radius), -math.pi / 2), ((x1 - radius, y1 - radius), 0.0),
               ((x0 + radius, y1 - radius), math.pi / 2), ((x0 + radius, y0 + radius), math.pi)]
    starts = [(x0 + radius, y0), (x1, y0 + radius), (x1 - radius, y1), (x0, y1 - radius)]
    for i, ((cx, cy), a0) in enumerate(corners):
        sx, sy = starts[i]
        ex, ey = cx + radius * math.cos(a0), cy + radius * math.sin(a0)
        n = (math.cos(a0), math.sin(a0))
        length = math.hypot(ex - sx, ey - sy)
        for k in range(int(length / step)):
            t = k * step / length
            out.append((sx + (ex - sx) * t, sy + (ey - sy) * t, n[0], n[1], s + k * step))
        s += length
        arc = radius * math.pi / 2
        for k in range(int(arc / step)):
            a = a0 + (math.pi / 2) * k * step / arc
            out.append((cx + radius * math.cos(a), cy + radius * math.sin(a), math.cos(a), math.sin(a), s + k * step))
        s += arc
    return out, s


_PATH, _PERIM = _rounded_rect_path((0, 0, WORLD_W, WORLD_H), CORNER)


def _wobble(x, y, s):
    """How far the waterline wanders from COAST here: gentle bays and points, none at the
    harbour, whose quay wall is straight."""
    w = (math.sin(s / _PERIM * math.tau * 7 + 0.6) * 0.55 + math.sin(s / _PERIM * math.tau * 13 + 2.1) * 0.3
         + math.sin(s / _PERIM * math.tau * 23 + 4.0) * 0.15) * WOBBLE
    if y > WORLD_H - 10:
        d = max(HARBOUR_X[0] - 500 - x, x - HARBOUR_X[1] - 500, 0.0)
        w *= min(1.0, d / 900.0)
    return w


def outline(offset, wobble=1.0):
    """The island's outline `offset` px out from the waterline (negative: inland)."""
    return [(x + nx * (COAST + offset + wobble * _wobble(x, y, s)), y + ny * (COAST + offset + wobble * _wobble(x, y, s)))
            for x, y, nx, ny, s in _PATH]


def limit_outline():
    path, _ = _rounded_rect_path((0, 0, WORLD_W, WORLD_H), CORNER)
    return [(x + nx * LIMIT, y + ny * LIMIT) for x, y, nx, ny, _s in path]


# --- placeholders (Gate B makes the real art) --------------------------------------------

def art_or(path, placeholder):
    """The built art at `path` (under art/), or the drawn placeholder while there is none."""
    full = ART / path
    return Image.open(full).convert("RGBA") if full.exists() else placeholder()


def lighthouse_img(size=360):
    im = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(im)
    c = size / 2
    for r, col in ((0.46, (110, 104, 98)), (0.30, (245, 245, 240)), (0.24, (214, 52, 52)), (0.17, (245, 245, 240)),
                   (0.11, (60, 64, 72)), (0.08, (255, 222, 90))):
        d.ellipse((c - r * size, c - r * size, c + r * size, c + r * size), fill=col + (255,))
    return im


def sailboat_img(colour=(214, 60, 60)):
    """Seen from above: a white hull, the boom out to one side, a sail bellied along it."""
    im = Image.new("RGBA", (200, 140))
    d = ImageDraw.Draw(im)
    d.ellipse((20, 44, 190, 96), fill=(250, 248, 240, 255), outline=(60, 50, 40, 255), width=4)
    d.ellipse((40, 54, 170, 86), fill=(196, 150, 100, 255))
    d.polygon([(118, 70), (40, 18), (64, 70)], fill=(255, 255, 255, 255), outline=(80, 80, 90, 255))
    d.polygon([(118, 70), (40, 18), (78, 30)], fill=colour + (255,))
    d.line([(118, 70), (40, 18)], fill=(90, 60, 30, 255), width=5)
    d.ellipse((110, 62, 126, 78), fill=(90, 60, 30, 255))
    return im


def dolphin_img():
    im = Image.new("RGBA", (180, 80))
    d = ImageDraw.Draw(im)
    d.ellipse((10, 22, 160, 58), fill=(120, 140, 160, 255))
    d.ellipse((140, 33, 176, 47), fill=(120, 140, 160, 255))
    d.polygon([(70, 24), (100, 4), (96, 26)], fill=(96, 114, 134, 255))
    d.polygon([(14, 40), (0, 20), (2, 60)], fill=(96, 114, 134, 255))
    d.ellipse((30, 34, 140, 52), fill=(200, 212, 222, 255))
    d.ellipse((150, 34, 156, 40), fill=(20, 20, 30, 255))
    return im


def gull_img():
    im = Image.new("RGBA", (120, 70))
    d = ImageDraw.Draw(im)
    d.polygon([(60, 34), (8, 10), (0, 18), (50, 42)], fill=(250, 250, 250, 255), outline=(120, 120, 130, 255))
    d.polygon([(60, 34), (112, 10), (120, 18), (70, 42)], fill=(250, 250, 250, 255), outline=(120, 120, 130, 255))
    d.ellipse((48, 26, 72, 52), fill=(255, 255, 255, 255), outline=(120, 120, 130, 255))
    d.polygon([(56, 50), (64, 50), (60, 62)], fill=(250, 180, 40, 255))
    d.polygon([(0, 18), (8, 10), (14, 16)], fill=(60, 60, 70, 255))
    d.polygon([(120, 18), (112, 10), (106, 16)], fill=(60, 60, 70, 255))
    return im


def buoy_img(colour):
    im = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(im)
    d.ellipse((4, 8, 60, 64), fill=(0, 0, 0, 60))
    d.ellipse((2, 2, 58, 58), fill=colour + (255,), outline=(40, 40, 50, 255), width=3)
    d.rectangle((2, 24, 58, 36), fill=(255, 255, 255, 255))
    d.ellipse((22, 22, 38, 38), fill=(250, 220, 80, 255), outline=(40, 40, 50, 255), width=2)
    return im


def harbour_sketch():
    """The harbour master's boathouse as the §19.2 block sketch Kontext will be given: a
    navy roof with a lookout, white weatherboard, a big boathouse door beside the office door."""
    img = pp.building_sketch({"width": 0.8, "roof": 0.3, "wall": 0.26, "roof_colour": [40, 80, 150],
                              "wall_colour": [236, 222, 190], "front": "garages", "count": 2,
                              "door_colour": [70, 130, 190]}, size=768).convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, _a = px[x, y]
            if r > 222 and g > 222 and b > 220:
                px[x, y] = (r, g, b, 0)
    img = img.crop(img.getbbox())
    d = ImageDraw.Draw(img)
    w = img.width
    # A round lookout with a flag on the roof, and a lifebuoy on the wall: details the
    # Kontext prompt will ask for.
    d.ellipse((w * 0.42, 20, w * 0.58, 20 + w * 0.16), fill=(250, 250, 250, 255), outline=(40, 50, 70, 255), width=4)
    d.line([(w * 0.5, 30), (w * 0.5, -10 + 30)], fill=(60, 60, 60, 255), width=4)
    d.ellipse((w * 0.08, img.height * 0.62, w * 0.16, img.height * 0.62 + w * 0.08), outline=(230, 60, 50, 255), width=10)
    return img


# --- the pieces --------------------------------------------------------------------------

def paint_ground(v: View, town_photo=None, photo_rect=None, photo_k=None, photo_origin=None, photo_crop=None):
    v.img.paste(v.tiled("open", Image.open(ART / "town" / "island" / "open_sea.png")), (0, 0))
    v.fill_poly(limit_outline(), v.tiled("deep", Image.open(ART / "town" / "island" / "sea.png")))
    v.fill_poly(outline(SHALLOWS), v.tiled("shallows", fill_tile("lagoon_water")), soft=v.s(120))
    v.fill_poly(outline(SHALLOWS * 0.45), v.tiled("shallows", None), soft=v.s(60))
    # Foam where the waves meet the sand.
    foam = Image.new("L", v.img.size, 0)
    ImageDraw.Draw(foam).line(v.pts(outline(18) + outline(18)[:1]), fill=230, width=max(2, round(v.s(26))))
    v.fill_mask(foam.filter(ImageFilter.GaussianBlur(max(1, v.s(6)))), FOAM)
    v.fill_poly(outline(0), v.tiled("wet", Image.open(ART / "town" / "island" / "wet_sand.png")))
    v.fill_poly(outline(-WET), v.tiled("beach", fill_tile("beach")), soft=v.s(30))
    v.fill_poly(outline(-BEACH), v.tiled("grass", Image.open(ART / "tiles" / "grass.png")), soft=v.s(40))


def paste_town(v: View, photo: Image.Image, world_rect, photo_world_to_px, feather):
    """The game's own picture of the town, over the world rect it shows."""
    x0, y0, x1, y1 = world_rect
    a, b = photo_world_to_px(x0, y0), photo_world_to_px(x1, y1)
    crop = photo.crop((round(a[0]), round(a[1]), round(b[0]), round(b[1]))).convert("RGBA")
    pa, pb = v.p(x0, y0), v.p(x1, y1)
    crop = crop.resize((round(pb[0] - pa[0]), round(pb[1] - pa[1])), Image.LANCZOS)
    mask = Image.new("L", crop.size, 0)
    f = round(v.s(feather))
    ImageDraw.Draw(mask).rectangle((f, f, crop.width - f, crop.height - f), fill=255)
    if f:
        mask = mask.filter(ImageFilter.GaussianBlur(f / 2))
    v.img.paste(crop, (round(pa[0]), round(pa[1])), mask)


def paint_beach_life(v: View, rng: random.Random):
    """Palms where the grass meets the sand, parasols and beach balls on the beach."""
    inner = outline(-BEACH - 60)
    beach = outline(-BEACH * 0.45)
    for i in range(0, len(inner), 9):
        x, y = inner[i]
        if HARBOUR_X[0] - 300 < x < HARBOUR_X[1] + 300 and y > WORLD_H - 200:
            continue
        v.sprite(ART / "props" / "beach" / "palm_tree.png", (x, y), 220 * rng.uniform(0.85, 1.1), rng.uniform(0, math.tau))
    for i in range(5, len(beach), 37):
        x, y = beach[i]
        if HARBOUR_X[0] - 500 < x < HARBOUR_X[1] + 500 and y > WORLD_H - 200:
            continue
        v.sprite(ART / "props" / "beach" / "parasol.png", (x, y), 190)
        v.sprite(ART / "props" / "beach" / "beach_ball.png", (x + 150, y + 60), 70)


def paint_harbour(v: View, sketch: Image.Image):
    stone = v.tiled("pavement", Image.open(ART / "town" / "pavement.png"))
    asphalt = v.tiled("asphalt", Image.open(ART / "tiles" / "asphalt.png"))
    d = ImageDraw.Draw(v.img)
    # The harbour road: from the ring road down to the quay, a lane each way.
    drive = (DRIVE_X - DRIVE_HALF, STREETS[3] - SIDEWALK - 10, DRIVE_X + DRIVE_HALF, QUAY[1] + 40)
    d.rectangle(v.box((drive[0] - 7, drive[1] + 20, drive[2] + 7, drive[3])), fill=(237, 235, 224))
    v.fill_poly([(drive[0], drive[1]), (drive[2], drive[1]), (drive[2], drive[3]), (drive[0], drive[3])], asphalt, soft=0)
    y = drive[1] + 160
    while y < drive[3] - 80:
        d.rectangle(v.box((DRIVE_X - 5, y, DRIVE_X + 5, y + 80)), fill=(242, 242, 230))
        y += 160
    # The quay: stone paving with a dark edge and bollards along the water.
    q = QUAY
    v.fill_poly([(q[0], q[1]), (q[2], q[1]), (q[2], q[3]), (q[0], q[3])], stone, soft=0)
    d.rectangle(v.box((q[0], q[3] - 30, q[2], q[3])), fill=(150, 140, 126))
    d.rectangle(v.box((q[0], q[1], q[0] + 24, q[3])), fill=(150, 140, 126))
    d.rectangle(v.box((q[2] - 24, q[1], q[2], q[3])), fill=(150, 140, 126))
    x = q[0] + 120
    while x < q[2] - 60:
        if not (PIER[0] - 40 < x < PIER[2] + 40 or SLIPWAY[0] - 40 < x < SLIPWAY[2] + 40):
            d.ellipse(v.box((x - 22, q[3] - 50, x + 22, q[3] - 6)), fill=(60, 60, 66))
        x += 220
    # Stacked crates, a coil of rope and a little crane: life on the quay.
    for cx, cy, col in ((5060, 8300, (196, 120, 60)), (5130, 8300, (70, 140, 200)), (5095, 8240, (220, 180, 60))):
        d.rectangle(v.box((cx - 34, cy - 34, cx + 34, cy + 34)), fill=col, outline=(60, 40, 20), width=max(1, round(v.s(4))))
    d.ellipse(v.box((5180, 8470, 5260, 8550)), outline=(190, 160, 110), width=max(1, round(v.s(14))))
    # Slipway: concrete running down into the water.
    s = SLIPWAY
    grad = Image.new("RGBA", (max(1, round(v.s(s[2] - s[0]))), max(1, round(v.s(s[3] - s[1])))))
    gd = ImageDraw.Draw(grad)
    for row in range(grad.height):
        gd.line([(0, row), (grad.width, row)], fill=(196, 192, 182, int(255 * (1 - row / grad.height) ** 0.7)))
    v.img.alpha_composite(grad, tuple(round(c) for c in v.p(s[0], s[1])))
    # The pier: planks across, posts down either side.
    p = PIER
    v.shadow(((p[0] + p[2]) / 2 + 14, (p[1] + p[3]) / 2 + 14), (p[2] - p[0]) / 2, (p[3] - p[1]) / 2, 50)
    planks = ART / "town" / "island" / "planks.png"
    if planks.exists():
        v.fill_poly([(p[0], p[1]), (p[2], p[1]), (p[2], p[3]), (p[0], p[3])], v.tiled("planks", Image.open(planks)), soft=0)
    else:
        d.rectangle(v.box(p), fill=(186, 130, 78), outline=(110, 70, 36), width=max(1, round(v.s(5))))
    y = p[1] + 60
    while y < p[3] + 40:
        for x in (p[0] - 6, p[2] + 6):
            post = ART / "town" / "island" / "mooring_post.png"
            if post.exists():
                v.sprite(post, (x, y), 56)
            else:
                d.ellipse(v.box((x - 20, y - 20, x + 20, y + 20)), fill=(116, 76, 40), outline=(70, 44, 20))
        y += 150
    # The harbour building, front down onto the quay.
    b = BUILDING
    v.sprite(art_or("town/buildings/harbour.png", lambda: sketch), ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2), max(b[2] - b[0], b[3] - b[1]))
    # The land pad: driving the car on swaps it for the boat.
    pad(v, LAND_PAD, (60, 150, 220), "boat")
    # The mooring: sailing the boat in swaps it back for the car.
    m = MOORING
    ring = Image.new("RGBA", v.img.size)
    rd = ImageDraw.Draw(ring)
    rd.rounded_rectangle(v.box(m), radius=v.s(60), fill=(255, 255, 255, 70))
    v.img.alpha_composite(ring)
    for k in range(14):
        t = k / 14
        per = 2 * ((m[2] - m[0]) + (m[3] - m[1]))
        dist = t * per
        w, h = m[2] - m[0], m[3] - m[1]
        if dist < w:
            at = (m[0] + dist, m[1])
        elif dist < w + h:
            at = (m[2], m[1] + dist - w)
        elif dist < 2 * w + h:
            at = (m[2] - (dist - w - h), m[3])
        else:
            at = (m[0], m[3] - (dist - 2 * w - h))
        if at[1] <= m[1] + 1 and m[0] + 60 < at[0] < m[2] - 60:
            continue  # the pier side stays open
        v.sprite(buoy_img((250, 200, 40) if k % 2 else (255, 255, 255)), at, 34)
    icon(v, ((m[0] + m[2]) / 2, (m[1] + m[3]) / 2 + 30), "car", (255, 255, 255, 200))
    # Boats tied up along the pier and the quay.
    v.sprite(ART / "boats" / "tugboat.png", (p[0] - 110, 8880), 150, math.pi / 2)
    v.sprite(ART / "boats" / "duck.png", (p[2] + 100, 8820), 120, math.pi / 2)
    v.sprite(ART / "boats" / "swan.png", (4120, 8780), 120, math.pi * 0.62)
    v.sprite(art_or("town/island/sailboat.png", sailboat_img), (5840, 8800), 200)


def pad(v: View, r, colour, kind):
    layer = Image.new("RGBA", v.img.size)
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(v.box(r), radius=v.s(30), fill=colour + (235,), outline=(255, 255, 255, 255), width=max(1, round(v.s(8))))
    v.img.alpha_composite(layer)
    icon(v, ((r[0] + r[2]) / 2, (r[1] + r[3]) / 2), kind, (255, 255, 255, 255))


def icon(v: View, at, kind, colour):
    """What the pad turns you into: a boat (hull and wave) or a car (body and wheels)."""
    layer = Image.new("RGBA", v.img.size)
    d = ImageDraw.Draw(layer)
    x, y = at
    if kind == "boat":
        d.polygon(v.pts([(x - 110, y - 10), (x + 110, y - 10), (x + 70, y + 50), (x - 80, y + 50)]), fill=colour)
        d.polygon(v.pts([(x - 10, y - 20), (x - 10, y - 120), (x + 70, y - 20)]), fill=colour)
        d.line(v.pts([(x - 130, y + 85), (x - 80, y + 70), (x - 30, y + 85), (x + 20, y + 70), (x + 70, y + 85),
                      (x + 120, y + 70)]), fill=colour, width=max(1, round(v.s(12))))
    else:
        d.rounded_rectangle(v.box((x - 110, y - 50, x + 110, y + 30)), radius=v.s(26), fill=colour)
        d.rounded_rectangle(v.box((x - 60, y - 100, x + 60, y - 30)), radius=v.s(20), fill=colour)
        for wx in (x - 60, x + 60):
            d.ellipse(v.box((wx - 30, y + 10, wx + 30, y + 70)), fill=colour)
    v.img.alpha_composite(layer)


def coin_trail(v: View, points):
    for at in points:
        v.sprite(ART / "ui" / "coin.png", at, 56)


def arc(a, b, bulge, n):
    (ax, ay), (bx, by) = a, b
    mx, my = (ax + bx) / 2, (ay + by) / 2
    nx, ny = -(by - ay), bx - ax
    length = math.hypot(nx, ny) or 1
    cx, cy = mx + nx / length * bulge, my + ny / length * bulge
    return [((1 - t) ** 2 * ax + 2 * (1 - t) * t * cx + t * t * bx, (1 - t) ** 2 * ay + 2 * (1 - t) * t * cy + t * t * by)
            for t in (i / (n - 1) for i in range(n))]


def islet(v: View, at, r, rng, palms=1, rocks=True):
    x, y = at
    shape = [(x + math.cos(a) * r * (1 + 0.12 * math.sin(3 * a + r)), y + math.sin(a) * r * 0.8 * (1 + 0.1 * math.cos(5 * a)))
             for a in (math.tau * i / 40 for i in range(40))]
    grown = [(x + (px - x) * 1.35, y + (py - y) * 1.35) for px, py in shape]
    v.fill_poly(grown, v.tiled("shallows", None), soft=v.s(40))
    v.fill_poly(shape, v.tiled("beach", None), soft=v.s(8))
    if rocks:
        for k in range(4):
            a = rng.uniform(0, math.tau)
            v.sprite(ART / "props" / "water" / "rock.png", (x + math.cos(a) * r * 0.95, y + math.sin(a) * r * 0.75), 110, a)
    for k in range(palms):
        v.sprite(ART / "props" / "beach" / "palm_tree.png", (x + (k - (palms - 1) / 2) * 140, y - 20), 200, rng.uniform(0, 6))


def paint_sea(v: View, rng: random.Random):
    # The outer limit: a ring of buoys with clumps of rock, and darker open sea beyond.
    lim = limit_outline()
    for i in range(0, len(lim), 15):
        v.sprite(buoy_img((230, 70, 60)), lim[i], 60)
    for i in range(7, len(lim), 60):
        x, y = lim[i]
        for k in range(3):
            v.sprite(ART / "props" / "water" / "rock.png", (x + rng.uniform(-120, 120), y + rng.uniform(-120, 120)), 150,
                     rng.uniform(0, 6))
    # The lighthouse on its rock, out to the north-east, its beam sweeping round.
    lh = (WORLD_W + 1250, -1150)
    beam = Image.new("RGBA", v.img.size)
    bx, by = v.p(*lh)
    ImageDraw.Draw(beam).polygon([(bx, by), v.p(lh[0] - 1700, lh[1] + 900), v.p(lh[0] - 1300, lh[1] + 1500)],
                                 fill=(255, 240, 160, 70))
    v.img.alpha_composite(beam.filter(ImageFilter.GaussianBlur(max(1, v.s(30)))))
    islet(v, lh, 420, rng, palms=0)
    v.shadow((lh[0] + 30, lh[1] + 40), 190, 190, 70)
    v.sprite(art_or("town/island/lighthouse.png", lighthouse_img), (lh[0], lh[1] - 80), 420)
    # Islets with a ramp: line up, jump the sandbar, collect the coins in the air.
    for at, heading in (((WORLD_W + 1350, 4700), -math.pi / 2), ((-1450, 2300), math.pi / 2)):
        islet(v, at, 260, rng, palms=1, rocks=False)
        d = 1 if heading > 0 else -1
        ramp_at = (at[0], at[1] - d * 620)
        v.sprite(ART / "props" / "water" / "ramp.png", ramp_at, 260, heading)
        coin_trail(v, arc((at[0], at[1] - d * 400), (at[0], at[1] + d * 520), 0, 7))
    # The buoy slalom along the north shore, coins through the gates.
    y0 = -1250
    for k in range(10):
        x = 2400 + k * 560
        v.sprite(buoy_img((240, 150, 40) if k % 2 else (230, 70, 60)), (x, y0 + (220 if k % 2 else -220)), 70)
    coin_trail(v, [(2400 + k * 560 + 280, y0) for k in range(9)])
    # The shipwreck out to the north-west, a treasure chest on the sand beside it.
    wreck = (-1500, -1000)
    islet(v, (wreck[0] + 260, wreck[1] + 220), 170, rng, palms=0)
    v.sprite(ART / "props" / "water" / "shipwreck_2.png", wreck, 420, 0.4)
    v.sprite(ART / "props" / "water" / "treasure_chest.png", (wreck[0] + 280, wreck[1] + 210), 110)
    # Coin trails round the coast.
    coin_trail(v, arc((900, WORLD_H + 1100), (3300, WORLD_H + 1300), 400, 9))
    coin_trail(v, arc((WORLD_W + 1000, 7200), (WORLD_W + 900, 9200), -300, 8))
    coin_trail(v, arc((-1100, 5200), (-1200, 7200), 260, 8))
    # Dolphins leaping in the west, seagulls over the harbour and the lighthouse.
    for k, (dx, dy) in enumerate(((-1700, 6200), (-1950, 6420), (-1500, 6500))):
        ring = Image.new("RGBA", v.img.size)
        x, y = v.p(dx + 20, dy + 10)
        ImageDraw.Draw(ring).ellipse((x - v.s(110), y - v.s(46), x + v.s(110), y + v.s(46)), outline=(255, 255, 255, 160),
                                     width=max(1, round(v.s(8))))
        v.img.alpha_composite(ring)
        v.sprite(art_or("town/island/dolphin.png", dolphin_img), (dx, dy), 200, -0.35 + k * 0.15)
    for at in ((4300, WORLD_H + 900), (4900, WORLD_H + 1250), (5600, WORLD_H + 1000), (WORLD_W + 900, -700),
               (WORLD_W + 1600, -1500)):
        v.sprite(art_or("town/island/seagull.png", gull_img), at, 110)
    # Two sailboats on fixed loops: one round the whole island, one round the east islet.
    loop = outline(1250, wobble=0.3)
    dots = Image.new("RGBA", v.img.size)
    dd = ImageDraw.Draw(dots)
    for i in range(0, len(loop), 3):
        x, y = v.p(*loop[i])
        dd.ellipse((x - v.s(14), y - v.s(14), x + v.s(14), y + v.s(14)), fill=(255, 255, 255, 110))
    small = [(WORLD_W + 1350 + math.cos(a) * 820, 4700 + math.sin(a) * 640) for a in (math.tau * i / 60 for i in range(60))]
    for x, y in small[::2]:
        x, y = v.p(x, y)
        dd.ellipse((x - v.s(12), y - v.s(12), x + v.s(12), y + v.s(12)), fill=(255, 255, 255, 110))
    v.img.alpha_composite(dots)
    i = len(loop) // 5
    # Side-on, never turned: mirrored when sailing left.
    for at, nxt in ((loop[i], loop[i + 1]), (small[40], small[41])):
        boat = art_or("town/island/sailboat.png", sailboat_img)
        if nxt[0] < at[0]:
            boat = boat.transpose(Image.FLIP_LEFT_RIGHT)
        v.sprite(boat, at, 260)


def label(v: View, text, at, size=16, anchor="la"):
    d = ImageDraw.Draw(v.img)
    f = ImageFont.truetype(str(FONT), size)
    x, y = at
    bb = d.textbbox((x, y), text, font=f, anchor=anchor)
    d.rounded_rectangle((bb[0] - 10, bb[1] - 8, bb[2] + 10, bb[3] + 8), radius=8, fill=(20, 32, 46, 215))
    d.text((x, y), text, font=f, fill=(240, 244, 248, 255), anchor=anchor)


def wake_behind(v: View, at, heading, length=420, width=70):
    layer = Image.new("RGBA", v.img.size)
    d = ImageDraw.Draw(layer)
    hx, hy = math.cos(heading), math.sin(heading)
    nx, ny = -hy, hx
    tail = (at[0] - hx * length, at[1] - hy * length)
    for side in (1, -1):
        d.line([v.p(at[0] - hx * 50, at[1] - hy * 50), v.p(tail[0] + nx * side * width, tail[1] + ny * side * width)],
               fill=(255, 255, 255, 170), width=max(1, round(v.s(9))))
    d.line([v.p(at[0] - hx * 50, at[1] - hy * 50), v.p(*tail)], fill=(255, 255, 255, 110), width=max(1, round(v.s(26))))
    v.img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(max(1, v.s(3)))))


# --- the photographs and the three pictures ----------------------------------------------

def photograph(tmp: Path):
    """The game's own pictures: the whole town, and the south ring road at game scale."""
    # The south shot has the car on the ring road low in the picture, so the street is clear
    # of the HUD in the top corners.
    shots = {"overview": ("1920x1080", ["--overview"]), "south": ("1920x1080", ["--start=4960,7300"])}
    out = {}
    for name, (size, flags) in shots.items():
        path = tmp / f"{name}.png"
        subprocess.run([GODOT, "--path", str(ROOT), "--resolution", size, "--",
                        f"--save={tmp / 'save.json'}", f"--settings={tmp / 'settings.cfg'}", "--screen=town",
                        *flags, f"--screenshot={path}", "--wait=2.5"], check=True, capture_output=True, timeout=180)
        out[name] = Image.open(path).convert("RGB")
    return out


def screen_mapper(photo: Image.Image, centre, zoom):
    """World -> photo px for a screenshot centred on `centre` at camera `zoom` (the window
    may have been resized, and canvas_items stretch scales the 1080-high view to fit)."""
    k = zoom * photo.height / 1080.0
    return lambda x, y: (photo.width / 2 + (x - centre[0]) * k, photo.height / 2 + (y - centre[1]) * k)


def overview(photos, sketch):
    pad_px = LIMIT + 450
    v = View((-pad_px, -pad_px, WORLD_W + pad_px, WORLD_H + pad_px), 0.12)
    paint_ground(v)
    zoom = min(1920 / WORLD_W, 1080 / WORLD_H)
    town = (STREETS[0] - 200, STREETS[1] - 200, STREETS[2] + 200, STREETS[3] + 200)
    paste_town(v, photos["overview"], town, screen_mapper(photos["overview"], (WORLD_W / 2, WORLD_H / 2), zoom), 180)
    rng = random.Random(21)
    paint_beach_life(v, rng)
    paint_harbour(v, sketch)
    paint_sea(v, rng)
    v.sprite(ART / "boats" / "speedboat.png", (5800, WORLD_H + 1500), 150, math.pi * 0.2)
    wake_behind(v, (5800, WORLD_H + 1500), math.pi * 0.2, 900, 160)
    notes = [
        ("HARBOUR: car <-> boat", (4960, WORLD_H + 2050), "ma"),
        ("LIGHTHOUSE", (WORLD_W + 1250, -1750), "md"),
        ("RAMP ISLET", (WORLD_W + 1350, 5250), "ma"),
        ("RAMP ISLET", (-1450, 2900), "ma"),
        ("BUOY SLALOM", (5000, -1700), "md"),
        ("SHIPWRECK", (-1300, -1650), "md"),
        ("DOLPHINS", (-1700, 6800), "ma"),
        ("SAILBOAT LOOP", (WORLD_W + 1700, 2200), "ma"),
        ("OUTER LIMIT", (-LIMIT + 300, WORLD_H + LIMIT + 120), "la"),
    ]
    for text, at, anchor in notes:
        label(v, text, v.p(*at), 15, anchor)
    title(v.img, "PHASE 21 - THE ISLAND", "Free Drive's town with a beach, the ocean all round and a harbour")
    return v.img


def title(img, head, sub):
    d = ImageDraw.Draw(img)
    f1, f2 = ImageFont.truetype(str(FONT), 26), ImageFont.truetype(str(FONT), 13)
    d.rounded_rectangle((20, 20, 40 + max(d.textlength(head, font=f1), d.textlength(sub, font=f2)), 104), radius=12,
                        fill=(20, 32, 46, 225))
    d.text((30, 34), head, font=f1, fill=(255, 220, 90))
    d.text((30, 78), sub, font=f2, fill=(230, 236, 240))


def closeup(photos, sketch):
    """The harbour at game scale (zoom 1.0), from the ring road down past the mooring."""
    rect = CLOSEUP
    v = View(rect, 1.0)
    paint_ground(v)
    south = photos["south"]
    mapper = screen_mapper(south, (4960, 7300), 1.0)
    paste_town(v, south, (rect[0], rect[1], rect[2], STREETS[3] + 40), mapper, 0)
    rng = random.Random(4)
    paint_beach_life(v, rng)
    paint_harbour(v, sketch)
    for at in ((4120, 9350), (5800, 9500)):
        v.sprite(ART / "props" / "water" / "rock.png", at, 130, rng.uniform(0, 6))
    v.sprite(art_or("town/island/seagull.png", gull_img), (5300, 9050), 110)
    v.sprite(art_or("town/island/seagull.png", gull_img), (4200, 8450), 100)
    coin_trail(v, arc((5000, 9550), (5850, 9250), 120, 6))
    # The car heading down the harbour road, the boat leaving the mooring.
    v.sprite(ART / "cars" / "car_red.png", (DRIVE_X - 60, 7980), 128, math.pi / 2)
    boat_at = ((MOORING[0] + MOORING[2]) / 2, MOORING[3] + 160)
    wake_behind(v, boat_at, math.pi / 2, 260, 50)
    v.sprite(ART / "boats" / "speedboat.png", boat_at, 128, math.pi / 2)
    notes = [
        ("1 HARBOUR", ((BUILDING[0] + BUILDING[2]) / 2, BUILDING[1] - 30), "md"),
        ("2 LAND PAD: drive on = swap to boat", ((LAND_PAD[0] + LAND_PAD[2]) / 2, LAND_PAD[3] + 30), "ma"),
        ("3 PIER", (PIER[2] + 60, 8980), "la"),
        ("4 MOORING: sail in = swap to car", (MOORING[2] + 60, MOORING[1] + 60), "la"),
        ("HARBOUR ROAD", (DRIVE_X + DRIVE_HALF + 30, 7830), "la"),
        ("SLIPWAY", (SLIPWAY[2] + 30, SLIPWAY[1] + 80), "la"),
        ("QUAY", (5040, 8420), "ma"),
        ("BEACH", (4030, 8400), "la"),
    ]
    for text, at, anchor in notes:
        label(v, text, v.p(*at), 20, anchor)
    title(v.img, "THE HARBOUR - game scale", "Every pixel is a world pixel at camera zoom 1.0")
    return v.img


def swap_views(close: Image.Image):
    """Two 1920x1080 game views cut from the close-up: the car on the land pad, the boat at
    the mooring."""
    x0, y0 = CLOSEUP[0], CLOSEUP[1]
    out = Image.new("RGB", (1920, 1080 // 2 + 60), (20, 32, 46))
    for i, (centre, text) in enumerate((
            (((LAND_PAD[0] + LAND_PAD[2]) / 2, (LAND_PAD[1] + LAND_PAD[3]) / 2), "THE LAND PAD (camera on the car)"),
            (((MOORING[0] + MOORING[2]) / 2, (MOORING[1] + MOORING[3]) / 2 + 120), "THE MOORING (the boat sails off)"))):
        cx = min(max(centre[0] - x0, 960), close.width - 960)
        cy = min(max(centre[1] - y0, 540), close.height - 540)
        view = close.crop((round(cx - 960), round(cy - 540), round(cx + 960), round(cy + 540))).resize((950, 534), Image.LANCZOS)
        out.paste(view.convert("RGB"), (i * 970, 60))
        d = ImageDraw.Draw(out)
        d.text((i * 970 + 10, 20), f"{i + 1}  {text}", font=ImageFont.truetype(str(FONT), 18), fill=(255, 220, 90))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sketch = harbour_sketch()
    with tempfile.TemporaryDirectory() as tmp:
        photos = photograph(Path(tmp))
    overview(photos, sketch).convert("RGB").save(OUT / "01_island_overview.png")
    close = closeup(photos, sketch)
    close.convert("RGB").save(OUT / "02_harbour_closeup.png")
    swap_views(close).save(OUT / "03_swap_views.png")
    sketch.save(OUT / "harbour_sketch.png")
    print("wrote", *sorted(p.name for p in OUT.iterdir()))


if __name__ == "__main__":
    main()

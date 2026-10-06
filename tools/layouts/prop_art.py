"""Props, wall props and the cup icon for the Jungle, Candy and Moon themes (docs/DESIGN.md §7.5).

    python tools/layouts/prop_art.py            # every picture
    python tools/layouts/prop_art.py --sheet    # also a review sheet in docs/mockups/

The first four themes' props were generated with FLUX (tools/comfy/). These are drawn by
script instead, in the same soft clay look: each picture is a stack of flat shapes, every
shape is given a pillowy height from its own blurred outline, and the height field is lit
from the top left like the generated props (soft diffuse light, a glossy highlight, a little
shade in the creases). Everything is seen from directly above, as in the rest of the game.
Seeded, so a rebuild is byte-identical.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SS = 3  # supersampling: drawn at 3x, lit, then scaled down
LIGHT = np.array([-0.45, -0.55, 0.70])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
HALF = (LIGHT + np.array([0.0, 0.0, 1.0])) / np.linalg.norm(LIGHT + np.array([0.0, 0.0, 1.0]))


def _blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian blur of a float array (PIL cannot blur float images), edges padded."""
    r = int(math.ceil(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    p = np.pad(a, r, mode="edge")
    p = np.apply_along_axis(lambda v: np.convolve(v, k, mode="valid"), 0, p)
    return np.apply_along_axis(lambda v: np.convolve(v, k, mode="valid"), 1, p).astype(np.float32)


class Clay:
    """A picture built from shapes painted bottom to top, then lit as one height field."""

    def __init__(self, size: int, seed: int = 0):
        self.size = size
        self.n = size * SS
        self.rgb = np.zeros((self.n, self.n, 3), np.float32)
        self.alpha = np.zeros((self.n, self.n), np.float32)
        self.height = np.zeros((self.n, self.n), np.float32)
        self.gloss = np.zeros((self.n, self.n), np.float32)
        self.rng = np.random.default_rng(seed)

    # --- shapes, in output pixels; each returns a hi-res mask ------------------------------
    def _canvas(self):
        img = Image.new("L", (self.n, self.n), 0)
        return img, ImageDraw.Draw(img)

    def circle(self, cx, cy, r):
        return self.ellipse(cx, cy, r, r)

    def ellipse(self, cx, cy, rx, ry, angle=0.0):
        if angle == 0.0:
            img, d = self._canvas()
            d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=255)
            return np.asarray(img, np.float32) / 255.0
        pts = [(cx + rx * math.cos(t) * math.cos(angle) - ry * math.sin(t) * math.sin(angle),
                cy + rx * math.cos(t) * math.sin(angle) + ry * math.sin(t) * math.cos(angle))
               for t in np.linspace(0, math.tau, 72, endpoint=False)]
        return self.polygon(pts)

    def polygon(self, pts):
        img, d = self._canvas()
        d.polygon([(x * SS, y * SS) for x, y in pts], fill=255)
        return np.asarray(img, np.float32) / 255.0

    def rect(self, x0, y0, x1, y1, radius=0.0):
        img, d = self._canvas()
        d.rounded_rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], radius=radius * SS, fill=255)
        return np.asarray(img, np.float32) / 255.0

    def line(self, pts, width):
        img, d = self._canvas()
        d.line([(x * SS, y * SS) for x, y in pts], fill=255, width=int(width * SS), joint="curve")
        for x, y in (pts[0], pts[-1]):
            d.ellipse([(x - width / 2) * SS, (y - width / 2) * SS, (x + width / 2) * SS, (y + width / 2) * SS], fill=255)
        return np.asarray(img, np.float32) / 255.0

    def leaf(self, cx, cy, length, width, angle, base_gap=0.0):
        """A pointed leaf from (cx, cy) outwards along `angle`."""
        pts = []
        for t in np.linspace(0, 1, 24):
            w = width * math.sin(math.pi * t) ** 0.8
            pts.append((base_gap + t * length, w))
        for t in np.linspace(1, 0, 24):
            w = width * math.sin(math.pi * t) ** 0.8
            pts.append((base_gap + t * length, -w))
        ca, sa = math.cos(angle), math.sin(angle)
        return self.polygon([(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts])

    # --- painting ------------------------------------------------------------------------
    def paint(self, mask, colour, z=0.0, bulge=6.0, gloss=0.25, absolute=False, noise=0.0):
        """Lay a shape on top. Its top is `z` above what lies beneath (or above zero when
        `absolute`), rising `bulge` px towards its middle with rounded edges."""
        m = np.clip(mask, 0.0, 1.0)
        if not m.any():
            return
        blur_px = max(1.0, bulge * SS * 0.9)
        dome = np.sqrt(np.clip(_blur(m, blur_px), 0.0, 1.0)) * bulge * SS
        base = np.where(m > 0.5, (0.0 if absolute else self._under(m)) + z * SS, 0.0)
        col = np.broadcast_to(np.asarray(colour, np.float32), self.rgb.shape).copy()
        if noise:
            col *= (1.0 + noise * self.rng.standard_normal((self.n, self.n, 1)).astype(np.float32))
        sel = m[..., None]
        self.rgb = self.rgb * (1 - sel) + col * sel
        self.height = np.where(m > 0.5, base + dome, self.height)
        self.gloss = np.where(m > 0.5, gloss, self.gloss)
        self.alpha = np.maximum(self.alpha, m)

    def _under(self, m):
        """The height of what is already beneath a new shape (its highest point under it),
        so a shape laid on another sits on top of it rather than sinking into it."""
        inside = m > 0.5
        return float(self.height[inside].max()) if inside.any() else 0.0

    def speckle(self, mask, colours, count, radius, z=0.6):
        """Small dots (sprinkles, sugar, spots) scattered inside a mask."""
        ys, xs = np.nonzero(mask > 0.5)
        if len(xs) == 0:
            return
        for _ in range(count):
            k = self.rng.integers(len(xs))
            x, y = xs[k] / SS, ys[k] / SS
            c = colours[self.rng.integers(len(colours))]
            self.paint(self.circle(x, y, radius), c, z=z, bulge=radius * 0.8, gloss=0.4)

    def sprinkle(self, mask, colours, count, length, width, z=0.8):
        ys, xs = np.nonzero(mask > 0.5)
        for _ in range(count):
            k = self.rng.integers(len(xs))
            x, y = xs[k] / SS, ys[k] / SS
            a = self.rng.uniform(0, math.pi)
            dx, dy = math.cos(a) * length / 2, math.sin(a) * length / 2
            self.paint(self.line([(x - dx, y - dy), (x + dx, y + dy)], width), colours[self.rng.integers(len(colours))],
                       z=z, bulge=width * 0.5, gloss=0.45)

    # --- light ---------------------------------------------------------------------------
    def render(self) -> Image.Image:
        h = _blur(self.height, SS * 0.7)
        gy, gx = np.gradient(h)
        nrm = np.dstack([-gx, -gy, np.ones_like(h)])
        nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
        diffuse = np.clip(nrm @ LIGHT, 0.0, 1.0)
        spec = np.clip(nrm @ HALF, 0.0, 1.0) ** 24 * self.gloss
        # Crease shade: darker where a point lies below its surroundings.
        wide = _blur(self.height, SS * 6)
        ao = np.clip(1.0 - (wide - h) / (SS * 14.0), 0.72, 1.0)
        shade = (0.52 + 0.62 * diffuse) * ao
        rgb = self.rgb * shade[..., None] + 255.0 * spec[..., None]
        out = np.dstack([np.clip(rgb, 0, 255), np.clip(self.alpha * 255.0, 0, 255)]).astype(np.uint8)
        return _downscale(Image.fromarray(out, "RGBA"), self.size)


def _downscale(img: Image.Image, size: int) -> Image.Image:
    """Scaled with premultiplied alpha, so the transparent edge does not darken."""
    a = np.asarray(img, np.float32)
    pre = a[..., :3] * (a[..., 3:4] / 255.0)
    small_pre = np.asarray(Image.fromarray(np.clip(pre, 0, 255).astype(np.uint8)).resize((size, size), Image.LANCZOS),
                           np.float32)
    small_a = np.asarray(Image.fromarray(a[..., 3].astype(np.uint8)).resize((size, size), Image.LANCZOS), np.float32)
    rgb = np.where(small_a[..., None] > 0, small_pre * 255.0 / np.maximum(small_a[..., None], 1.0), 0.0)
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), small_a]).astype(np.uint8), "RGBA")


def _blob(c: Clay, cx, cy, r, lumps, seed_phase=0.0, wobble=0.18):
    """A lumpy round outline (rocks, bushes)."""
    pts = []
    for t in np.linspace(0, math.tau, 90, endpoint=False):
        k = 1.0 + wobble * sum(math.sin(f * t + seed_phase * (f + 1)) / f for f in lumps)
        pts.append((cx + r * k * math.cos(t), cy + r * k * math.sin(t)))
    return c.polygon(pts)


# --- jungle ------------------------------------------------------------------------------

def jungle_tree() -> Image.Image:
    """A big round canopy of broad leaves, darker underneath, a few bright leaves on top."""
    size = 216
    c = Clay(size, seed=51)
    cx = cy = size / 2
    rng = np.random.default_rng(5)
    rings = [(8, 86, 44, (40, 112, 50), 0.0), (7, 70, 40, (60, 146, 58), 0.45), (5, 46, 32, (90, 176, 70), 0.15),
             (3, 24, 22, (122, 198, 86), 0.7)]
    for count, length, width, colour, phase in rings:
        for k in range(count):
            a = math.tau * (k + phase) / count + rng.uniform(-0.12, 0.12)
            c.paint(c.leaf(cx, cy, length + rng.uniform(-6, 6), width / 2, a, base_gap=6), colour, z=1.5, bulge=7,
                    gloss=0.3)
            # the leaf's middle vein
            ca, sa = math.cos(a), math.sin(a)
            vein = c.line([(cx + ca * 14, cy + sa * 14), (cx + ca * (length - 10), cy + sa * (length - 10))], 2.4)
            c.paint(vein * (c.alpha > 0.5), tuple(min(255, v + 40) for v in colour), z=0.3, bulge=0.8, gloss=0.1)
    c.paint(c.circle(cx, cy, 10), (150, 206, 96), z=2, bulge=6)
    return c.render()


def jungle_flower() -> Image.Image:
    """A big tropical flower: five pink petals, a yellow middle, two leaves underneath."""
    size = 112
    c = Clay(size, seed=52)
    cx = cy = size / 2
    for a in (0.6, 3.6):
        c.paint(c.leaf(cx, cy, 50, 12, a, base_gap=4), (70, 150, 60), bulge=5, gloss=0.2)
    for k in range(5):
        a = math.tau * k / 5 - math.pi / 2
        px, py = cx + math.cos(a) * 20, cy + math.sin(a) * 20
        c.paint(c.ellipse(px, py, 21, 15, angle=a), (255, 96, 150), z=2, bulge=7, gloss=0.35)
    c.paint(c.circle(cx, cy, 12), (255, 190, 70), z=2, bulge=6, gloss=0.3)
    c.speckle(c.circle(cx, cy, 9), [(255, 236, 140), (240, 150, 40)], 14, 1.6)
    return c.render()


def boulder() -> Image.Image:
    """A round grey boulder with moss on top: the jungle's map-edge wall and its rocks."""
    size = 96
    c = Clay(size, seed=53)
    body = _blob(c, 48, 48, 38, (2, 3, 5), 0.7)
    c.paint(body, (140, 140, 134), bulge=22, gloss=0.15, noise=0.03)
    moss = _blob(c, 42, 40, 22, (2, 3, 4), 2.1, 0.3) * body
    c.paint(moss, (96, 160, 70), z=1, bulge=5, gloss=0.1, noise=0.05)
    return c.render()


# --- candy -------------------------------------------------------------------------------

def lollipop() -> Image.Image:
    """A swirl lollipop seen from above (the stick hidden beneath it)."""
    size = 120
    c = Clay(size, seed=61)
    cx = cy = size / 2
    disc = c.circle(cx, cy, 52)
    c.paint(disc, (255, 255, 255), bulge=10, gloss=0.5)
    # A two-arm spiral of pink over the white.
    for arm, colour in ((0, (255, 72, 132)), (math.pi, (255, 150, 60))):
        pts = [(cx + r * math.cos(arm + r / 9.0), cy + r * math.sin(arm + r / 9.0)) for r in np.linspace(2, 50, 80)]
        c.paint(c.line(pts, 11) * disc, colour, z=0.2, bulge=1.5, gloss=0.5)
    return c.render()


def donut() -> Image.Image:
    """A pink-iced ring donut with sprinkles; the hole shows the ground."""
    size = 128
    c = Clay(size, seed=62)
    cx = cy = size / 2
    hole = c.circle(cx, cy, 15)
    dough = np.clip(c.circle(cx, cy, 58) - hole, 0, 1)
    c.paint(dough, (214, 150, 84), bulge=16, gloss=0.15)
    icing_pts = [(cx + (49 + 4 * math.sin(7 * t)) * math.cos(t), cy + (49 + 4 * math.sin(7 * t)) * math.sin(t))
                 for t in np.linspace(0, math.tau, 120, endpoint=False)]
    icing = np.clip(c.polygon(icing_pts) - c.circle(cx, cy, 22), 0, 1)
    c.paint(icing, (255, 142, 190), z=0.5, bulge=4, gloss=0.55)
    c.sprinkle(icing * np.clip(1 - c.circle(cx, cy, 25), 0, 1),
               [(255, 255, 255), (80, 170, 255), (255, 220, 60), (120, 220, 140)], 26, 8, 3)
    c.alpha *= 1 - hole
    return c.render()


def cupcake() -> Image.Image:
    """A cupcake from above: a ridged paper case, a swirl of frosting and a cherry."""
    size = 120
    c = Clay(size, seed=63)
    cx = cy = size / 2
    case = [(cx + (54 + 3 * math.cos(18 * t)) * math.cos(t), cy + (54 + 3 * math.cos(18 * t)) * math.sin(t))
            for t in np.linspace(0, math.tau, 144, endpoint=False)]
    c.paint(c.polygon(case), (120, 200, 230), bulge=6, gloss=0.2)
    for r, colour in ((44, (255, 240, 246)), (33, (255, 214, 232)), (22, (255, 240, 246))):
        c.paint(c.circle(cx + 1, cy + 1, r), colour, z=1.5, bulge=8, gloss=0.4)
    c.sprinkle(c.circle(cx, cy, 42) * (1 - c.circle(cx, cy, 14)), [(255, 90, 140), (90, 180, 255), (255, 210, 60)],
               18, 6, 2.5)
    c.paint(c.circle(cx - 2, cy - 2, 11), (220, 30, 60), z=2, bulge=9, gloss=0.8)
    return c.render()


def gumdrop() -> Image.Image:
    """A sugared green gumdrop: Candy Lane's map-edge wall."""
    size = 76
    c = Clay(size, seed=64)
    body = c.circle(38, 38, 32)
    c.paint(body, (110, 214, 130), bulge=22, gloss=0.35)
    c.speckle(body, [(214, 255, 220), (255, 255, 255)], 40, 1.3, z=0.3)
    return c.render()


# --- moon --------------------------------------------------------------------------------

def rocket() -> Image.Image:
    """A rocket standing on its pad, seen from straight above: the round body with its red
    nose cone in the middle and four fins."""
    size = 176
    c = Clay(size, seed=71)
    cx = cy = size / 2
    for k in range(4):
        a = math.tau * k / 4 + math.pi / 4
        ca, sa = math.cos(a), math.sin(a)
        fin = [(cx + ca * 20 - sa * 9, cy + sa * 20 + ca * 9), (cx + ca * 66 - sa * 5, cy + sa * 66 + ca * 5),
               (cx + ca * 70, cy + sa * 70), (cx + ca * 66 + sa * 5, cy + sa * 66 - ca * 5),
               (cx + ca * 20 + sa * 9, cy + sa * 20 - ca * 9)]
        c.paint(c.polygon(fin), (230, 57, 70), z=2, bulge=5, gloss=0.4)
    c.paint(c.circle(cx, cy, 36), (244, 244, 246), z=4, bulge=14, gloss=0.5)
    c.paint(c.circle(cx, cy, 36) - c.circle(cx, cy, 30), (58, 134, 255), z=0.3, bulge=1, gloss=0.4)
    c.paint(c.circle(cx, cy, 22), (230, 57, 70), z=1, bulge=14, gloss=0.6)
    for k in range(3):  # portholes peeking out round the body
        a = math.tau * k / 3 - math.pi / 2
        c.paint(c.circle(cx + math.cos(a) * 33, cy + math.sin(a) * 33, 5.5), (90, 200, 255), z=1, bulge=3, gloss=0.9)
    return c.render()


def satellite_dish() -> Image.Image:
    """A dish aerial pointing up: a white bowl with a feed on three struts, on a base."""
    size = 160
    c = Clay(size, seed=72)
    cx = cy = size / 2
    c.paint(c.rect(cx - 30, cy + 22, cx + 30, cy + 74, 10), (120, 126, 140), bulge=6, gloss=0.2)  # base box
    c.paint(c.rect(cx - 20, cy + 52, cx + 20, cy + 64, 4), (255, 200, 40), z=0.5, bulge=2, gloss=0.3)
    dish = c.circle(cx, cy - 4, 60)
    c.paint(dish, (236, 238, 244), z=6, bulge=8, gloss=0.4)
    c.paint(c.circle(cx, cy - 4, 50), (214, 218, 228), z=-4, bulge=-6, gloss=0.3)  # the bowl dips
    for k in range(3):
        a = math.tau * k / 3 + 0.5
        c.paint(c.line([(cx + math.cos(a) * 48, cy - 4 + math.sin(a) * 48), (cx, cy - 4)], 4), (150, 156, 170),
                z=4, bulge=2, gloss=0.3)
    c.paint(c.circle(cx, cy - 4, 9), (230, 57, 70), z=6, bulge=6, gloss=0.7)
    return c.render()


def moon_rock() -> Image.Image:
    """A lumpy grey-violet moon rock with two little craters: Moon Base's map-edge wall."""
    size = 92
    c = Clay(size, seed=73)
    body = _blob(c, 46, 46, 37, (2, 3, 5), 1.3, 0.2)
    c.paint(body, (164, 156, 186), bulge=20, gloss=0.15, noise=0.03)
    for x, y, r in ((36, 38, 9), (58, 56, 6)):
        c.paint(c.circle(x, y, r), (136, 128, 160), z=-3, bulge=-3, gloss=0.05)
    return c.render()


# --- cup icon ----------------------------------------------------------------------------

def cup_star() -> Image.Image:
    """The Starlight Cup: a smiling yellow star, like the sun and snowflake cups."""
    size = 200
    c = Clay(size, seed=81)
    cx, cy = size / 2, size / 2 + 6
    pts = []
    for k in range(10):
        a = -math.pi / 2 + math.pi * k / 5
        r = 92 if k % 2 == 0 else 44
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    star = c.polygon(pts)
    # Round the points a little: blur and re-threshold the outline.
    soft = _blur(star, SS * 5)
    star = np.clip((soft - 0.42) * 8, 0, 1)
    c.paint(star, (255, 196, 40), bulge=26, gloss=0.35)
    inner = np.clip((soft - 0.62) * 8, 0, 1)
    c.paint(inner, (255, 224, 90), z=-1, bulge=8, gloss=0.35)
    for x in (cx - 18, cx + 18):  # eyes, with a shine
        c.paint(c.ellipse(x, cy - 6, 7, 9), (50, 40, 40), z=1, bulge=3, gloss=0.6)
        c.paint(c.circle(x + 2.5, cy - 9, 2.6), (255, 255, 255), z=1, bulge=1, gloss=0.2)
    for x in (cx - 32, cx + 32):  # cheeks
        c.paint(c.ellipse(x, cy + 10, 9, 6), (255, 150, 120), z=0.2, bulge=1, gloss=0.1)
    smile = [(cx + 16 * math.cos(t), cy + 8 + 12 * math.sin(t)) for t in np.linspace(0.15 * math.pi, 0.85 * math.pi, 20)]
    c.paint(c.line(smile, 5), (120, 40, 40), z=0.5, bulge=1, gloss=0.2)
    return c.render()


PICTURES = {
    "art/props/jungle/jungle_tree.png": jungle_tree,
    "art/props/jungle/jungle_flower.png": jungle_flower,
    "art/props/jungle/boulder.png": boulder,
    "art/props/candy/lollipop.png": lollipop,
    "art/props/candy/donut.png": donut,
    "art/props/candy/cupcake.png": cupcake,
    "art/props/candy/gumdrop.png": gumdrop,
    "art/props/moon/rocket.png": rocket,
    "art/props/moon/satellite_dish.png": satellite_dish,
    "art/props/moon/moon_rock.png": moon_rock,
    "art/ui/cups/cup_star.png": cup_star,
}


def sheet(images: dict) -> Image.Image:
    """Every picture on each theme's ground, for review."""
    grounds = [(92, 168, 64), (246, 192, 216), (214, 210, 226)]
    w = sum(im.width + 16 for im in images.values()) + 16
    out = Image.new("RGBA", (w, 3 * 240), (0, 0, 0, 255))
    for row, g in enumerate(grounds):
        out.paste(Image.new("RGBA", (w, 240), g + (255,)), (0, row * 240))
        x = 16
        for im in images.values():
            out.alpha_composite(im, (x, row * 240 + (240 - im.height) // 2))
            x += im.width + 16
    return out


def main() -> None:
    images = {}
    for rel, draw in PICTURES.items():
        out = ROOT / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        images[rel] = draw()
        images[rel].save(out)
        print(f"  {rel} {images[rel].size}")
    if "--sheet" in sys.argv:
        sheet(images).save(ROOT / "docs/mockups/props_jungle_candy_moon.png")
        print("  docs/mockups/props_jungle_candy_moon.png")


if __name__ == "__main__":
    main()

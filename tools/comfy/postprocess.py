"""Local image post-processing: seamless tiling, sprite fitting, contact sheets."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT_PATH = Path("G:/Godot/external_assets/fonts/Public_Pixel_Font_1_24/PublicPixel.ttf")


def make_seamless(img: Image.Image) -> Image.Image:
    """Make a texture tile by blending it with a half-offset copy of itself.

    The offset copy tiles perfectly at its border but has a seam cross through
    the middle; the original is the reverse. Weighting each pixel by its
    distance to the two seams keeps whichever copy is clean at that point.
    """
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    h, w = a.shape[:2]
    r = np.roll(a, (h // 2, w // 2), axis=(0, 1))
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d_border = np.minimum.reduce([x, y, w - 1 - x, h - 1 - y])
    d_cross = np.minimum(np.abs(x - w / 2), np.abs(y - h / 2))
    weight = (d_border / (d_border + d_cross + 1e-6))[..., None]
    out = a * weight + r * (1.0 - weight)
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def flat_fill(size: int, base: tuple[int, int, int], variation: float = 0.0, waves: int = 4,
              speckle_density: float = 0.0, speckle_shift: int = 12, speckle_size: int = 2,
              speckle_sign: int = 0, seed: int = 0) -> Image.Image:
    """A near-flat ground tile that tiles perfectly by construction.

    Matches the chosen style frame, whose ground is flat colour: `variation` adds soft
    blotches (fraction of brightness) built from sine waves with whole numbers of cycles
    per tile, so the left edge always meets the right. Speckles wrap around the edges
    for the same reason. `speckle_sign` 1 makes every speckle brighter (stars on a space
    fill); 0 picks lighter or darker at random.
    """
    rng = np.random.default_rng(seed)
    # Blotches from a coarse random grid, upsampled smoothly. The grid is tiled 3 x 3 before
    # upsampling and the centre cut out, so the result wraps exactly — and unlike summed sine
    # waves it has no direction, so it never reads as diagonal stripes.
    grid = rng.standard_normal((waves, waves)).astype(np.float32)
    big = Image.fromarray(np.tile(grid, (3, 3)), mode="F").resize((3 * size, 3 * size), Image.BICUBIC)
    field = np.array(big, dtype=np.float32)[size:2 * size, size:2 * size]
    field /= max(1e-6, float(np.abs(field).max()))
    img = np.empty((size, size, 3), np.float32)
    img[:] = base
    img *= (1.0 + variation * field)[..., None]
    count = int(size * size * speckle_density / (speckle_size * speckle_size))
    for _ in range(count):
        cx, cy = rng.integers(0, size, size=2)
        shift = speckle_shift * (speckle_sign or rng.choice([-1, 1]))
        for dy in range(speckle_size):
            for dx in range(speckle_size):
                img[(cy + dy) % size, (cx + dx) % size] += shift
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def kerb_strip(length: int, thickness: int = 38, block: int = 48,
               red=(196, 47, 47), cream=(231, 231, 171)) -> Image.Image:
    """Chunky red/cream kerb blocks with a cream line along the road side (the bottom edge).

    Tiles along X when `length` is a multiple of 2 * block.
    """
    strip = Image.new("RGBA", (length, thickness), (0, 0, 0, 0))
    draw = ImageDraw.Draw(strip)
    line = 6
    draw.rectangle((0, thickness - line, length, thickness), fill=cream)
    for i, x in enumerate(range(0, length, block)):
        draw.rectangle((x, 0, x + block - 1, thickness - line - 3), fill=red if i % 2 == 0 else cream)
    return strip


def chequer(size: int = 64, square: int = 32) -> Image.Image:
    """Black-and-white chequer that tiles in both directions, for the start/finish line."""
    img = Image.new("RGB", (size, size), (245, 245, 240))
    draw = ImageDraw.Draw(img)
    for y in range(0, size, square):
        for x in range(0, size, square):
            if (x // square + y // square) % 2 == 0:
                draw.rectangle((x, y, x + square - 1, y + square - 1), fill=(30, 32, 36))
    return img


def punch_center_hole(img: Image.Image, dark_luma: int = 70) -> Image.Image:
    """Make the middle of a ring-shaped sprite transparent, out to its first dark pixel.

    For a tyre seen from above the matting keeps whatever the model drew in the hole (a rim,
    a light disc); looking down a stack you should see the ground. The radius is the median
    distance, over 64 rays from the centre, to the first pixel darker than `dark_luma`.
    """
    img = img.convert("RGBA")
    a = np.asarray(img).copy()
    h, w = a.shape[:2]
    cy, cx = h / 2, w / 2
    luma = a[..., :3] @ np.array([0.299, 0.587, 0.114])
    radii = []
    for angle in np.linspace(0, 2 * np.pi, 64, endpoint=False):
        for r in range(2, int(min(h, w) / 2)):
            y, x = int(cy + r * np.sin(angle)), int(cx + r * np.cos(angle))
            if luma[y, x] < dark_luma:
                radii.append(r)
                break
    if not radii:
        return img
    radius = float(np.median(radii))
    yy, xx = np.mgrid[0:h, 0:w]
    a[..., 3][(yy - cy) ** 2 + (xx - cx) ** 2 < radius ** 2] = 0
    return Image.fromarray(a)


def tile_grid(tile: Image.Image, n: int = 3) -> Image.Image:
    w, h = tile.size
    grid = Image.new(tile.mode, (w * n, h * n))
    for gy in range(n):
        for gx in range(n):
            grid.paste(tile, (gx * w, gy * h))
    return grid


def fit_sprite(img: Image.Image, box: tuple[int, int]) -> Image.Image:
    """Scale a cut-out to fit `box` keeping aspect, centred on a transparent canvas."""
    img = img.convert("RGBA")
    scale = min(box[0] / img.width, box[1] / img.height)
    resized = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", box, (0, 0, 0, 0))
    canvas.paste(resized, ((box[0] - resized.width) // 2, (box[1] - resized.height) // 2), resized)
    return canvas


def font(size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(str(FONT_PATH), size)
    except OSError:
        return ImageFont.load_default(size)


def contact_sheet(cells: list[tuple[Image.Image, str]], columns: int, cell: tuple[int, int],
                  title: str = "", bg=(40, 44, 52), checker: bool = False) -> Image.Image:
    """Lay labelled images out in a grid. `checker` shows transparency on cut-outs."""
    label_h, pad, title_h = 28, 16, (48 if title else 0)
    rows = (len(cells) + columns - 1) // columns
    sheet = Image.new("RGB", (pad + columns * (cell[0] + pad), title_h + pad + rows * (cell[1] + label_h + pad)), bg)
    draw = ImageDraw.Draw(sheet)
    if title:
        draw.text((pad, 14), title, font=font(20), fill=(240, 240, 240))
    for i, (img, label) in enumerate(cells):
        x = pad + (i % columns) * (cell[0] + pad)
        y = title_h + pad + (i // columns) * (cell[1] + label_h + pad)
        if checker:
            sheet.paste(_checkerboard(cell), (x, y))
        fitted = fit_sprite(img, cell) if img.mode == "RGBA" else img.resize(cell, Image.LANCZOS)
        sheet.paste(fitted, (x, y), fitted if fitted.mode == "RGBA" else None)
        draw.text((x, y + cell[1] + 8), label, font=font(12), fill=(220, 220, 220))
    return sheet


def _checkerboard(size: tuple[int, int], square: int = 16) -> Image.Image:
    board = Image.new("RGB", size, (200, 200, 200))
    draw = ImageDraw.Draw(board)
    for y in range(0, size[1], square):
        for x in range(0, size[0], square):
            if (x // square + y // square) % 2:
                draw.rectangle((x, y, x + square - 1, y + square - 1), fill=(160, 160, 160))
    return board


def sticker_border(img: Image.Image, width: float = 0.045, colour=(255, 255, 255)) -> Image.Image:
    """Give a cut-out the white die-cut edge of a sticker: the subject's silhouette grown by
    `width` of its longer side, smoothed into a round outline, filled white underneath.

    The growth is a distance field (a chamfer pass at a quarter of the size), so a thick
    edge on a 1500 px master costs well under a second.
    """
    img = img.convert("RGBA")
    pad = round(max(img.size) * width) + 4
    canvas = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    canvas.paste(img, (pad, pad), img)
    q = 4
    small = np.asarray(canvas.getchannel("A").resize((canvas.width // q, canvas.height // q), Image.BILINEAR)) > 96
    dist = _chamfer(small)
    grown = Image.fromarray(((dist <= (pad - 4) / q) * 255).astype(np.uint8))
    # A die-cut sticker has no holes: fill whatever the outside cannot reach.
    outside = grown.copy()
    ImageDraw.floodfill(outside, (0, 0), 128)
    grown = outside.point(lambda v: 0 if v == 128 else 255).resize(canvas.size, Image.BILINEAR)
    edge = grown.filter(ImageFilter.GaussianBlur(q)).point(lambda v: 255 if v > 127 else round(v * 2))
    out = Image.new("RGBA", canvas.size, colour + (0,))
    out.putalpha(edge)
    out.alpha_composite(canvas)
    return out


def _chamfer(inside: np.ndarray) -> np.ndarray:
    """Approximate Euclidean distance (in pixels) from every pixel to the nearest True one."""
    big = 1e9
    d = np.where(inside, 0.0, big)
    h, w = d.shape
    diag = 2 ** 0.5
    for y in range(h):  # forward pass, row by row (columns vectorised along the row)
        if y > 0:
            row = np.minimum(d[y], d[y - 1] + 1)
            row[1:] = np.minimum(row[1:], d[y - 1, :-1] + diag)
            row[:-1] = np.minimum(row[:-1], d[y - 1, 1:] + diag)
            d[y] = row
        d[y] = np.minimum.accumulate(d[y] - np.arange(w)) + np.arange(w)
    for y in range(h - 1, -1, -1):
        if y < h - 1:
            row = np.minimum(d[y], d[y + 1] + 1)
            row[1:] = np.minimum(row[1:], d[y + 1, :-1] + diag)
            row[:-1] = np.minimum(row[:-1], d[y + 1, 1:] + diag)
            d[y] = row
        rev = d[y, ::-1]
        d[y] = (np.minimum.accumulate(rev - np.arange(w)) + np.arange(w))[::-1]
    return d


def cover(img: Image.Image, box: tuple[int, int]) -> Image.Image:
    """Scale and centre-crop an image so it fills `box` exactly (a background)."""
    scale = max(box[0] / img.width, box[1] / img.height)
    resized = img.convert("RGB").resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left, top = (resized.width - box[0]) // 2, (resized.height - box[1]) // 2
    return resized.crop((left, top, left + box[0], top + box[1]))


def building_sketch(sketch: dict, size: int = 1536) -> Image.Image:
    """A flat block drawing of a town building in the game's street view: the roof seen from
    above on top, the front wall facing straight down below it, nothing at an angle.

    FLUX draws every building isometric however it is asked; Kontext keeps the layout of an
    image it edits, so it is given this drawing and only adds the detail (generate_assets.py).
    `sketch`: width, roof and wall as fractions of `size`; roof_colour and wall_colour; the
    front: "door" (a door between windows), "garages" (n big doors) or "open" (a counter).
    """
    img = Image.new("RGB", (size, size), (250, 250, 248))
    d = ImageDraw.Draw(img)
    w, roof_h, wall_h = (round(sketch[k] * size) for k in ("width", "roof", "wall"))
    roof, wall = tuple(sketch["roof_colour"]), tuple(sketch["wall_colour"])
    x0 = (size - w) // 2
    x1 = x0 + w
    top = (size - roof_h - wall_h) // 2
    eave = top + roof_h
    bottom = eave + wall_h
    dark = tuple(int(c * 0.8) for c in roof)
    d.rounded_rectangle((x0 + 30, top + 60, x1 + 40, bottom + 30), 60, fill=(228, 228, 225))  # shadow
    d.rounded_rectangle((x0, top, x1, eave + 20), 70, fill=roof)
    d.rounded_rectangle((x0 + 30, eave - 20, x1 - 30, bottom), 30, fill=wall)
    d.rounded_rectangle((x0 - 10, eave - 30, x1 + 10, eave + 40), 36, fill=dark)  # eaves
    inner = (x0 + 70, x1 - 70)
    floor = bottom - 10
    front = sketch.get("front", "door")
    glass, wood = (170, 210, 235), (120, 80, 60)
    if front == "garages":
        n = sketch.get("count", 2)
        gap = 40
        each = (inner[1] - inner[0] - gap * (n - 1)) / n
        for i in range(n):
            gx = inner[0] + i * (each + gap)
            d.rounded_rectangle((gx, eave + 90, gx + each, floor), 24, fill=tuple(sketch.get("door_colour", (200, 200, 205))))
    elif front == "open":
        d.rounded_rectangle((inner[0], eave + 90, inner[1], floor - 90), 24, fill=glass)
        d.rounded_rectangle((inner[0] - 10, floor - 100, inner[1] + 10, floor), 20, fill=dark)
    else:
        door_w = min(220, w // 5)
        cx = (x0 + x1) // 2
        d.rounded_rectangle((cx - door_w // 2, max(eave + 100, floor - 260), cx + door_w // 2, floor), 40, fill=wood)
        win_h = min(170, (floor - eave) - 160)
        for wx in (inner[0], inner[1] - 220):
            d.rounded_rectangle((wx, eave + 100, wx + 220, eave + 100 + win_h), 24, fill=glass)
    return img


def ramp_sketch(sketch: dict, size: int = 1536) -> Image.Image:
    """A boat jump ramp seen from straight above, pointing right: planks running across it,
    darker at the low end on the left (where it dips into the water) and paler towards the
    raised end on the right, which has a striped lip and casts a shadow; two arrows point the
    way the boats go. FLUX draws a ramp three-quarter however it is asked, and a three-quarter
    ramp cannot be turned to lie along a channel; Kontext keeps this view (DESIGN.md §20.2).
    `sketch`: width and length as fractions of `size`, and the number of boards."""
    img = Image.new("RGB", (size, size), (250, 250, 248))
    d = ImageDraw.Draw(img)
    length, width = round(sketch["length"] * size), round(sketch["width"] * size)
    x0, y0 = (size - length) // 2, (size - width) // 2
    x1, y1 = x0 + length, y0 + width
    d.rounded_rectangle((x0 + 40, y0 + 50, x1 + 70, y1 + 60), 40, fill=(222, 222, 220))  # the raised end's shadow
    boards = sketch.get("boards", 9)
    lip = round(length * 0.1)
    each = (length - lip) / boards
    for i in range(boards):
        shade = 0.72 + 0.28 * i / (boards - 1)
        colour = tuple(round(c * shade) for c in (232, 184, 120))
        bx = x0 + i * each
        d.rectangle((bx, y0, bx + each - 6, y1), fill=colour)
    stripe = round(width / 6)
    for k in range(6):
        d.rectangle((x1 - lip, y0 + k * stripe, x1, y0 + (k + 1) * stripe), fill=(250, 205, 40) if k % 2 == 0 else (225, 60, 50))
    for cx in (x0 + length * 0.3, x0 + length * 0.55):
        d.line([(cx, y0 + width * 0.28), (cx + width * 0.2, y0 + width * 0.5), (cx, y0 + width * 0.72)], fill=(250, 205, 40),
               width=round(width * 0.07), joint="curve")
    return img


def driver_sketch(sketch: dict, size: int = 1536) -> Image.Image:
    """A driver (DESIGN.md §22): head and shoulders of a toy figure seen from straight above,
    facing up, arms reaching forward (to a steering wheel when `wheel`). FLUX draws a figure
    from the front however it is asked; Kontext keeps this view. `sketch`: `hat` colour and
    `hat_kind` (helmet, cap, peaked, fire, space), an optional `decal` colour for a stripe down the
    helmet, `body` colour, `hair` colour and `hair_style` (tufts, pigtails, ponytail, curls,
    short), `wheel`, and `scale` (1.0 a child, about 1.2 a grown-up)."""
    img = Image.new("RGB", (size, size), (250, 250, 248))
    d = ImageDraw.Draw(img)
    u = size / 64 * sketch.get("scale", 1.0)  # one unit; the figure is about 30 units across
    c = size / 2
    col = lambda key, default=(0, 0, 0): tuple(sketch.get(key, default))  # noqa: E731
    dark = lambda rgb, f=0.7: tuple(round(v * f) for v in rgb)  # noqa: E731
    skin, body, hat, hair = (246, 205, 170), col("body"), col("hat"), col("hair", (120, 72, 40))
    style = sketch.get("hair_style", "short")
    space = sketch.get("hat_kind") == "space"  # the bubble keeps all the hair inside
    # Hair that shows behind the head (down is behind: the figure faces up).
    if space:
        pass
    elif style == "pigtails":
        for s in (-1, 1):
            d.ellipse((c + s * 7 * u - 3 * u, c + 4 * u, c + s * 7 * u + 3 * u, c + 11 * u), fill=hair)
    elif style == "ponytail":
        d.ellipse((c - 2.5 * u, c + 5 * u, c + 2.5 * u, c + 14 * u), fill=hair)
    # Shoulders across the figure, a little behind the head.
    d.ellipse((c - 12 * u, c - 3 * u, c + 12 * u, c + 9 * u), fill=body, outline=dark(body), width=round(u * 0.6))
    # Arms forward, hands on the wheel.
    for s in (-1, 1):
        d.line([(c + s * 9 * u, c + 1 * u), (c + s * 5.5 * u, c - 10 * u)], fill=body, width=round(4 * u))
        d.ellipse((c + s * 5.5 * u - 2 * u, c - 12 * u, c + s * 5.5 * u + 2 * u, c - 8 * u), fill=skin)
    if sketch.get("wheel"):
        d.arc((c - 8 * u, c - 14 * u, c + 8 * u, c - 6 * u), 180, 360, fill=(40, 40, 46), width=round(2 * u))
    # The head: hair round the edge, then the hat or helmet on top.
    if style in ("curls", "tufts", "short", "pigtails", "ponytail"):
        r = 7.8 if style == "curls" else 7.3
        d.ellipse((c - r * u, c - r * u + 0.8 * u, c + r * u, c + r * u + 0.8 * u), fill=hair)
    kind = sketch.get("hat_kind", "helmet")
    if kind == "helmet":
        d.ellipse((c - 7 * u, c - 7 * u, c + 7 * u, c + 7 * u), fill=hat, outline=dark(hat), width=round(u * 0.6))
        d.chord((c - 6 * u, c - 7 * u, c + 6 * u, c + 2 * u), 200, 340, fill=(36, 42, 66))  # visor, at the front
        if "decal" in sketch:
            d.rectangle((c - 1.2 * u, c - 3 * u, c + 1.2 * u, c + 7 * u), fill=col("decal"))
    elif kind == "space":  # a round glass bubble over the hair, on a coloured collar ring
        d.ellipse((c - 9.5 * u, c - 9.5 * u, c + 9.5 * u, c + 9.5 * u), fill=hat, outline=dark(hat), width=round(u * 0.6))
        d.ellipse((c - 8.3 * u, c - 8.3 * u, c + 8.3 * u, c + 8.3 * u), fill=(206, 232, 248))
        if style in ("curls", "tufts", "short", "pigtails", "ponytail"):
            d.ellipse((c - 5.6 * u, c - 4.8 * u, c + 5.6 * u, c + 6.4 * u), fill=hair)
        if style == "pigtails":
            for s in (-1, 1):
                d.ellipse((c + s * 5.5 * u - 1.8 * u, c + 3 * u, c + s * 5.5 * u + 1.8 * u, c + 7 * u), fill=hair)
        elif style == "ponytail":
            d.ellipse((c - 1.8 * u, c + 4.5 * u, c + 1.8 * u, c + 8 * u), fill=hair)
        d.arc((c - 7 * u, c - 7 * u, c + 7 * u, c + 7 * u), 200, 260, fill=(255, 255, 255), width=round(1.4 * u))
    elif kind == "fire":
        d.ellipse((c - 9 * u, c - 9.5 * u, c + 9 * u, c + 8 * u), fill=dark(hat, 0.9))  # brim
        d.ellipse((c - 6.5 * u, c - 6.5 * u, c + 6.5 * u, c + 6.5 * u), fill=hat, outline=dark(hat), width=round(u * 0.6))
        d.rectangle((c - 1 * u, c - 6.5 * u, c + 1 * u, c + 6.5 * u), fill=dark(hat, 0.85))  # comb
    else:  # cap or peaked cap: the crown, and the peak at the front
        d.chord((c - 6 * u, c - 12 * u, c + 6 * u, c - 2 * u), 180, 360, fill=dark(hat, 0.85))
        d.ellipse((c - 6.5 * u, c - 6.5 * u, c + 6.5 * u, c + 6.5 * u), fill=hat, outline=dark(hat), width=round(u * 0.6))
        if kind == "peaked" and "decal" in sketch:
            d.ellipse((c - 1.5 * u, c - 6 * u, c + 1.5 * u, c - 3 * u), fill=col("decal"))  # badge
        d.ellipse((c - 1 * u, c - 1 * u, c + 1 * u, c + 1 * u), fill=dark(hat, 0.8))  # the button on top
    if style == "tufts":
        for dx in (-3, 0, 3):
            d.polygon([(c + dx * u - 1.5 * u, c + 6 * u), (c + dx * u, c + 9 * u), (c + dx * u + 1.5 * u, c + 6 * u)], fill=hair)
    return img

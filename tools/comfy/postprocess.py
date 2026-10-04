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
              seed: int = 0) -> Image.Image:
    """A near-flat ground tile that tiles perfectly by construction.

    Matches the chosen style frame, whose ground is flat colour: `variation` adds soft
    blotches (fraction of brightness) built from sine waves with whole numbers of cycles
    per tile, so the left edge always meets the right. Speckles wrap around the edges
    for the same reason.
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
        shift = speckle_shift * rng.choice([-1, 1])
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

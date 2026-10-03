"""Compare two ways of building the road, at true game scale, on track 01's hairpin.

    python tools/layouts/road_compare.py

Left: what Godot's corner-matching terrain can draw on 128 px tiles (marching squares —
each tile's road edge is a straight cut between tile-edge midpoints). Right: the road
drawn straight from the spline. Writes docs/mockups/road_compare.png.
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "comfy"))
import postprocess as pp  # noqa: E402

DATA = json.loads((ROOT / "docs" / "mockups" / "track_01_points.json").read_text())
TILE = DATA["tile_px"]
HALF = DATA["road_tiles"] / 2 * TILE
LINE = [tuple(p) for p in DATA["racing_line_px"]]
VIEW = (29 * TILE, 1 * TILE, 44 * TILE, 13 * TILE)  # around the T2 hairpin
ART = ROOT / "art"


def dist_to_line(x: float, y: float) -> float:
    best = math.inf
    for (ax, ay), (bx, by) in zip(LINE, LINE[1:] + LINE[:1]):
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy or 1)))
        best = min(best, math.hypot(x - ax - t * dx, y - ay - t * dy))
    return best


def base_canvas() -> Image.Image:
    grass = Image.open(ART / "tiles" / "grass.png").convert("RGB")
    w, h = VIEW[2] - VIEW[0], VIEW[3] - VIEW[1]
    img = Image.new("RGB", (w, h))
    for y in range(0, h, TILE):
        for x in range(0, w, TILE):
            img.paste(grass, (x, y))
    return img


def textured(mask: Image.Image, tile_path: Path) -> Image.Image:
    tile = Image.open(tile_path).convert("RGB")
    fill = Image.new("RGB", mask.size)
    for y in range(0, mask.height, TILE):
        for x in range(0, mask.width, TILE):
            fill.paste(tile, (x, y))
    return fill


def terrain_version() -> Image.Image:
    img = base_canvas()
    mask = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(mask)
    x0, y0 = VIEW[0], VIEW[1]
    cols, rows = (VIEW[2] - x0) // TILE, (VIEW[3] - y0) // TILE
    on = [[dist_to_line(x0 + c * TILE, y0 + r * TILE) < HALF for c in range(cols + 1)] for r in range(rows + 1)]
    for r in range(rows):
        for c in range(cols):
            corners = [(c, r), (c + 1, r), (c + 1, r + 1), (c, r + 1)]
            states = [on[cy][cx] for cx, cy in corners]
            pts = []
            for i in range(4):
                (ax, ay), (bx, by) = corners[i], corners[(i + 1) % 4]
                if states[i]:
                    pts.append((ax * TILE, ay * TILE))
                if states[i] != states[(i + 1) % 4]:
                    pts.append(((ax + bx) / 2 * TILE, (ay + by) / 2 * TILE))
            if len(pts) >= 3:
                draw.polygon(pts, fill=255)
    img.paste(textured(mask, ART / "tiles" / "asphalt.png"), (0, 0), mask)
    return img


def spline_version() -> Image.Image:
    img = base_canvas()
    pts = [(x - VIEW[0], y - VIEW[1]) for x, y in LINE]
    pts = pts + pts[:2]
    kerb_mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(kerb_mask).line(pts, fill=255, width=int(2 * HALF + 2 * 30), joint="curve")
    stripes = Image.new("RGB", img.size, (231, 231, 171))
    sd = ImageDraw.Draw(stripes)
    # Red/cream blocks along the curve: alternate colour every ~48 px of arc length.
    acc = 0.0
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        seg = math.hypot(bx - ax, by - ay)
        if int(acc // 48) % 2 == 0:
            sd.line([(ax, ay), (bx, by)], fill=(196, 47, 47), width=int(2 * HALF + 2 * 30))
        acc += seg
    img.paste(stripes, (0, 0), kerb_mask)
    road_mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(road_mask).line(pts, fill=255, width=int(2 * HALF), joint="curve")
    img.paste(textured(road_mask, ART / "tiles" / "asphalt.png"), (0, 0), road_mask)
    return img


def main() -> None:
    left, right = terrain_version(), spline_version()
    cell = (left.width // 2, left.height // 2)
    sheet = pp.contact_sheet([(left, "A: tile terrain (corner matching, 128 px tiles)"),
                              (right, "B: road drawn from the spline, kerbs follow the curve")],
                             2, cell, "T2 HAIRPIN AT GAME SCALE (shown at 50%)")
    sheet.save(ROOT / "docs" / "mockups" / "road_compare.png")
    print("wrote docs/mockups/road_compare.png")


if __name__ == "__main__":
    main()

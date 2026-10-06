"""Finds the four tyres in every car body and writes them to game/configs/car_wheels.gd, for
the rolling tread (actors/car/rolling_tread.gd, docs/CAR_ANIMATION_PLAN.md).

    python tools/comfy/wheel_rects.py            # detect, apply overrides, write the script + sheet
    python tools/comfy/wheel_rects.py --check    # only report, write nothing

A body is 128 x 72 px, seen from above, facing +X, its tyres poking out above and below.
Tyre pixels are opaque, dark and grey; near the top and bottom edges we look for runs of
columns holding such pixels, bridge the small gaps a hubcap leaves, keep the two widest
runs per side (the left one is the rear wheel, the right one the front) and grow each
inwards while its rows are mostly tyre. The paints are Kontext recolours whose outlines drift
by a few pixels, so every image is measured on its own, and each paint is compared with its
car's original.

Rectangles the detection gets wrong are fixed by hand in asset_manifest.json under
`wheel_overrides`: a path relative to art/cars (wildcards allowed) maps to either
{wheel name: [x0, y0, x1, y1]} or "none" for a car whose tyres hardly show; such a car is
left out and simply drawn without rolling tread. Check the result on
docs/mockups/wheel_rects.png.
"""
import argparse
import json
from fnmatch import fnmatch
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import postprocess as pp

ROOT = Path(__file__).resolve().parents[2]
CARS = ROOT / "art" / "cars"
OUT = ROOT / "game" / "configs" / "car_wheels.gd"
SHEET = ROOT / "docs" / "mockups" / "wheel_rects.png"
MANIFEST = Path(__file__).parent / "asset_manifest.json"

# Tyre pixels: opaque, darker than DARK_LUMA, greyer than GREY_SPREAD (max - min channel).
DARK_LUMA = 75
GREY_SPREAD = 45
# The tyres are located in the first window of EDGE_ROWS[1] rows, starting EDGE_ROWS[0] rows
# from the top or bottom edge and moving inwards, that holds two of them (the Dragon's wings
# keep its tyres a few rows in from the edge).
EDGE_ROWS = (1, 7)
# A column belongs to a tyre with at least this many tyre pixels in those rows.
MIN_COLUMN = 3
# Gaps narrower than this (a hubcap) are bridged; runs narrower than MIN_WIDTH dropped.
MAX_GAP = 2
MIN_WIDTH = 8
# A rectangle grows inwards, at most BAND rows from the edge, while its row is this much tyre.
BAND = 20
MIN_ROW_COVER = 0.3
# A paint's tyre more than this many px from its original's is reported.
DRIFT_WARN = 4
WHEELS = ("rear_left", "front_left", "rear_right", "front_right")


def tyre_mask(img: Image.Image) -> np.ndarray:
    a = np.asarray(img.convert("RGBA")).astype(int)
    luma = a[..., :3] @ np.array([0.299, 0.587, 0.114])
    spread = a[..., :3].max(-1) - a[..., :3].min(-1)
    return (a[..., 3] > 128) & (luma < DARK_LUMA) & (spread < GREY_SPREAD)


def _runs(columns: np.ndarray) -> list[tuple[int, int]]:
    runs, start, gap = [], None, 0
    for x, filled in enumerate(list(columns) + [False] * (MAX_GAP + 1)):
        if filled:
            if start is None:
                start = x
            gap, end = 0, x + 1
        elif start is not None:
            gap += 1
            if gap > MAX_GAP:
                runs.append((start, end))
                start = None
    return [r for r in runs if r[1] - r[0] >= MIN_WIDTH]


def detect(img: Image.Image) -> dict[str, list[int]]:
    """Up to four rectangles [x0, y0, x1, y1] (x1, y1 exclusive), keyed by wheel name.

    The tyres are the outermost dark things above and below the body, so their columns are
    picked from the rows nearest the top and bottom edges; each rectangle then grows inwards
    for as long as its row is mostly tyre. The inner part of a tyre is under the body anyway.
    """
    mask = tyre_mask(img)
    h = mask.shape[0]
    found = {}
    for side, flip in (("left", False), ("right", True)):
        m = mask[::-1] if flip else mask
        runs = []
        for start in range(EDGE_ROWS[0], BAND - EDGE_ROWS[1], 2):
            edge = m[start:start + EDGE_ROWS[1]]
            runs = sorted(_runs(edge.sum(0) >= MIN_COLUMN), key=lambda r: r[1] - r[0], reverse=True)[:2]
            if len(runs) == 2:
                break
        for name, (x0, x1) in zip(("rear", "front"), sorted(runs)):
            cover = m[:BAND, x0:x1].mean(1)
            rows = np.where(cover >= MIN_ROW_COVER)[0]
            top = int(rows.min())
            bottom = top
            while bottom + 1 < BAND and cover[bottom + 1] >= MIN_ROW_COVER:
                bottom += 1
            y0, y1 = (h - bottom - 1, h - top) if flip else (top, bottom + 1)
            found[f"{name}_{side}"] = [int(x0), int(y0), int(x1), int(y1)]
    # Each axle's two tyres are one width; light and shadow often hide part of one of them.
    for axle in ("rear", "front"):
        pair = [found[f"{axle}_{side}"] for side in ("left", "right") if f"{axle}_{side}" in found]
        if len(pair) == 2:
            x0, x1 = min(r[0] for r in pair), max(r[2] for r in pair)
            for r in pair:
                r[0], r[2] = x0, x1
    return found


def bodies() -> list[Path]:
    return sorted(p for p in CARS.rglob("*.png"))


def original_of(path: Path) -> Path | None:
    if path.parent.name != "paint":
        return None
    original = CARS / "setups" / (path.stem.rsplit("_", 1)[0] + ".png")
    return original if original.exists() else None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="report only, write nothing")
    args = parser.parse_args()

    overrides = json.loads(MANIFEST.read_text(encoding="utf-8")).get("wheel_overrides", {})
    result, problems, cells = {}, [], []
    for path in bodies():
        key = path.relative_to(CARS).as_posix()
        img = Image.open(path)
        rects = detect(img)
        for pattern, fix in overrides.items():
            if pattern.startswith("_") or not fnmatch(key, pattern):
                continue
            if fix == "none":
                rects = {}
            else:
                rects.update({w: r for w, r in fix.items() if not w.startswith("_")})
        if not rects:
            cells.append((_marked(img, rects), key + " (none)"))
            continue
        missing = [w for w in WHEELS if w not in rects]
        if missing:
            problems.append(f"{key}: no {', '.join(missing)}")
        original = original_of(path)
        if original and original.relative_to(CARS).as_posix() in result:
            base = result[original.relative_to(CARS).as_posix()]
            for wheel, rect in rects.items():
                if wheel in base and max(abs(a - b) for a, b in zip(rect, base[wheel])) > DRIFT_WARN:
                    problems.append(f"{key}: {wheel} {rect} vs original {base[wheel]}")
        result[key] = {w: rects[w] for w in WHEELS if w in rects}
        cells.append((_marked(img, rects), key))

    for line in problems:
        print("check:", line)
    print(f"{len(result)} bodies, {len(problems)} to check")
    if args.check:
        return
    OUT.write_text(_gdscript(result), encoding="utf-8")
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    pp.contact_sheet(cells, 6, (384, 216), title="Wheel rectangles", bg=(200, 200, 200)).save(SHEET)
    print("wrote", OUT.relative_to(ROOT), "and", SHEET.relative_to(ROOT))


def _gdscript(result: dict) -> str:
    rows = []
    for key, rects in result.items():
        cells = ", ".join(f"Rect2i({x0}, {y0}, {x1 - x0}, {y1 - y0})" for x0, y0, x1, y1 in (rects[w] for w in WHEELS))
        rows.append(f'\t"{key}": [{cells}],')
    return GD_TEMPLATE.replace("@ROWS@", "\n".join(rows))


GD_TEMPLATE = '''class_name CarWheels
extends RefCounted
## Where the tyres are in every car body, for the rolling tread (actors/car/rolling_tread.gd).
## GENERATED by tools/comfy/wheel_rects.py from the PNGs in art/cars: re-run it after building
## new cars or paints instead of editing this file.
##
## Per body (path under art/cars): rear left, front left, rear right, front right, in texture
## pixels. Left is the top of the image, the car's left as it faces +X. A body that is not
## listed (the Bubble Car, whose tyres hardly show) just has no rolling tread.

const BODIES := {
@ROWS@
}


## The four tyre rectangles of `texture`, or an empty array.
static func of(texture: Texture2D) -> Array:
	if texture == null:
		return []
	return BODIES.get(texture.resource_path.trim_prefix("res://art/cars/"), [])
'''


def _marked(img: Image.Image, rects: dict) -> Image.Image:
    scale = 3
    big = img.convert("RGBA").resize((img.width * scale, img.height * scale), Image.NEAREST)
    draw = ImageDraw.Draw(big)
    for wheel, (x0, y0, x1, y1) in rects.items():
        colour = (255, 0, 90, 255) if wheel.startswith("front") else (0, 140, 255, 255)
        draw.rectangle((x0 * scale, y0 * scale, x1 * scale - 1, y1 * scale - 1), outline=colour, width=2)
    return big


if __name__ == "__main__":
    main()

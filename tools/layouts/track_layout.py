"""Track layout: one list of control points -> the design SVG and the in-game data.

    python tools/layouts/track_layout.py

Writes docs/mockups/track_01_layout.svg for review and docs/mockups/track_01_points.json,
which Phase 6 reads to build the TileMapLayer road and the Path2D racing line. Editing
the circuit means editing CONTROL_POINTS here, never the SVG or the scene by hand.
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "mockups"

TILE_PX = 128
MAP_TILES = (48, 28)
ROAD_TILES = 3.0
SVG_PER_TILE = 20
SAMPLES_PER_SEGMENT = 40
AVG_SPEED_PX_S = 700.0  # rough average including corners, for a lap-time estimate

# Centre line in tile units, in driving order. Cars leave the grid heading +X.
CONTROL_POINTS = [
    (11, 23), (21, 23), (31, 23),          # start/finish straight
    (38, 21.5), (41, 16), (41, 10),        # T1 sweeping turn, up the right side
    (39, 5.5), (34.5, 4.5), (31.5, 8),     # T2 hairpin
    (29, 12.5), (25, 13.5), (21.5, 10.5),  # T3/T4 S-bend
    (18, 6), (13, 4.5), (7.5, 5.5),        # back straight
    (5, 10), (5, 16), (6.5, 21),           # T5 down the left side, T6 onto the straight
]
FINISH_X = 17.0
CORNER_LABELS = {"T1": 4, "T2": 7, "T3": 9, "T4": 11, "T5": 15, "T6": 17}  # control-point index
SAND_TRAPS = [((42.5, 24.0), (3.8, 2.6)), ((37.0, 1.6), (4.2, 1.3))]   # centre, radii in tiles
TREES = [(16, 15), (19, 17), (13, 12), (24, 19), (33, 18), (35, 11), (9, 14),
         (2, 3), (45, 4), (46, 14), (2, 25), (27, 26)]
TYRE_STACKS = [(43.6, 12), (43.6, 16), (43.6, 20), (36, 1.8), (40, 2.2), (2.6, 12), (2.6, 16)]


def catmull_rom_closed(points, samples):
    out = []
    n = len(points)
    for i in range(n):
        p0, p1, p2, p3 = (points[(i + k) % n] for k in (-1, 0, 1, 2))
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * (2 * p1[a] + (-p0[a] + p2[a]) * t + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * t2
                       + (-p0[a] + 3 * p1[a] - 3 * p2[a] + p3[a]) * t3)
                for a in (0, 1)))
    return out


def cumulative_length(pts):
    lengths = [0.0]
    for a, b in zip(pts, pts[1:] + pts[:1]):
        lengths.append(lengths[-1] + math.dist(a, b))
    return lengths


def tangent(pts, i):
    a, b = pts[i - 1], pts[(i + 1) % len(pts)]
    d = (b[0] - a[0], b[1] - a[1])
    m = math.hypot(*d) or 1.0
    return d[0] / m, d[1] / m


def curvature(pts, i):
    t0, t1 = tangent(pts, i - 1), tangent(pts, (i + 1) % len(pts))
    return abs(math.atan2(t0[0] * t1[1] - t0[1] * t1[0], t0[0] * t1[0] + t0[1] * t1[1]))


def runs(flags):
    """Contiguous index runs where flags is true, treating the list as circular."""
    n = len(flags)
    if all(flags):
        return [list(range(n))]
    start = next(i for i in range(n) if not flags[i])
    result, current = [], []
    for k in range(1, n + 1):
        i = (start + k) % n
        if flags[i]:
            current.append(i)
        elif current:
            result.append(current)
            current = []
    if current:
        result.append(current)
    return result


def svg(v):
    return v * SVG_PER_TILE


def poly(pts, closed=False):
    d = "M " + " L ".join(f"{svg(x):.1f} {svg(y):.1f}" for x, y in pts)
    return d + (" Z" if closed else "")


def perpendicular_segment(centre, tan, half_width):
    nx, ny = -tan[1], tan[0]
    return ((centre[0] + nx * half_width, centre[1] + ny * half_width),
            (centre[0] - nx * half_width, centre[1] - ny * half_width))


def main():
    pts = catmull_rom_closed(CONTROL_POINTS, SAMPLES_PER_SEGMENT)
    lengths = cumulative_length(pts)
    lap_tiles = lengths[-1]
    half = ROAD_TILES / 2

    finish_i = min(range(len(pts)), key=lambda i: abs(pts[i][0] - FINISH_X) + abs(pts[i][1] - 23) * 4)
    finish = perpendicular_segment(pts[finish_i], tangent(pts, finish_i), half)
    mid_target = (lengths[finish_i] + lap_tiles / 2) % lap_tiles
    check_i = min(range(len(pts)), key=lambda i: abs(lengths[i] - mid_target))
    checkpoint = perpendicular_segment(pts[check_i], tangent(pts, check_i), half)

    # Staggered 2-wide grid behind the line, nose toward +X.
    grid = []
    for slot in range(4):
        gx = FINISH_X - 1.5 - slot * 1.5
        gy = 23 + (-0.7 if slot % 2 == 0 else 0.7)
        grid.append((gx, gy))

    kerb_runs = runs([curvature(pts, i) > 0.035 for i in range(len(pts))])

    W, H = svg(MAP_TILES[0]), svg(MAP_TILES[1])
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H + 120}" width="{W * 2}" height="{(H + 120) * 2}" '
         'font-family="Public Pixel, Consolas, monospace">',
         '<title>Track 01 layout</title>',
         f'<rect width="{W}" height="{H + 120}" fill="#14202E"/>',
         f'<rect width="{W}" height="{H}" fill="#5DBB4A"/>']
    # Faint tile grid so the TileMapLayer can be authored square by square.
    for x in range(MAP_TILES[0] + 1):
        s.append(f'<line x1="{svg(x)}" y1="0" x2="{svg(x)}" y2="{H}" stroke="#000" stroke-opacity="0.07" stroke-width="1"/>')
    for y in range(MAP_TILES[1] + 1):
        s.append(f'<line x1="0" y1="{svg(y)}" x2="{W}" y2="{svg(y)}" stroke="#000" stroke-opacity="0.07" stroke-width="1"/>')
    s.append(f'<rect x="4" y="4" width="{W - 8}" height="{H - 8}" fill="none" stroke="#2A2E35" stroke-width="8" stroke-dasharray="8 6"/>')
    for (cx, cy), (rx, ry) in SAND_TRAPS:
        s.append(f'<ellipse cx="{svg(cx)}" cy="{svg(cy)}" rx="{svg(rx)}" ry="{svg(ry)}" fill="#F2D27A" stroke="#C9A24A" stroke-width="3"/>')

    road = poly(pts, closed=True)
    s.append(f'<path d="{road}" fill="none" stroke="#1B1E23" stroke-width="{svg(ROAD_TILES) + 8}" stroke-linejoin="round"/>')
    for run in kerb_runs:
        sub = poly([pts[i] for i in run])
        s.append(f'<path d="{sub}" fill="none" stroke="#F5F5F5" stroke-width="{svg(ROAD_TILES) + 6}" stroke-linejoin="round"/>')
        s.append(f'<path d="{sub}" fill="none" stroke="#DC2828" stroke-width="{svg(ROAD_TILES) + 6}" stroke-dasharray="10 10" stroke-linejoin="round"/>')
    s.append(f'<path d="{road}" fill="none" stroke="#4A4F57" stroke-width="{svg(ROAD_TILES) - 6}" stroke-linejoin="round"/>')
    s.append(f'<path d="{road}" fill="none" stroke="#FFFFFF" stroke-opacity="0.75" stroke-width="2" stroke-dasharray="6 8"/>')

    # Direction arrows along the racing line.
    for frac in (0.08, 0.3, 0.55, 0.8):
        i = min(range(len(pts)), key=lambda k: abs(lengths[k] - frac * lap_tiles))
        tx, ty = tangent(pts, i)
        ang = math.degrees(math.atan2(ty, tx))
        x, y = svg(pts[i][0]), svg(pts[i][1])
        s.append(f'<path d="M -10 -8 L 8 0 L -10 8 Z" fill="#FFD23F" stroke="#0E141C" stroke-width="2" transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})"/>')

    # Start/finish chequer and the mid-lap checkpoint.
    (fx1, fy1), (fx2, fy2) = finish
    s.append(f'<line x1="{svg(fx1)}" y1="{svg(fy1)}" x2="{svg(fx2)}" y2="{svg(fy2)}" stroke="#FFFFFF" stroke-width="10"/>')
    s.append(f'<line x1="{svg(fx1)}" y1="{svg(fy1)}" x2="{svg(fx2)}" y2="{svg(fy2)}" stroke="#0E141C" stroke-width="10" stroke-dasharray="5 5"/>')
    (cx1, cy1), (cx2, cy2) = checkpoint
    s.append(f'<line x1="{svg(cx1)}" y1="{svg(cy1)}" x2="{svg(cx2)}" y2="{svg(cy2)}" stroke="#FF2BD6" stroke-width="5" stroke-dasharray="8 5"/>')
    s.append(f'<text x="{svg(cx1) - 8}" y="{svg(cy1) - 10}" text-anchor="end" font-size="11" fill="#FF2BD6">CHECKPOINT</text>')

    colours = ["#E63946", "#3A86FF", "#FFD23F", "#2EC46B"]
    for (gx, gy), c in zip(grid, colours):
        s.append(f'<rect x="{svg(gx) - 12.8}" y="{svg(gy) - 7.2}" width="25.6" height="14.4" rx="4.5" fill="{c}" stroke="#0E141C" stroke-width="2"/>')

    for tx, ty in TREES:
        s.append(f'<circle cx="{svg(tx)}" cy="{svg(ty)}" r="16" fill="#2E8B3A" stroke="#1C5A24" stroke-width="3"/>')
    for tx, ty in TYRE_STACKS:
        s.append(f'<circle cx="{svg(tx)}" cy="{svg(ty)}" r="8" fill="#22252A" stroke="#F5F5F5" stroke-width="2"/>')

    # Corner labels sit beside the road, on the side away from the infield, so they cover nothing.
    centroid = (sum(p[0] for p in CONTROL_POINTS) / len(CONTROL_POINTS), sum(p[1] for p in CONTROL_POINTS) / len(CONTROL_POINTS))
    for label, idx in CORNER_LABELS.items():
        i = idx * SAMPLES_PER_SEGMENT
        tx, ty = tangent(pts, i)
        nx, ny = -ty, tx
        px, py = pts[i]
        if (px + nx - centroid[0]) ** 2 + (py + ny - centroid[1]) ** 2 < (px - centroid[0]) ** 2 + (py - centroid[1]) ** 2:
            nx, ny = -nx, -ny
        x, y = px + nx * (half + 1.1), py + ny * (half + 1.1)
        s.append(f'<circle cx="{svg(x)}" cy="{svg(y)}" r="15" fill="#FFFFFF" stroke="#0E141C" stroke-width="3"/>')
        s.append(f'<text x="{svg(x)}" y="{svg(y) + 5}" text-anchor="middle" font-size="12" fill="#0E141C">{label}</text>')

    lap_px = lap_tiles * TILE_PX
    info = [
        f"TRACK 01 · {MAP_TILES[0]}x{MAP_TILES[1]} tiles ({MAP_TILES[0] * TILE_PX}x{MAP_TILES[1] * TILE_PX} px) · road {ROAD_TILES:g} tiles wide",
        f"Lap {lap_tiles:.0f} tiles = {lap_px:,.0f} px · about {lap_px / AVG_SPEED_PX_S:.0f} s per lap at {AVG_SPEED_PX_S:.0f} px/s average · 3 laps",
        "Dashed white = racing line (Path2D). Pink = mid-lap checkpoint, must be crossed for the lap to count.",
        "Kerbs auto-placed wherever the bend is tight. Map edge is a tyre wall. One faint square = one 128 px tile.",
    ]
    for k, line in enumerate(info):
        s.append(f'<text x="12" y="{H + 24 + k * 24}" font-size="9" fill="#E6EDF5">{line}</text>')
    s.append("</svg>")

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "track_01_layout.svg").write_text("\n".join(s), encoding="utf-8")

    to_px = lambda p: [round(p[0] * TILE_PX, 1), round(p[1] * TILE_PX, 1)]
    data = {
        "tile_px": TILE_PX,
        "map_tiles": MAP_TILES,
        "road_tiles": ROAD_TILES,
        "control_points_tiles": CONTROL_POINTS,
        "racing_line_px": [to_px(p) for p in pts[::4]],
        "lap_length_px": round(lap_px, 1),
        "finish_line_px": [to_px(p) for p in finish],
        "checkpoint_px": [to_px(p) for p in checkpoint],
        "grid_slots_px": [to_px(p) for p in grid],
        "sand_traps_tiles": SAND_TRAPS,
        "trees_tiles": TREES,
        "tyre_stacks_tiles": TYRE_STACKS,
    }
    (OUT / "track_01_points.json").write_text(json.dumps(data, indent=1), encoding="utf-8")
    print(f"lap {lap_tiles:.1f} tiles = {lap_px:,.0f} px (~{lap_px / AVG_SPEED_PX_S:.0f} s); "
          f"{len(kerb_runs)} kerb runs; finish idx {finish_i}, checkpoint idx {check_i}")


if __name__ == "__main__":
    main()

"""Track layouts: one spec per track -> the design SVG and the in-game data.

    python tools/layouts/track_layout.py [track_02 ...]      (default: every spec)

Reads tools/layouts/tracks/<id>.json and writes docs/mockups/<id>_layout.svg for review and
docs/mockups/<id>_points.json, which track/build/build_track.gd turns into the track scene.
Editing a circuit means editing its spec, never the SVG or the scene by hand.

A spec holds: map size and road width (tiles), the racing line's control points in driving
order, where the finish goes, optionally the grid slots (otherwise placed behind the line),
patches (ellipses of the theme's patch surface: sand traps, ice ponds, dunes), props by kind,
and, as fractions of a lap, ice on the road and boost pads. The theme (tools/layouts/
themes.json) colours the diagram the way the track will look.
"""
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
OUT = ROOT / "docs" / "mockups"
THEMES = json.loads((HERE / "themes.json").read_text(encoding="utf-8"))

TILE_PX = 128
SVG_PER_TILE = 20
SAMPLES_PER_SEGMENT = 40
AVG_SPEED_PX_S = 850.0  # the AI's average lap speed on Track 01, for a lap-time estimate
GRID_SPACING_TILES = 1.5
GRID_LANE_TILES = 0.7
PROP_STYLE = {  # kind -> (svg radius, fill, stroke)
    "tree": (16, "#2E8B3A", "#1C5A24"), "tyre_stack": (8, "#22252A", "#F5F5F5"),
    "palm_tree": (17, "#3FAE49", "#7A5230"), "parasol": (14, "#E63946", "#FFFFFF"),
    "beach_ball": (7, "#3A86FF", "#FFD23F"), "pine_tree": (16, "#1F6B45", "#FFFFFF"),
    "snowman": (10, "#FFFFFF", "#22252A"), "toy_house": (22, "#C0392B", "#5A1E16"),
    "traffic_cone": (6, "#FF7A1A", "#FFFFFF"),
}


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


def at_fraction(pts, lengths, fraction):
    lap = lengths[-1]
    target = (fraction % 1.0) * lap
    return min(range(len(pts)), key=lambda i: abs(lengths[i] - target))


def min_clearance(pts, lengths):
    """The closest the line comes to itself between points at least two road widths apart
    along it, in tiles: below road width + 1 the road would overlap or touch itself."""
    step = 8
    lap = lengths[-1]
    best = math.inf
    idx = list(range(0, len(pts), step))
    for a in idx:
        for b in idx:
            along = abs(lengths[a] - lengths[b])
            if min(along, lap - along) < 12:
                continue
            best = min(best, math.dist(pts[a], pts[b]))
    return best


def build(spec: dict) -> None:
    track_id = spec["id"]
    theme = THEMES[spec["theme"]]
    map_tiles = spec["map_tiles"]
    road = spec["road_tiles"]
    control = [tuple(p) for p in spec["control_points"]]
    pts = catmull_rom_closed(control, SAMPLES_PER_SEGMENT)
    lengths = cumulative_length(pts)
    lap_tiles = lengths[-1]
    half = road / 2

    near = spec["finish_near"]
    finish_i = min(range(len(pts)), key=lambda i: math.dist(pts[i], near))
    finish = perpendicular_segment(pts[finish_i], tangent(pts, finish_i), half)
    mid_target = (lengths[finish_i] + lap_tiles / 2) % lap_tiles
    check_i = min(range(len(pts)), key=lambda i: abs(lengths[i] - mid_target))
    checkpoint = perpendicular_segment(pts[check_i], tangent(pts, check_i), half)

    if "grid_tiles" in spec:
        grid = [tuple(p) for p in spec["grid_tiles"]]
    else:
        # Staggered two-wide grid behind the line, along the road, whatever its direction.
        grid = []
        for slot in range(4):
            behind = lengths[finish_i] - (1.5 + slot * GRID_SPACING_TILES)
            i = min(range(len(pts)), key=lambda k: abs(lengths[k] - behind % lap_tiles))
            tx, ty = tangent(pts, i)
            side = -GRID_LANE_TILES if slot % 2 == 0 else GRID_LANE_TILES
            grid.append((round(pts[i][0] - ty * side, 2), round(pts[i][1] + tx * side, 2)))

    kerb_runs = runs([curvature(pts, i) > 0.035 for i in range(len(pts))])
    clearance = min_clearance(pts, lengths)
    colours_svg = theme["svg"]

    W, H = svg(map_tiles[0]), svg(map_tiles[1])
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H + 120}" width="{W * 2}" height="{(H + 120) * 2}" '
         'font-family="Public Pixel, Consolas, monospace">',
         f'<title>{spec["name"]} layout</title>',
         f'<rect width="{W}" height="{H + 120}" fill="#14202E"/>',
         f'<rect width="{W}" height="{H}" fill="{colours_svg["ground"]}"/>']
    for x in range(map_tiles[0] + 1):
        s.append(f'<line x1="{svg(x)}" y1="0" x2="{svg(x)}" y2="{H}" stroke="#000" stroke-opacity="0.07" stroke-width="1"/>')
    for y in range(map_tiles[1] + 1):
        s.append(f'<line x1="0" y1="{svg(y)}" x2="{W}" y2="{svg(y)}" stroke="#000" stroke-opacity="0.07" stroke-width="1"/>')
    s.append(f'<rect x="4" y="4" width="{W - 8}" height="{H - 8}" fill="none" stroke="#2A2E35" stroke-width="8" stroke-dasharray="8 6"/>')
    for (cx, cy), (rx, ry) in spec.get("patches", []):
        s.append(f'<ellipse cx="{svg(cx)}" cy="{svg(cy)}" rx="{svg(rx)}" ry="{svg(ry)}" fill="{colours_svg["patch"]}" '
                 f'stroke="{colours_svg["patch_rim"]}" stroke-width="3"/>')

    road_path = poly(pts, closed=True)
    kerb = theme["kerb"]
    s.append(f'<path d="{road_path}" fill="none" stroke="#1B1E23" stroke-width="{svg(road) + 8}" stroke-linejoin="round"/>')
    for run in kerb_runs:
        sub = poly([pts[i] for i in run])
        s.append(f'<path d="{sub}" fill="none" stroke="rgb{tuple(kerb["cream"])}" stroke-width="{svg(road) + 6}" stroke-linejoin="round"/>')
        s.append(f'<path d="{sub}" fill="none" stroke="rgb{tuple(kerb["red"])}" stroke-width="{svg(road) + 6}" stroke-dasharray="10 10" stroke-linejoin="round"/>')
    s.append(f'<path d="{road_path}" fill="none" stroke="#4A4F57" stroke-width="{svg(road) - 6}" stroke-linejoin="round"/>')
    for span in spec.get("ice", []):
        a = at_fraction(pts, lengths, span["at"])
        n = int(span["length_tiles"] / (lap_tiles / len(pts)))
        sub = poly([pts[(a + k) % len(pts)] for k in range(n)])
        s.append(f'<path d="{sub}" fill="none" stroke="#C4E8F6" stroke-opacity="0.9" stroke-width="{svg(road) - 6}"/>')
    s.append(f'<path d="{road_path}" fill="none" stroke="#FFFFFF" stroke-opacity="0.75" stroke-width="2" stroke-dasharray="6 8"/>')
    for frac in spec.get("boost_pads", []):
        i = at_fraction(pts, lengths, frac)
        ang = math.degrees(math.atan2(*reversed(tangent(pts, i))))
        x, y = svg(pts[i][0]), svg(pts[i][1])
        s.append(f'<rect x="-12" y="-17" width="24" height="34" rx="5" fill="#FFC428" stroke="#0E141C" stroke-width="2" '
                 f'transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})"/>')
        s.append(f'<path d="M -6 -9 L 4 0 L -6 9" fill="none" stroke="#FFFFFF" stroke-width="3" transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})"/>')

    for frac in (0.08, 0.3, 0.55, 0.8):
        i = at_fraction(pts, lengths, frac)
        tx, ty = tangent(pts, i)
        ang = math.degrees(math.atan2(ty, tx))
        x, y = svg(pts[i][0]), svg(pts[i][1])
        s.append(f'<path d="M -10 -8 L 8 0 L -10 8 Z" fill="#FFD23F" stroke="#0E141C" stroke-width="2" transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})"/>')

    (fx1, fy1), (fx2, fy2) = finish
    s.append(f'<line x1="{svg(fx1)}" y1="{svg(fy1)}" x2="{svg(fx2)}" y2="{svg(fy2)}" stroke="#FFFFFF" stroke-width="10"/>')
    s.append(f'<line x1="{svg(fx1)}" y1="{svg(fy1)}" x2="{svg(fx2)}" y2="{svg(fy2)}" stroke="#0E141C" stroke-width="10" stroke-dasharray="5 5"/>')
    (cx1, cy1), (cx2, cy2) = checkpoint
    s.append(f'<line x1="{svg(cx1)}" y1="{svg(cy1)}" x2="{svg(cx2)}" y2="{svg(cy2)}" stroke="#FF2BD6" stroke-width="5" stroke-dasharray="8 5"/>')
    s.append(f'<text x="{svg(cx1) - 8}" y="{svg(cy1) - 10}" text-anchor="end" font-size="11" fill="#FF2BD6">CHECKPOINT</text>')

    for (gx, gy), c in zip(grid, ["#E63946", "#3A86FF", "#FFD23F", "#2EC46B"]):
        s.append(f'<rect x="{svg(gx) - 12.8}" y="{svg(gy) - 7.2}" width="25.6" height="14.4" rx="4.5" fill="{c}" stroke="#0E141C" stroke-width="2"/>')

    for kind, spots in spec.get("props", {}).items():
        r, fill, stroke = PROP_STYLE[kind]
        for tx, ty in spots:
            s.append(f'<circle cx="{svg(tx)}" cy="{svg(ty)}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="3"/>')

    centroid = (sum(p[0] for p in control) / len(control), sum(p[1] for p in control) / len(control))
    for label, idx in spec.get("corner_labels", {}).items():
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
        f"{spec['name'].upper()} · {theme['name']} · {map_tiles[0]}x{map_tiles[1]} tiles · road {road:g} tiles wide",
        f"Lap {lap_tiles:.0f} tiles = {lap_px:,.0f} px · about {lap_px / AVG_SPEED_PX_S:.0f} s per lap · closest the road comes to itself: {clearance:.1f} tiles",
        "Dashed white = racing line. Pink = mid-lap checkpoint. Pale blue on the road = ice. Orange = boost pad.",
        "Kerbs wherever the bend is tight. Map edge is a wall. One faint square = one 128 px tile.",
    ]
    for k, line in enumerate(info):
        s.append(f'<text x="12" y="{H + 24 + k * 24}" font-size="9" fill="#E6EDF5">{line}</text>')
    s.append("</svg>")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{track_id}_layout.svg").write_text("\n".join(s), encoding="utf-8")

    to_px = lambda p: [round(p[0] * TILE_PX, 1), round(p[1] * TILE_PX, 1)]  # noqa: E731
    data = {
        "id": track_id,
        "name": spec["name"],
        "theme": spec["theme"],
        "tile_px": TILE_PX,
        "map_tiles": map_tiles,
        "road_tiles": road,
        "control_points_tiles": control,
        "racing_line_px": [to_px(p) for p in pts[::4]],
        "lap_length_px": round(lap_px, 1),
        "finish_line_px": [to_px(p) for p in finish],
        "checkpoint_px": [to_px(p) for p in checkpoint],
        "grid_slots_px": [to_px(p) for p in grid],
        "patches_tiles": spec.get("patches", []),
        "props_tiles": spec.get("props", {}),
        "ice_spans": [[span["at"] % 1.0, span["length_tiles"] / lap_tiles] for span in spec.get("ice", [])],
        "boost_pads": spec.get("boost_pads", []),
    }
    (OUT / f"{track_id}_points.json").write_text(json.dumps(data, indent=1), encoding="utf-8")
    warn = "  ROAD OVERLAPS ITSELF" if clearance < road + 1.0 else ""
    print(f"{track_id}: lap {lap_tiles:.1f} tiles = {lap_px:,.0f} px (~{lap_px / AVG_SPEED_PX_S:.0f} s); "
          f"{len(kerb_runs)} kerb runs; clearance {clearance:.1f} tiles{warn}")


def main():
    ids = sys.argv[1:] or sorted(p.stem for p in (HERE / "tracks").glob("*.json"))
    for track_id in ids:
        build(json.loads((HERE / "tracks" / f"{track_id}.json").read_text(encoding="utf-8")))


if __name__ == "__main__":
    main()

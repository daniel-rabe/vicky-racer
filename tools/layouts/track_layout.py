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

Where the line crosses itself, one pass goes over a bridge: `bridges` names the upper pass
by the fraction of the lap where it crosses ({"upper_at": 0.2, "length_tiles": 18}). The
the script finds every crossing, centres a bridge span on the chosen pass, and warns about a
crossing with no bridge, or a gate, pad or ice patch on a bridge or right by a crossing.

A water theme makes a boat course (DESIGN.md §20) and a space theme a space course (§24):
branches, plus currents, ramps and logs on water, or drifting asteroids, comets and station
tunnels in space.
"""
import json
import math
import random
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
    "jungle_tree": (20, "#2F7D32", "#1B4D1E"), "jungle_flower": (11, "#FF5FA2", "#FFD23F"),
    "boulder": (10, "#8C8F96", "#5B5E66"), "lollipop": (10, "#FF4F8B", "#FFFFFF"),
    "donut": (11, "#F7A8C8", "#B07040"), "cupcake": (11, "#FFF3F8", "#E05A9A"),
    "gumdrop": (7, "#7BD88F", "#3E9E57"), "rocket": (15, "#F2F2F2", "#E63946"),
    "satellite_dish": (14, "#E6E8EE", "#6C7080"), "moon_rock": (10, "#9A94AE", "#625C78"),
    # Boat courses (DESIGN.md §20): props in the water are bumpers, on the banks scenery.
    "buoy": (6, "#FF7A1A", "#FFFFFF"), "rock": (12, "#8C8F96", "#5B5E66"),
    "reeds": (10, "#6E9E3A", "#3F6420"), "lily_pad": (8, "#58A848", "#2F6E2A"),
    "duck_house": (14, "#E8B04A", "#8A5A2A"), "shipwreck": (24, "#8A5A32", "#3E2614"),
    "treasure_chest": (9, "#C98A2E", "#FFD23F"), "lemon_slice": (12, "#FFE45C", "#FFFFFF"),
    "ice_cube": (10, "#E8F6FF", "#9CCBE6"), "cocktail_umbrella": (12, "#FF5FA2", "#FFFFFF"),
    # Space courses (DESIGN.md §24): asteroids in the dust are bumpers, the rest is scenery.
    "asteroid": (12, "#8C8494", "#4E4858"), "moon_base": (20, "#E6E8EE", "#6C7080"),
    "ringed_planet": (70, "#E8B86A", "#9A6A2A"), "little_moon": (26, "#C8C4D6", "#7A7490"),
    "space_station": (34, "#D8DCE6", "#5A6070"), "solar_panel": (12, "#3A6AC8", "#E6E8EE"),
    "lollipop_planet": (40, "#FF6FA8", "#FFFFFF"), "gumball": (11, "#7BD88F", "#FFFFFF"),
    "star_buoy": (6, "#FFD23F", "#FFFFFF"),
}


def water_course(spec, theme, pts, lengths, lap_tiles, kerb_runs, W, H, branches=()):
    """A boat course's channel (DESIGN.md §20): a shore band at the map edge, the channel of deep
    water with a pale foam edge, buoys along the tight bends, and the currents' chevrons."""
    colours = theme["svg"]
    road = spec["road_tiles"]
    half = road / 2
    band = svg(0.8)
    out = [f'<path d="M0 0 H{W} V{H} H0 Z M{band} {band} V{H - band} H{W - band} V{band} Z" fill="{colours["shore"]}" '
           'fill-rule="evenodd"/>',
           f'<rect x="{band}" y="{band}" width="{W - 2 * band}" height="{H - 2 * band}" fill="none" stroke="#FFFFFF" '
           'stroke-opacity="0.55" stroke-width="3"/>']
    road_path = poly(pts, closed=True)
    for br in branches:  # under the main channel, so the junctions read as the main water
        w = br["road_tiles"]
        out.append(f'<path d="{poly(br["line"])}" fill="none" stroke="#FFFFFF" stroke-opacity="0.35" stroke-width="{svg(w) + 10}" stroke-linejoin="round" stroke-linecap="round"/>')
        out.append(f'<path d="{poly(br["line"])}" fill="none" stroke="{colours["road"]}" stroke-width="{svg(w)}" stroke-linejoin="round" stroke-linecap="round"/>')
        if br["current"]:
            for k in range(SAMPLES_PER_SEGMENT // 2, len(br["line"]) - SAMPLES_PER_SEGMENT // 2, 12):
                tx, ty = tangent(br["line"], k)
                ang = math.degrees(math.atan2(ty, tx))
                x, y = br["line"][k]
                out.append(f'<path d="M -5 -7 L 4 0 L -5 7" fill="none" stroke="#FFFFFF" stroke-opacity="0.9" stroke-width="3" '
                           f'transform="translate({svg(x):.1f} {svg(y):.1f}) rotate({ang:.1f})"/>')
        out.append(f'<path d="{poly(br["line"])}" fill="none" stroke="#FFD23F" stroke-opacity="0.9" stroke-width="2" stroke-dasharray="3 7"/>')
        mid = br["line"][len(br["line"]) // 2]
        out.append(f'<text x="{svg(mid[0]):.1f}" y="{svg(mid[1]) - svg(w / 2) - 8:.1f}" text-anchor="middle" font-size="10" '
                   f'fill="#FFFFFF" stroke="#0E141C" stroke-width="3" paint-order="stroke">{br["name"].upper()}</text>')
    out.append(f'<path d="{road_path}" fill="none" stroke="#FFFFFF" stroke-opacity="0.35" stroke-width="{svg(road) + 10}" stroke-linejoin="round"/>')
    out.append(f'<path d="{road_path}" fill="none" stroke="{colours["road"]}" stroke-width="{svg(road)}" stroke-linejoin="round"/>')
    for span in spec.get("currents", []):
        a = at_fraction(pts, lengths, span["at"])
        n = int(span["length_tiles"] / (lap_tiles / len(pts)))
        sub = [pts[(a + k) % len(pts)] for k in range(n)]
        out.append(f'<path d="{poly(sub)}" fill="none" stroke="#FFFFFF" stroke-opacity="0.18" stroke-width="{svg(road) - 10}"/>')
        step = max(1, int(2.2 / (lap_tiles / len(pts))))
        for k in range(step // 2, n, step):
            i = (a + k) % len(pts)
            tx, ty = tangent(pts, i)
            ang = math.degrees(math.atan2(ty, tx))
            for off in (-0.28, 0.28):
                x, y = pts[i][0] - ty * off * road, pts[i][1] + tx * off * road
                out.append(f'<path d="M -5 -7 L 4 0 L -5 7" fill="none" stroke="#FFFFFF" stroke-opacity="0.9" stroke-width="3" '
                           f'transform="translate({svg(x):.1f} {svg(y):.1f}) rotate({ang:.1f})"/>')
    kerb = theme["kerb"]
    for run in kerb_runs:
        for j, i in enumerate(run[::6]):
            tx, ty = tangent(pts, i)
            for side in (1, -1):
                x, y = pts[i][0] - ty * side * (half + 0.15), pts[i][1] + tx * side * (half + 0.15)
                c = kerb["red"] if j % 2 == 0 else kerb["cream"]
                out.append(f'<circle cx="{svg(x):.1f}" cy="{svg(y):.1f}" r="4" fill="rgb{tuple(c)}" stroke="#0E141C" stroke-width="1.5"/>')
    return out


def water_overlay(spec, pts, lengths, half, branches=()):
    """What sits over a boat course's water: jump ramps, drifting logs and their paths, and
    the scenery bridges the boats pass under."""
    out = []
    ramps = [(pts, lengths, f) for f in spec.get("ramps", [])]
    for br in branches:
        bl = open_length(br["line"])
        ramps += [(br["line"], bl, f) for f in br["ramps"]]
    for line, lens, frac in ramps:
        i = at_fraction(line, lens, frac)
        tx, ty = tangent(line, i)
        ang = math.degrees(math.atan2(ty, tx))
        x, y = svg(line[i][0]), svg(line[i][1])
        out.append(f'<path d="M -14 -16 L 14 -10 L 14 10 L -14 16 Z" fill="#C98A4A" stroke="#4A2E14" stroke-width="2.5" '
                   f'transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})"/>')
        out.append(f'<path d="M -6 -7 L 5 0 L -6 7" fill="none" stroke="#FFD23F" stroke-width="3" '
                   f'transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})"/>')
    for (ax, ay), (bx, by) in spec.get("logs", []):
        out.append(f'<line x1="{svg(ax)}" y1="{svg(ay)}" x2="{svg(bx)}" y2="{svg(by)}" stroke="#7A5230" stroke-opacity="0.7" '
                   'stroke-width="2" stroke-dasharray="4 5"/>')
        mx, my = (ax + bx) / 2, (ay + by) / 2
        ang = math.degrees(math.atan2(by - ay, bx - ax)) + 90
        out.append(f'<rect x="-16" y="-5" width="32" height="10" rx="5" fill="#8A5A32" stroke="#3E2614" stroke-width="2" '
                   f'transform="translate({svg(mx):.1f} {svg(my):.1f}) rotate({ang:.1f})"/>')
    for frac in spec.get("scenery_bridges", []):
        i = at_fraction(pts, lengths, frac)
        tx, ty = tangent(pts, i)
        ang = math.degrees(math.atan2(ty, tx))
        x, y = svg(pts[i][0] + 0.3), svg(pts[i][1] + 0.5)
        length = svg(2 * half + 3)
        out.append(f'<rect x="-14" y="{-length / 2:.1f}" width="28" height="{length:.1f}" fill="#000" fill-opacity="0.25" '
                   f'transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})"/>')
        x, y = svg(pts[i][0]), svg(pts[i][1])
        out.append(f'<rect x="-14" y="{-length / 2:.1f}" width="28" height="{length:.1f}" fill="#B07A44" stroke="#4A2E14" '
                   f'stroke-width="2.5" transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})"/>')
        for k in range(1, 6):
            yy = -length / 2 + k * length / 6
            out.append(f'<line x1="-14" y1="{yy:.1f}" x2="14" y2="{yy:.1f}" stroke="#4A2E14" stroke-width="1.5" '
                       f'transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})"/>')
    return out


def starfield(W, H, seed):
    """Deterministic stars for a space course's diagram: a dot field, a few with a twinkle cross."""
    rng, out = random.Random(seed), []
    for _ in range(int(W * H / 2600)):
        x, y, r = rng.uniform(0, W), rng.uniform(0, H), rng.choice((0.8, 1.0, 1.2, 1.8))
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="#FFFFFF" fill-opacity="{rng.uniform(0.35, 0.9):.2f}"/>')
        if r > 1.5:
            out.append(f'<path d="M {x - 5:.0f} {y:.0f} H {x + 5:.0f} M {x:.0f} {y - 5:.0f} V {y + 5:.0f}" stroke="#FFFFFF" '
                       'stroke-opacity="0.6" stroke-width="1"/>')
    return out


def space_course(spec, theme, pts, kerb_runs, W, H, patches, branches=()):
    """A space course's lane (DESIGN.md §24): stars, a ring of big asteroids at the map edge
    (the wall), the theme's clouds, the glowing star lane, and beacon lights on the tight bends."""
    colours = theme["svg"]
    road = spec["road_tiles"]
    half = road / 2
    band = svg(0.9)
    out = starfield(W, H, len(spec["id"]) * 7 + sum(spec["map_tiles"]))
    out.append(f'<path d="M0 0 H{W} V{H} H0 Z M{band} {band} V{H - band} H{W - band} V{band} Z" fill="{colours["edge"]}" '
               'fill-rule="evenodd"/>')
    rng = random.Random(len(spec["id"]))
    for k in range(int(2 * (W + H) / 22)):  # lumpy rocks along the edge band
        t = k * 22
        if t < W:
            x, y = t, band / 2
        elif t < W + H:
            x, y = W - band / 2, t - W
        elif t < 2 * W + H:
            x, y = W - (t - W - H), H - band / 2
        else:
            x, y = band / 2, H - (t - 2 * W - H)
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{rng.uniform(8, 15):.0f}" fill="{colours["edge"]}" '
                   'stroke="#2A2630" stroke-width="2"/>')
    out.extend(patches)  # clouds over the stars, under the lane
    road_path = poly(pts, closed=True)
    for br in branches:
        w = br["road_tiles"]
        out.append(f'<path d="{poly(br["line"])}" fill="none" stroke="{colours["glow"]}" stroke-opacity="0.3" stroke-width="{svg(w) + 14}" stroke-linejoin="round" stroke-linecap="round"/>')
        out.append(f'<path d="{poly(br["line"])}" fill="none" stroke="{colours["road"]}" stroke-width="{svg(w)}" stroke-linejoin="round" stroke-linecap="round"/>')
        out.append(f'<path d="{poly(br["line"])}" fill="none" stroke="#FFD23F" stroke-opacity="0.9" stroke-width="2" stroke-dasharray="3 7"/>')
        mid = br["line"][len(br["line"]) // 2]
        out.append(f'<text x="{svg(mid[0]):.1f}" y="{svg(mid[1]) - svg(w / 2) - 8:.1f}" text-anchor="middle" font-size="10" '
                   f'fill="#FFFFFF" stroke="#0E141C" stroke-width="3" paint-order="stroke">{br["name"].upper()}</text>')
    out.append(f'<path d="{road_path}" fill="none" stroke="{colours["glow"]}" stroke-opacity="0.3" stroke-width="{svg(road) + 14}" stroke-linejoin="round"/>')
    out.append(f'<path d="{road_path}" fill="none" stroke="{colours["road"]}" stroke-width="{svg(road)}" stroke-linejoin="round"/>')
    out.append(f'<path d="{road_path}" fill="none" stroke="{colours["glow"]}" stroke-opacity="0.4" stroke-width="{svg(road) - 22}" stroke-linejoin="round"/>')
    kerb = theme["kerb"]
    for run in kerb_runs:
        for j, i in enumerate(run[::6]):
            tx, ty = tangent(pts, i)
            for side in (1, -1):
                x, y = pts[i][0] - ty * side * (half + 0.15), pts[i][1] + tx * side * (half + 0.15)
                c = kerb["red"] if j % 2 == 0 else kerb["cream"]
                out.append(f'<circle cx="{svg(x):.1f}" cy="{svg(y):.1f}" r="7" fill="rgb{tuple(c)}" fill-opacity="0.35"/>')
                out.append(f'<circle cx="{svg(x):.1f}" cy="{svg(y):.1f}" r="3.5" fill="rgb{tuple(c)}" stroke="#0E141C" stroke-width="1"/>')
    return out


def space_overlay(spec, pts, lengths, half):
    """What flies over a space course: drifting asteroids and their paths, comets with the
    streak they cross the lane on, and the station tunnels the ships pass under."""
    out = []
    for (ax, ay), (bx, by) in spec.get("asteroids", []):
        out.append(f'<line x1="{svg(ax)}" y1="{svg(ay)}" x2="{svg(bx)}" y2="{svg(by)}" stroke="#C8C0D6" stroke-opacity="0.8" '
                   'stroke-width="2" stroke-dasharray="4 5"/>')
        mx, my = svg((ax + bx) / 2), svg((ay + by) / 2)
        out.append(f'<path d="M -14 -4 L -8 -13 L 5 -14 L 14 -5 L 12 9 L 0 14 L -11 10 Z" fill="#8C8494" stroke="#3E3848" '
                   f'stroke-width="2.5" transform="translate({mx:.1f} {my:.1f})"/>')
        out.append(f'<circle cx="{mx - 3:.1f}" cy="{my - 2:.1f}" r="3.5" fill="#6A6274"/>')
    for c in spec.get("comets", []):
        (ax, ay), (bx, by) = c["path"]
        ang = math.degrees(math.atan2(by - ay, bx - ax))
        out.append(f'<line x1="{svg(ax)}" y1="{svg(ay)}" x2="{svg(bx)}" y2="{svg(by)}" stroke="#FFE45C" stroke-opacity="0.85" '
                   'stroke-width="3" stroke-dasharray="10 6"/>')
        hx, hy = svg(ax + (bx - ax) * 0.25), svg(ay + (by - ay) * 0.25)
        out.append(f'<path d="M 0 0 L -60 -9 L -60 9 Z" fill="#FFE45C" fill-opacity="0.55" transform="translate({hx:.1f} {hy:.1f}) rotate({ang:.1f})"/>')
        out.append(f'<circle cx="{hx:.1f}" cy="{hy:.1f}" r="9" fill="#FFFFFF" stroke="#FFB020" stroke-width="3"/>')
        out.append(f'<text x="{hx:.1f}" y="{hy - 16:.1f}" text-anchor="middle" font-size="9" fill="#FFE45C" stroke="#0E141C" '
                   f'stroke-width="3" paint-order="stroke">COMET every {c.get("every", 8):g} s</text>')
    for t in spec.get("tunnels", []):
        i = at_fraction(pts, lengths, t["at"])
        n = int(t.get("length_tiles", 8) / (lengths[-1] / len(pts)))
        deck = [pts[(i + k) % len(pts)] for k in range(-n // 2, n // 2)]
        out.append(f'<path d="{poly([(x + 0.4, y + 0.7) for x, y in deck])}" fill="none" stroke="#000" stroke-opacity="0.3" stroke-width="{svg(2 * half + 1.5)}"/>')
        out.append(f'<path d="{poly(deck)}" fill="none" stroke="#3E4452" stroke-width="{svg(2 * half + 1.5)}"/>')
        out.append(f'<path d="{poly(deck)}" fill="none" stroke="#D8DCE6" stroke-width="{svg(2 * half + 0.9)}"/>')
        out.append(f'<path d="{poly(deck)}" fill="none" stroke="#9AA2B4" stroke-width="{svg(2 * half + 0.9)}" stroke-dasharray="3 22"/>')
        mx, my = deck[len(deck) // 2]
        out.append(f'<text x="{svg(mx):.1f}" y="{svg(my) + 4:.1f}" text-anchor="middle" font-size="10" fill="#3E4452">TUNNEL</text>')
    return out


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


def open_length(pts):
    """Cumulative length along an open line (a branch), one entry per point."""
    lengths = [0.0]
    for a, b in zip(pts, pts[1:]):
        lengths.append(lengths[-1] + math.dist(a, b))
    return lengths


def at_fraction(pts, lengths, fraction):
    lap = lengths[-1]
    target = (fraction % 1.0) * lap
    return min(range(len(pts)), key=lambda i: abs(lengths[i] - target))


CROSSING_KEEP_OUT = 12.0  # tiles around a crossing that the clearance check ignores


def min_clearance(pts, lengths, crossings=()):
    """The closest the line comes to itself between points at least two road widths apart
    along it, in tiles: below road width + 1 the road would overlap or touch itself.
    Bridged crossings are meant to come close, so the area round each is left out."""
    step = 8
    lap = lengths[-1]
    best = math.inf
    idx = [i for i in range(0, len(pts), step)
           if all(math.dist(pts[i], c["point"]) > CROSSING_KEEP_OUT for c in crossings)]
    for a in idx:
        for b in idx:
            along = abs(lengths[a] - lengths[b])
            if min(along, lap - along) < 12:
                continue
            best = min(best, math.dist(pts[a], pts[b]))
    return best


def find_crossings(pts, lengths):
    """Where the closed line crosses itself: the point, both passes (as lap fractions) and
    the angle between them in degrees."""
    n, lap = len(pts), lengths[-1]
    found = []
    for i in range(n):
        a1, a2 = pts[i], pts[(i + 1) % n]
        for j in range(i + 2, n):
            if (j + 1) % n == i:
                continue
            b1, b2 = pts[j], pts[(j + 1) % n]
            d = (a2[0] - a1[0]) * (b2[1] - b1[1]) - (a2[1] - a1[1]) * (b2[0] - b1[0])
            if abs(d) < 1e-12:
                continue
            t = ((b1[0] - a1[0]) * (b2[1] - b1[1]) - (b1[1] - a1[1]) * (b2[0] - b1[0])) / d
            u = ((b1[0] - a1[0]) * (a2[1] - a1[1]) - (b1[1] - a1[1]) * (a2[0] - a1[0])) / d
            if 0 <= t <= 1 and 0 <= u <= 1:
                point = (a1[0] + t * (a2[0] - a1[0]), a1[1] + t * (a2[1] - a1[1]))
                ta, tb = tangent(pts, i), tangent(pts, j)
                angle = math.degrees(math.acos(max(-1.0, min(1.0, abs(ta[0] * tb[0] + ta[1] * tb[1])))))
                if any(math.dist(point, f["point"]) < 1.0 for f in found):
                    continue  # the same crossing, found again on a neighbouring segment
                found.append({"point": point, "passes": [lengths[i] / lap, lengths[j] / lap], "angle": angle})
    return found


def catmull_rom_open(points, samples):
    """Through points[1:-1]; the first and last points only shape the ends."""
    out = []
    for i in range(1, len(points) - 2):
        p0, p1, p2, p3 = points[i - 1], points[i], points[i + 1], points[i + 2]
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * (2 * p1[a] + (-p0[a] + p2[a]) * t + (2 * p0[a] - 5 * p1[a] + 4 * p2[a] - p3[a]) * t2
                       + (-p0[a] + 3 * p1[a] - 3 * p2[a] + p3[a]) * t3)
                for a in range(2)))
    out.append(tuple(points[-2]))
    return out


def build_branches(spec, pts, lengths, lap_tiles):
    """Alternative paths (DESIGN.md §20.3): each leaves the racing line near `from_near`, runs
    through its own control points and rejoins near `to_near`. Progress on a branch maps onto
    the stretch of lap it bypasses, so laps, positions and gates need nothing new."""
    n = len(pts)
    out = []
    for b in spec.get("branches", []):
        a = min(range(n), key=lambda i: math.dist(pts[i], b["from_near"]))
        z = min(range(n), key=lambda i: math.dist(pts[i], b["to_near"]))
        lead = SAMPLES_PER_SEGMENT // 4
        ctrl = [pts[(a - lead) % n], pts[a]] + [tuple(p) for p in b["control_points"]] + [pts[z], pts[(z + lead) % n]]
        line = catmull_rom_open(ctrl, SAMPLES_PER_SEGMENT)
        length = open_length(line)[-1]
        bypassed = (lengths[z] - lengths[a]) % lap_tiles
        # Clear of the racing line everywhere but where it leaves and rejoins.
        width = b.get("road_tiles", spec["road_tiles"] * 0.7)
        need = spec["road_tiles"] / 2 + width / 2 + 1.0
        inner = [p for p in line if math.dist(p, pts[a]) > 2 * need and math.dist(p, pts[z]) > 2 * need]
        clearance = min((math.dist(p, q) for p in inner[::3] for q in pts[::3]), default=99)
        out.append({"name": b.get("name", ""), "from_i": a, "to_i": z, "from": lengths[a] / lap_tiles,
                    "to": lengths[z] / lap_tiles, "line": line, "length": length, "bypassed": bypassed,
                    "road_tiles": width, "ramps": b.get("ramps", []), "current": b.get("current", 0.0),
                    "clearance": clearance, "ok": clearance >= need})
        if clearance < need:
            print(f"  WARNING {spec['id']}: branch '{b.get('name')}' comes within {clearance:.1f} tiles of the racing line")
    return out


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
    crossings = find_crossings(pts, lengths)
    # Each bridge: a span of the lap centred on the pass it names, which goes over the other.
    bridges = []
    for b in spec.get("bridges", []):
        best = min(((abs(f - b["upper_at"]), f, c) for c in crossings for f in c["passes"]), default=None,
                   key=lambda x: x[0])
        if best is None:
            print(f"  WARNING {track_id}: a bridge is asked for but the line never crosses itself")
            continue
        span = b.get("length_tiles", 18.0) / lap_tiles
        bridges.append({"start": (best[1] - span / 2) % 1.0, "length": span, "crossing": best[2]})
    for c in crossings:
        if not any(b["crossing"] is c for b in bridges):
            print(f"  WARNING {track_id}: the road crosses itself at {tuple(round(v, 1) for v in c['point'])} with no bridge")
    near_crossing = lambda i: any(math.dist(pts[i], c["point"]) < 6.0 for c in crossings)  # noqa: E731

    def on_bridge(fraction):
        return any((fraction - b["start"]) % 1.0 <= b["length"] for b in bridges)

    branches = build_branches(spec, pts, lengths, lap_tiles)

    def bypassed(fraction):  # a gate here would be skipped by a boat on a branch
        return any((fraction - br["from"]) % 1.0 <= (br["to"] - br["from"]) % 1.0 for br in branches)

    # The checkpoint goes half a lap on, moved forward off any bridge, crossing or branch.
    mid_target = (lengths[finish_i] + lap_tiles / 2) % lap_tiles
    check_i = min(range(len(pts)), key=lambda i: abs(lengths[i] - mid_target))
    while near_crossing(check_i) or on_bridge(lengths[check_i] / lap_tiles) or bypassed(lengths[check_i] / lap_tiles):
        check_i = (check_i + 4) % len(pts)
    checkpoint = perpendicular_segment(pts[check_i], tangent(pts, check_i), half)
    if near_crossing(finish_i) or on_bridge(lengths[finish_i] / lap_tiles):
        print(f"  WARNING {track_id}: the finish line is on a bridge or by a crossing")
    if bypassed(lengths[finish_i] / lap_tiles):
        print(f"  WARNING {track_id}: the finish line is on a stretch a branch bypasses")
    for what, fractions in (("boost pad", spec.get("boost_pads", [])),
                            ("ice patch", [x["at"] for x in spec.get("ice", [])])):
        for f in fractions:
            i = at_fraction(pts, lengths, f)
            if near_crossing(i) or on_bridge(f):
                print(f"  WARNING {track_id}: a {what} at {f} is on a bridge or by a crossing")

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
    clearance = min_clearance(pts, lengths, crossings)
    colours_svg = theme["svg"]

    W, H = svg(map_tiles[0]), svg(map_tiles[1])
    footer = 120 + 24 * len(branches)
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H + footer}" width="{W * 2}" height="{(H + footer) * 2}" '
         'font-family="Public Pixel, Consolas, monospace">',
         f'<title>{spec["name"]} layout</title>',
         f'<rect width="{W}" height="{H + footer}" fill="#14202E"/>',
         f'<rect width="{W}" height="{H}" fill="{colours_svg["ground"]}"/>']
    for x in range(map_tiles[0] + 1):
        s.append(f'<line x1="{svg(x)}" y1="0" x2="{svg(x)}" y2="{H}" stroke="#000" stroke-opacity="0.07" stroke-width="1"/>')
    for y in range(map_tiles[1] + 1):
        s.append(f'<line x1="0" y1="{svg(y)}" x2="{W}" y2="{svg(y)}" stroke="#000" stroke-opacity="0.07" stroke-width="1"/>')
    s.append(f'<rect x="4" y="4" width="{W - 8}" height="{H - 8}" fill="none" stroke="#2A2E35" stroke-width="8" stroke-dasharray="8 6"/>')
    patches = [f'<ellipse cx="{svg(cx)}" cy="{svg(cy)}" rx="{svg(rx)}" ry="{svg(ry)}" fill="{colours_svg["patch"]}" '
               f'stroke="{colours_svg["patch_rim"]}" stroke-width="3"/>' for (cx, cy), (rx, ry) in spec.get("patches", [])]
    space = theme.get("space", False)
    if not space:  # a space course draws them over its stars
        s.extend(patches)

    road_path = poly(pts, closed=True)
    kerb = theme["kerb"]
    water = theme.get("water", False)
    if water:
        s.extend(water_course(spec, theme, pts, lengths, lap_tiles, kerb_runs, W, H, branches))
    elif space:
        s.extend(space_course(spec, theme, pts, kerb_runs, W, H, patches, branches))
    else:
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
    for b in bridges:
        a = at_fraction(pts, lengths, b["start"])
        n = int(b["length"] * len(pts))
        deck = [pts[(a + k) % len(pts)] for k in range(n)]
        middle = deck[n // 6: n - n // 6]
        shadow = poly([(x + 0.5, y + 0.8) for x, y in middle])
        s.append(f'<path d="{shadow}" fill="none" stroke="#000" stroke-opacity="0.3" stroke-width="{svg(road) + 10}"/>')
        s.append(f'<path d="{poly(deck)}" fill="none" stroke="#1B1E23" stroke-width="{svg(road) + 8}"/>')
        s.append(f'<path d="{poly(deck)}" fill="none" stroke="#5A6068" stroke-width="{svg(road) - 6}"/>')
        for side in (1, -1):
            rail = []
            for k, (x, y) in enumerate(middle):
                tx, ty = tangent(pts, (a + n // 6 + k) % len(pts))
                rail.append((x - ty * side * (half + 0.15), y + tx * side * (half + 0.15)))
            s.append(f'<path d="{poly(rail)}" fill="none" stroke="#F2F2F2" stroke-width="5"/>')
        s.append(f'<path d="{poly(deck)}" fill="none" stroke="#FFFFFF" stroke-opacity="0.75" stroke-width="2" stroke-dasharray="6 8"/>')
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
    if water:
        s.extend(water_overlay(spec, pts, lengths, half, branches))
    elif space:
        s.extend(space_overlay(spec, pts, lengths, half))

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
        f"Lap {lap_tiles:.0f} tiles = {lap_px:,.0f} px · about {lap_px / AVG_SPEED_PX_S:.0f} s per lap · closest the road comes to itself: {clearance:.1f} tiles"
        + "".join(f" · bridge crossing at {c['angle']:.0f}°" for c in crossings),
        "Dashed white = racing line. Pink = mid-lap checkpoint. Pale blue on the road = ice. Orange = boost pad.",
        "Kerbs wherever the bend is tight. Map edge is a wall. One faint square = one 128 px tile.",
    ]
    if water:
        info[2:] = [
            "Dark channel = deep water (full speed). Pale water = shallows (slower). Patches = banks (slowest; hovercraft skim them).",
            "Buoys mark the tight bends. White chevrons = current. Brown wedge = jump ramp. Orange = fizz/boost. Shore = wall.",
        ] + [f"Gold dashes = {br['name']}: {br['length']:.0f} tiles, {br['road_tiles']:g} wide, instead of {br['bypassed']:.0f} tiles of main channel"
             for br in branches]
    elif space:
        info[2:] = [
            "Glowing path = star lane (full speed). Starry space = dust (slower). Clouds / moon = slowest. Pale stretch = slippery ice.",
            "Beacons light the tight bends. Grey rocks on dashes = drifting asteroids. Yellow streak = comet path. Orange = boost. Rock ring = wall.",
        ] + [f"Gold dashes = {br['name']}: {br['length']:.0f} tiles, {br['road_tiles']:g} wide, instead of {br['bypassed']:.0f} tiles of main lane"
             for br in branches]
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
        "bridge_spans": [[b["start"], b["length"]] for b in bridges],
        "crossings_px": [to_px(c["point"]) for c in crossings],
    }
    if space:
        data |= {
            "space": True,
            "asteroids_px": [[to_px(a), to_px(b)] for a, b in spec.get("asteroids", [])],
            "comets": [{"path_px": [to_px(c["path"][0]), to_px(c["path"][1])], "every": c.get("every", 8.0),
                        "offset": c.get("offset", 0.0)} for c in spec.get("comets", [])],
            "tunnels": [[t["at"] % 1.0, t.get("length_tiles", 8) / lap_tiles] for t in spec.get("tunnels", [])],
        }
    if water or space:  # both have branches; currents, ramps and logs are only ever in water specs
        data |= {
            "water": water,
            "current_spans": [[c["at"] % 1.0, c["length_tiles"] / lap_tiles, c.get("strength", 1.0)]
                              for c in spec.get("currents", [])],
            "ramps": spec.get("ramps", []),
            "logs_px": [[to_px(a), to_px(b)] for a, b in spec.get("logs", [])],
            "scenery_bridges": spec.get("scenery_bridges", []),
            "branches": [{"name": br["name"], "from": round(br["from"], 4), "to": round(br["to"], 4),
                          "road_tiles": br["road_tiles"], "line_px": [to_px(p) for p in br["line"][::4]] + [to_px(br["line"][-1])],
                          "length_px": round(br["length"] * TILE_PX, 1), "ramps": br["ramps"], "current": br["current"]}
                         for br in branches],
        }
    (OUT / f"{track_id}_points.json").write_text(json.dumps(data, indent=1), encoding="utf-8")
    warn = "  ROAD OVERLAPS ITSELF" if clearance < road + 1.0 else ""
    print(f"{track_id}: lap {lap_tiles:.1f} tiles = {lap_px:,.0f} px (~{lap_px / AVG_SPEED_PX_S:.0f} s); "
          f"{len(kerb_runs)} kerb runs; clearance {clearance:.1f} tiles{warn}; "
          f"{len(crossings)} crossing(s){''.join(f' at {c["angle"]:.0f} deg' for c in crossings)}, {len(bridges)} bridge(s)")


def main():
    ids = sys.argv[1:] or sorted(p.stem for p in (HERE / "tracks").glob("*.json"))
    for track_id in ids:
        build(json.loads((HERE / "tracks" / f"{track_id}.json").read_text(encoding="utf-8")))


if __name__ == "__main__":
    main()

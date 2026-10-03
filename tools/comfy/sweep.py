"""Phase 2 bake-off: run a fixed probe set through competing generation configs.

    python tools/comfy/sweep.py --configs flux_base,redux_med,sd35_neg
    python tools/comfy/sweep.py --list

Every image lands in docs/mockups/bakeoff/<config>/, with prompt, seed, seconds and a
flatness score in docs/mockups/bakeoff/results.json. A comparison sheet (rows = configs,
columns = probes) is rebuilt after each config so progress is visible while it runs.
"""
import argparse
import io
import json
import time
from dataclasses import asdict
from pathlib import Path

import numpy as np
from PIL import Image

import postprocess as pp
import workflows as wf
from comfy_client import ComfyClient

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "mockups" / "bakeoff"
RESULTS = OUT / "results.json"
ANCHOR = ROOT / "docs" / "mockups" / "style_anchor.png"
BOARD = ROOT / "docs" / "mockups" / "style_board.png"
CAR_INIT = ROOT / "docs" / "mockups" / "raw" / "car_sports.png"  # the user's pick, white background
SEED = 11

STYLE = "soft flat children's picture book illustration, rounded friendly shapes, warm bright flat colours, no outlines"
SPRITE = "seen from directly above, top-down plan view, 2D video game sprite, {style}, centred on a plain white background"
TILE = ("uniform seamless ground texture filling the whole image, viewed from directly above, {style}, "
        "no objects, no borders, no vignette")
NEGATIVE = ("3d render, photo, realistic, gradient shading, glossy, shine, reflections, drop shadow, perspective, "
            "isometric, side view, text, watermark, border, frame, vignette")

# (id, kind, subject) — kind decides the suffix and whether the subject is cut out.
PROBES = [
    ("car", "sprite", "a red classic sports car with white racing stripes, pointing straight up, perfectly symmetrical"),
    ("tyres", "sprite", "a stack of three black racing tyres"),
    ("hay", "sprite", "a rectangular golden hay bale"),
    ("tree", "sprite", "a round bushy green tree"),
    ("grass", "tile", "short green lawn"),
    ("asphalt", "tile", "dark grey asphalt road surface"),
]


STYLE_R2 = ("soft children's picture book illustration, smooth matte clay toy look, rounded chunky friendly "
            "shapes, warm bright colours, gentle soft shading, no outlines")
SPRITE_R2 = "2D top-down video game sprite, {style}, centred on a plain white background"
PROBES_R2 = [
    ("car", "sprite", "a red classic sports car with white racing stripes seen from directly above, pointing straight up, perfectly symmetrical"),
    ("ring", "sprite", "a fat round ring of golden straw seen from above, a soft doughnut shape with a hole in the middle"),
    ("bale", "sprite", "a soft square golden hay bale seen from above at a slight angle, rounded edges"),
    ("tree", "sprite", "the round puffy crown of a tree seen from directly above, made of soft bubbly green clumps, no trunk visible"),
]
# Round 3: three ways of asking for a tree from above, and the chosen sports car restyled
# toward the board's clay-toy finish at two strengths. "restyle:<denoise>" probes start from
# the Phase 1 car instead of noise, so the shape the user picked survives.
CAR_SUBJECT = "a red classic sports car with white racing stripes seen from directly above, pointing straight down"
PROBES_R3 = [
    ("tree_a", "sprite", "a round green tree canopy seen from directly overhead like a satellite view, a circle of soft bubbly green clumps"),
    ("tree_b", "sprite", "a round green bush viewed from straight above, a circular blob of puffy leaf clusters, flat lay"),
    ("tree_c", "sprite", "bird's eye view of a single round puffy green treetop, only the top of the leaves is visible"),
    ("car_re45", "restyle:0.45", CAR_SUBJECT),
    ("car_re60", "restyle:0.60", CAR_SUBJECT),
]
# Round 4: the settled prompts, run through each quality setting. car_toy is the
# alternative to restyling the Phase 1 pick: a sports car born in the board's style.
TREE_SUBJECT = PROBES_R3[1][2]  # tree_b won round 3
PROBES_R4 = [
    ("ring", "sprite", PROBES_R2[1][2]),
    ("bale", "sprite", PROBES_R2[2][2]),
    ("tree", "sprite", TREE_SUBJECT),
    ("car_toy", "sprite", "a chunky red toy sports car with big round wheels and white racing stripes seen from directly above, pointing straight up, perfectly symmetrical"),
]
PROBE_SETS = {"r1": PROBES, "r2": PROBES_R2, "r3": PROBES_R3, "r4": PROBES_R4, "r5": PROBES_R4}


def prompt_for(kind: str, subject: str, probe_set: str = "r1") -> str:
    if probe_set in ("r2", "r3", "r4", "r5"):
        return f"{subject}, " + SPRITE_R2.format(style=STYLE_R2)
    return f"{subject}, " + (SPRITE if kind == "sprite" else TILE).format(style=STYLE)


def _flux(settings=None, style=None, ref_image="anchor", size=1024):
    def run(client, kind, prompt, ctx):
        ref = None
        if style:
            ref = wf.StyleRef(ctx[ref_image], **style)
        init, denoise = None, 1.0
        if kind.startswith("restyle"):
            init, denoise = ctx["car_init"], float(kind.split(":")[1])
        graph = wf.flux_txt2img(prompt, SEED, size, size, settings=settings, style=ref, prefix="vr_bakeoff",
                                cutout=wf.CutoutSettings() if kind != "tile" else None,
                                init_image=init, denoise=denoise)
        meta = {"model": "flux1-dev", "size": size, "flux": asdict(settings or wf.FluxSettings()),
                "style_ref": {**style, "image": ref_image} if style else None}
        return client.run(graph), meta
    return run


def _sd35(settings=None):
    def run(client, kind, prompt, ctx):
        graph = wf.sd35_txt2img(prompt, NEGATIVE, SEED, settings=settings, prefix="vr_bakeoff",
                                cutout=wf.CutoutSettings() if kind == "sprite" else None)
        return client.run(graph), {"model": "sd3.5-medium", "sd35": asdict(settings or wf.SD35Settings()), "negative": NEGATIVE}
    return run


BOARD_MED = {"downsampling_factor": 3.5, "weight": 0.85}

CONFIGS = {
    "flux_base": _flux(),
    "flux_g2": _flux(wf.FluxSettings(guidance=2.0)),
    "redux_strong": _flux(style={"downsampling_factor": 3.0, "weight": 1.0}),
    "redux_med": _flux(style={"downsampling_factor": 4.0, "weight": 0.8}),
    "redux_light": _flux(style={"downsampling_factor": 6.0, "weight": 0.7}),
    "sd35_neg": _sd35(),
    # Round 2: Redux points at the style board (objects only), not the whole frame.
    "r2_base": _flux(),
    "r2_board_light": _flux(style={"downsampling_factor": 5.0, "weight": 0.75}, ref_image="board"),
    "r2_board_med": _flux(style={"downsampling_factor": 3.5, "weight": 0.85}, ref_image="board"),
    "r2_board_strong": _flux(style={"downsampling_factor": 3.0, "weight": 1.0}, ref_image="board"),
    "r3_board_med": _flux(style={"downsampling_factor": 3.5, "weight": 0.85}, ref_image="board"),
    # Round 4: one quality lever at a time on the round-2 winner, then all of them together.
    "r4_base": _flux(style=BOARD_MED, ref_image="board"),
    "r4_steps30": _flux(wf.FluxSettings(steps=30), style=BOARD_MED, ref_image="board"),
    "r4_1536": _flux(style=BOARD_MED, ref_image="board", size=1536),
    "r4_bf16": _flux(wf.FluxSettings(weight_dtype="default"), style=BOARD_MED, ref_image="board"),
    "r4_all": _flux(wf.FluxSettings(steps=30, weight_dtype="default"), style=BOARD_MED, ref_image="board", size=1536),
    # Round 5: 1536 + bf16 gave the smoothest finish but leaked board objects; weaken the board's pull.
    "r5_1536_board_a": _flux(wf.FluxSettings(weight_dtype="default"), style={"downsampling_factor": 4.5, "weight": 0.75}, ref_image="board", size=1536),
    "r5_1536_board_b": _flux(wf.FluxSettings(weight_dtype="default"), style={"downsampling_factor": 6.0, "weight": 0.7}, ref_image="board", size=1536),
}


def flatness(img: Image.Image) -> float:
    """Mean colour gradient over the subject, at 256 px. Lower = flatter shading.

    Sprites are measured inside their alpha, shrunk a few pixels so the cut-out edge
    itself does not count as 'shading'.
    """
    img = img.convert("RGBA")
    img.thumbnail((256, 256))
    a = np.asarray(img, dtype=np.float32)
    rgb, alpha = a[..., :3], a[..., 3]
    gy = np.abs(np.diff(rgb, axis=0))[:, :-1].sum(-1)
    gx = np.abs(np.diff(rgb, axis=1))[:-1, :].sum(-1)
    grad = gx + gy
    mask = alpha[:-1, :-1] > 250
    for _ in range(3):  # erode the mask so silhouette edges are excluded
        mask = mask & np.roll(mask, 1, 0) & np.roll(mask, -1, 0) & np.roll(mask, 1, 1) & np.roll(mask, -1, 1)
    return round(float(grad[mask].mean()) if mask.any() else float("nan"), 2)


def load_results() -> dict:
    return json.loads(RESULTS.read_text()) if RESULTS.exists() else {}


def run_config(client: ComfyClient, name: str, ctx: dict, results: dict, probe_set: str) -> None:
    folder = OUT / name
    folder.mkdir(parents=True, exist_ok=True)
    results[name] = {"_probe_set": probe_set}
    for probe_id, kind, subject in PROBE_SETS[probe_set]:
        prompt = prompt_for(kind, subject, probe_set)
        start = time.monotonic()
        images, meta = CONFIGS[name](client, kind, prompt, ctx)
        seconds = round(time.monotonic() - start, 1)
        raw = Image.open(io.BytesIO(images["save"][0]))
        raw.save(folder / f"{probe_id}_raw.png")
        final = raw
        if kind != "tile":
            final = Image.open(io.BytesIO(images["save_cutout"][0]))
            final.save(folder / f"{probe_id}.png")
        else:
            final = pp.make_seamless(raw).resize((128, 128), Image.LANCZOS)
            final.save(folder / f"{probe_id}_128.png")
        score = flatness(final if kind != "tile" else raw)
        results[name][probe_id] = {"prompt": prompt, "seed": SEED, "seconds": seconds, "flatness": score, **meta}
        RESULTS.write_text(json.dumps(results, indent=2))
        print(f"  {name}/{probe_id}: {seconds}s, flatness {score}", flush=True)


def comparison_sheet(results: dict, probe_set: str) -> None:
    """Rows = configs in this probe set, columns = probes. Tiles shown 3 x 3."""
    probes = PROBE_SETS[probe_set]
    names = [n for n, r in results.items() if r.get("_probe_set", "r1") == probe_set]
    cells = []
    for name in names:
        folder = OUT / name
        for col, (probe_id, kind, _) in enumerate(probes):
            r = results[name].get(probe_id)
            if not r:
                cells.append((Image.new("RGB", (192, 192), (60, 60, 60)), f"{probe_id}: -"))
                continue
            if kind != "tile":
                img = Image.open(folder / f"{probe_id}.png")
            else:
                img = pp.tile_grid(Image.open(folder / f"{probe_id}_128.png"))
            label = f"{r['seconds']:.0f}s flat {r['flatness']:.0f}"
            cells.append((img, (name + "  " if col == 0 else "") + label))
    title = f"BAKE-OFF {probe_set.upper()}: ROWS = " + ", ".join(names)
    sheet = pp.contact_sheet(cells, len(probes), (192, 192), title[:110], checker=True)
    sheet.save(OUT / f"comparison_{probe_set}.png")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--configs", help="comma-separated configs to run")
    parser.add_argument("--probes", default="r1", choices=list(PROBE_SETS), help="probe set (default r1)")
    parser.add_argument("--list", action="store_true", help="list configs and exit")
    args = parser.parse_args()
    if args.list or not args.configs:
        print("\n".join(CONFIGS))
        return
    names = args.configs.split(",")
    unknown = [n for n in names if n not in CONFIGS]
    if unknown:
        parser.error(f"unknown config(s): {', '.join(unknown)}")
    client = ComfyClient()
    client.check_alive()
    ctx = {"anchor": client.upload_image(ANCHOR.read_bytes(), "vr_style_anchor.png"),
           "board": client.upload_image(BOARD.read_bytes(), "vr_style_board.png"),
           "car_init": client.upload_image(CAR_INIT.read_bytes(), "vr_car_init.png")}
    results = load_results()
    for name in names:
        print(f"{name}:", flush=True)
        run_config(client, name, ctx, results, args.probes)
        comparison_sheet(results, args.probes)


if __name__ == "__main__":
    main()

"""Renders the Phase 1 design mockups into docs/mockups/.

    python tools/comfy/make_mockups.py                      # every generated job
    python tools/comfy/make_mockups.py --only style_frames,tile_samples

Every image's prompt, seed, settings and render time go to docs/mockups/seeds.json,
so whichever frame or car gets picked can be reproduced exactly.
"""
import argparse
import io
import json
import time
from dataclasses import asdict
from pathlib import Path

from PIL import Image, ImageDraw

import postprocess as pp
import workflows as wf
from comfy_client import ComfyClient

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "mockups"
RAW = OUT / "raw"
SEEDS_FILE = OUT / "seeds.json"

SCENE = (
    "top-down view from directly above of a winding race track for a children's racing video game: "
    "grey asphalt road with red and white kerbs, green grass, a few round trees, tyre stacks and hay bales, "
    "four small colourful race cars (red, blue, yellow, green) driving around a bend, 2D video game screenshot"
)
STYLE_FLAVOURS = {
    "bold_outline": "flat vector cartoon illustration, thick black outlines, bright saturated flat colours, no gradients",
    "picture_book": "soft flat children's picture book illustration, rounded friendly shapes, warm bright flat colours, no outlines",
    "toy_playmat": "minimal geometric flat design like a children's toy car playmat, simple shapes, bold primary colours",
}
CAR_SUFFIX = (
    "seen from directly above, top-down plan view, pointing straight up, perfectly symmetrical, "
    "2D video game car sprite, soft flat children's picture book illustration, rounded friendly shapes, warm bright flat colours, no outlines, "
    "no shading, no shadow, centred on a plain white background"
)
CAR_DESIGNS = {
    "chunky": "a chunky cute red race car with big round wheels",
    "kart": "a red go-kart with a driver wearing a helmet",
    "formula": "a red formula racing car",
    "rally": "a red rally hatchback with a roof spoiler",
    "buggy": "a red beach buggy with a roll cage",
    "stock": "a red stock car with a racing number on the roof",
    "bubble": "a red bubble-shaped toy car",
    "sports": "a red classic sports car with white racing stripes",
}
TILE_SUFFIX = "seamless texture, viewed from directly above, flat vector cartoon style, flat colours, uniform, no objects, no borders"
TILES = {
    "asphalt": "dark grey asphalt road surface with subtle speckles",
    "grass": "short bright green lawn grass",
    "sand": "warm yellow beach sand with small ripples",
}


class Recorder:
    """Writes images and keeps seeds.json in step with them."""

    def __init__(self):
        self.data = json.loads(SEEDS_FILE.read_text()) if SEEDS_FILE.exists() else {}

    def save(self, img: Image.Image, rel: str, **meta) -> Path:
        path = OUT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        img.save(path)
        if meta:
            self.data[rel] = meta
            SEEDS_FILE.write_text(json.dumps(self.data, indent=2))
        return path


def _generate(client: ComfyClient, prompt: str, seed: int, w: int, h: int, cutout: bool):
    settings = wf.FluxSettings()
    graph = wf.flux_txt2img(prompt, seed, w, h, settings, wf.CutoutSettings() if cutout else None, prefix="vr_mockup")
    start = time.monotonic()
    images = client.run(graph)
    meta = {"prompt": prompt, "seed": seed, "size": [w, h], "flux": asdict(settings),
            "cutout": asdict(wf.CutoutSettings()) if cutout else None, "seconds": round(time.monotonic() - start, 1)}
    raw = Image.open(io.BytesIO(images["save"][0]))
    cut = Image.open(io.BytesIO(images["save_cutout"][0])) if cutout else None
    return raw, cut, meta


def style_frames(client: ComfyClient, rec: Recorder) -> None:
    cells = []
    n = 0
    for flavour, style in STYLE_FLAVOURS.items():
        for seed in (101, 202):
            n += 1
            prompt = f"{SCENE}, {style}"
            img, _, meta = _generate(client, prompt, seed, 1344, 768, cutout=False)
            rec.save(img, f"style_frame_{n:02d}.png", flavour=flavour, **meta)
            cells.append((img, f"{n:02d}  {flavour}  seed {seed}"))
            print(f"  style_frame_{n:02d} ({flavour}) {meta['seconds']}s", flush=True)
    rec.save(pp.contact_sheet(cells, 2, (672, 384), "STYLE FRAMES - PICK ONE"), "style_frames_sheet.png")


def car_sheet(client: ComfyClient, rec: Recorder) -> None:
    large, actual = [], []
    for name, design in CAR_DESIGNS.items():
        prompt = f"{design}, {CAR_SUFFIX}"
        raw, cut, meta = _generate(client, prompt, 11, 1024, 1024, cutout=True)
        rec.save(raw, f"raw/car_{name}.png", **meta)
        rec.save(cut, f"raw/car_{name}_cutout.png")
        large.append((cut, name))
        # In game the car points +X, so turn the upward-facing sprite clockwise.
        actual.append((pp.fit_sprite(cut.rotate(-90, expand=True), (128, 72)), name))
        print(f"  car_{name} {meta['seconds']}s", flush=True)
    top = pp.contact_sheet(large, 4, (256, 256), "CAR CANDIDATES", checker=True)
    bottom = pp.contact_sheet(actual, 8, (128, 72), "AT REAL IN-GAME SIZE (128 x 72, facing +X)", bg=(88, 92, 98))
    sheet = Image.new("RGB", (max(top.width, bottom.width), top.height + bottom.height), (40, 44, 52))
    sheet.paste(top, (0, 0))
    sheet.paste(bottom, (0, top.height))
    rec.save(sheet, "car_sheet.png")


def tile_samples(client: ComfyClient, rec: Recorder) -> None:
    cells = []
    for name, desc in TILES.items():
        prompt = f"{desc}, {TILE_SUFFIX}"
        raw, _, meta = _generate(client, prompt, 31, 1024, 1024, cutout=False)
        rec.save(raw, f"raw/tile_{name}.png", **meta)
        before = raw.resize((128, 128), Image.LANCZOS)
        after = pp.make_seamless(raw).resize((128, 128), Image.LANCZOS)
        rec.save(after, f"raw/tile_{name}_128.png")
        cells.append((pp.tile_grid(before), f"{name}: raw, tiled 3x3"))
        cells.append((pp.tile_grid(after), f"{name}: seamless pass"))
        print(f"  tile_{name} {meta['seconds']}s", flush=True)
    kerb = draw_kerb()
    rec.save(kerb, "raw/tile_kerb_128.png")
    cells.append((pp.tile_grid(kerb), "kerb: drawn, not generated"))
    rec.save(pp.contact_sheet(cells, 2, (384, 384), "TILES AT 128 PX, EACH SHOWN 3 x 3"), "tile_samples.png")


def draw_kerb(size: int = 128, stripes: int = 4) -> Image.Image:
    """A flat red/white kerb strip. Too geometric to generate well; trivial to draw."""
    img = Image.new("RGB", (size, size), (70, 74, 80))
    draw = ImageDraw.Draw(img)
    band = size // 4
    step = size // stripes
    for i in range(stripes):
        colour = (220, 40, 40) if i % 2 == 0 else (245, 245, 245)
        draw.rectangle((i * step, size - band, (i + 1) * step - 1, size - 1), fill=colour)
    draw.line((0, size - band - 2, size, size - band - 2), fill=(30, 30, 30), width=4)
    return img


CHOSEN_CAR = "sports"
CAR_SOURCE_FACING = "down"  # the chosen sports car came out nose-down despite the prompt
RACER_PAINTS = {
    "blue": "bright blue",
    "yellow": "sunny yellow",
    "green": "bright green",
}
FACING_TO_PLUS_X = {"up": -90, "down": 90, "left": 180, "right": 0}


def car_palette(client: ComfyClient, rec: Recorder) -> None:
    """Repaint the chosen car with FLUX Kontext so all four racers share one silhouette."""
    source_png = (RAW / f"car_{CHOSEN_CAR}.png").read_bytes()
    original = Image.open(RAW / f"car_{CHOSEN_CAR}_cutout.png")
    image_name = client.upload_image(source_png, f"vr_car_{CHOSEN_CAR}.png")
    racers = [("red", original)]
    for name, paint in RACER_PAINTS.items():
        instruction = (f"Change the car's red paint to {paint}. Keep the white racing stripes, the exact shape, "
                       "the wheels, the windows, the viewing angle and the plain white background exactly the same.")
        seed = 11
        graph = wf.flux_kontext_edit(image_name, instruction, seed, cutout=wf.CutoutSettings(), prefix="vr_palette")
        start = time.monotonic()
        images = client.run(graph)
        cut = Image.open(io.BytesIO(images["save_cutout"][0]))
        rec.save(Image.open(io.BytesIO(images["save"][0])), f"raw/car_{CHOSEN_CAR}_{name}.png",
                 source=f"raw/car_{CHOSEN_CAR}.png", instruction=instruction, seed=seed,
                 model=wf.FLUX_KONTEXT, seconds=round(time.monotonic() - start, 1))
        rec.save(cut, f"raw/car_{CHOSEN_CAR}_{name}_cutout.png")
        racers.append((name, cut))
        print(f"  car_{CHOSEN_CAR}_{name}", flush=True)
    turn = FACING_TO_PLUS_X[CAR_SOURCE_FACING]
    large = [(cut, name) for name, cut in racers]
    actual = [(pp.fit_sprite(cut.rotate(turn, expand=True), (128, 72)), name) for name, cut in racers]
    top = pp.contact_sheet(large, 4, (256, 256), f"RACER PALETTE - {CHOSEN_CAR.upper()}", checker=True)
    bottom = pp.contact_sheet(actual, 4, (128, 72), "IN GAME (128 x 72, facing +X)", bg=(74, 79, 87))
    sheet = Image.new("RGB", (max(top.width, bottom.width), top.height + bottom.height), (40, 44, 52))
    sheet.paste(top, (0, 0))
    sheet.paste(bottom, (0, top.height))
    rec.save(sheet, "car_palette.png")


JOBS = {"style_frames": style_frames, "car_sheet": car_sheet, "tile_samples": tile_samples, "car_palette": car_palette}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="comma-separated jobs: " + ", ".join(JOBS))
    args = parser.parse_args()
    names = args.only.split(",") if args.only else list(JOBS)
    unknown = [n for n in names if n not in JOBS]
    if unknown:
        parser.error(f"unknown job(s): {', '.join(unknown)}")
    client = ComfyClient()
    client.check_alive()
    rec = Recorder()
    RAW.mkdir(parents=True, exist_ok=True)
    for name in names:
        print(f"{name}:", flush=True)
        JOBS[name](client, rec)


if __name__ == "__main__":
    main()

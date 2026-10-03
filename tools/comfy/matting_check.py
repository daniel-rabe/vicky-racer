"""Matting bake-off: the same raw images cut out by each locally available BiRefNet model.

    python tools/comfy/matting_check.py

Cut-outs are shown at sprite size on the game's asphalt and grass colours, because halos
and leftover shadows only show against the background they will actually sit on.
Writes docs/mockups/bakeoff/matting/sheet.png.
"""
import io
from pathlib import Path

from PIL import Image

import postprocess as pp
import workflows as wf
from comfy_client import ComfyClient

ROOT = Path(__file__).resolve().parents[2]
BAKEOFF = ROOT / "docs" / "mockups" / "bakeoff"
OUT = BAKEOFF / "matting"
# Only models already on disk — anything else would trigger a silent download.
MODELS = ["BiRefNet-general", "BiRefNet_toonout"]
SOURCES = {
    "sports car (shadow case)": ROOT / "docs" / "mockups" / "raw" / "car_sports.png",
    "toy car": BAKEOFF / "r5_1536_board_a" / "car_toy_raw.png",
    "ring": BAKEOFF / "r5_1536_board_a" / "ring_raw.png",
    "tree": BAKEOFF / "r5_1536_board_a" / "tree_raw.png",
}
GROUNDS = {"asphalt": (102, 109, 116), "grass": (168, 190, 68)}


def on_ground(cut: Image.Image, colour: tuple[int, int, int], box: int = 128) -> Image.Image:
    sprite = pp.fit_sprite(cut, (box, box))
    tile = Image.new("RGB", (box, box), colour)
    tile.paste(sprite, (0, 0), sprite)
    return tile.resize((box * 2, box * 2), Image.NEAREST)  # 2x nearest so edge pixels are inspectable


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    client = ComfyClient()
    client.check_alive()
    cells = []
    for label, path in SOURCES.items():
        uploaded = client.upload_image(path.read_bytes(), f"vr_matting_{path.stem}.png")
        for model in MODELS:
            images = client.run(wf.cutout_only(uploaded, wf.CutoutSettings(model=model), prefix="vr_matting"))
            cut = Image.open(io.BytesIO(images["save_cutout"][0])).convert("RGBA")
            cut.save(OUT / f"{path.parent.name}_{path.stem}_{model}.png")
            for ground, colour in GROUNDS.items():
                cells.append((on_ground(cut, colour), f"{label[:14]} {model[9:]} {ground}"))
            print(f"  {label} / {model}", flush=True)
    pp.contact_sheet(cells, 4, (256, 256), "MATTING: general vs toonout, 128px sprite shown 2x").save(OUT / "sheet.png")


if __name__ == "__main__":
    main()

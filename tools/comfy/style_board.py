"""Build the Redux style reference: frame 04's objects, cut out, on a plain board.

    python tools/comfy/style_board.py

Feeding the whole style frame to Redux leaked its *content* into every asset (tyre
stacks sitting in roundabouts, grass tiles turned into track). The board keeps the
look — soft clay-toy shading, rounded shapes, warm colours — without the track.
Writes docs/mockups/style_board.png.
"""
import io
from pathlib import Path

from PIL import Image

import workflows as wf
from comfy_client import ComfyClient

ROOT = Path(__file__).resolve().parents[2]
MOCKUPS = ROOT / "docs" / "mockups"
BOARD_BG = (244, 241, 230)

# Pixel boxes in style_anchor.png (1344 x 768).
CROPS = {
    "tree_tl": (0, 0, 170, 240),
    "tree_bl": (0, 530, 215, 768),
    "ring_a": (730, 40, 862, 172),
    "ring_b": (870, 118, 1006, 252),
    "bale_a": (1118, 535, 1262, 680),
    "bale_b": (212, 645, 362, 768),
    "car_red": (500, 135, 628, 242),
    "car_yellow": (624, 360, 700, 488),
    "car_blue": (1012, 350, 1132, 475),
    "car_green": (825, 545, 958, 640),
    "car_orange": (492, 520, 612, 612),
    "log": (820, 280, 875, 335),
}


def main() -> None:
    client = ComfyClient()
    client.check_alive()
    anchor = Image.open(MOCKUPS / "style_anchor.png").convert("RGB")
    cutouts = []
    for name, box in CROPS.items():
        crop = anchor.crop(box)
        crop = crop.resize((crop.width * 3, crop.height * 3), Image.LANCZOS)  # matting works better larger
        buf = io.BytesIO()
        crop.save(buf, "PNG")
        uploaded = client.upload_image(buf.getvalue(), f"vr_board_{name}.png")
        images = client.run(wf.cutout_only(uploaded, prefix="vr_board"))
        cutouts.append(Image.open(io.BytesIO(images["save_cutout"][0])).convert("RGBA"))
        print(f"  cut out {name}", flush=True)

    board = Image.new("RGB", (1024, 1024), BOARD_BG)
    cols, cell = 4, 1024 // 4
    rows = (len(cutouts) + cols - 1) // cols
    top = (1024 - rows * cell) // 2
    for i, cut in enumerate(cutouts):
        cut.thumbnail((cell - 24, cell - 24), Image.LANCZOS)
        x = (i % cols) * cell + (cell - cut.width) // 2
        y = top + (i // cols) * cell + (cell - cut.height) // 2
        board.paste(cut, (x, y), cut)
    board.save(MOCKUPS / "style_board.png")
    print("wrote docs/mockups/style_board.png")


if __name__ == "__main__":
    main()

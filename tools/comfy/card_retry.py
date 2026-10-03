"""Candidate sheet for setup-card variants that need another try.

    python tools/comfy/card_retry.py

Renders each instruction below at several seeds from the red car's master, so the best can be
pinned in asset_manifest.json (instruction + seed) and rebuilt with `generate_assets.py build`.
Writes docs/mockups/candidates/cards_retry.png.
"""
import io
from pathlib import Path

from PIL import Image

import postprocess as pp
import recipe
from comfy_client import ComfyClient
from generate_assets import CANDIDATES, MASTERS, SHEETS, TO_PLUS_X, all_entries, facing_of, load_manifest

SEEDS = [12, 13, 14]
RETRIES = {
    "card_slider": ("Draw three curved light-blue motion swooshes beside the left side of the car, showing it sliding "
                    "sideways. Keep the car exactly the same, pointing straight up, the top-down view and the plain white background."),
    "card_kart": ("Turn this car into a small open-top red go-kart seen from directly above, pointing straight up, "
                  "with a driver wearing a red helmet in the seat. Keep the plain white background."),
    "card_rocket": ("Add two big rocket boosters with orange flames at the back of the car, which is the top of the "
                    "picture, with the flames pointing up. Keep the red paint, the white stripes, the top-down view "
                    "and the plain white background."),
    "card_banana": ("Repaint this car bright banana yellow with just a few small brown marks at the front and back like "
                    "the tips of a banana, and put a peeled banana on the roof. Keep the shape, the top-down view and the plain white background."),
}


def main() -> None:
    client = ComfyClient()
    client.check_alive()
    uploaded = client.upload_image((MASTERS / "car_red_raw.png").read_bytes(), "vr_src_car_red.png")
    CANDIDATES.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    turn = TO_PLUS_X[facing_of(all_entries(manifest)["car_red"], all_entries(manifest))]
    cells = []
    for card, instruction in RETRIES.items():
        for seed in SEEDS:
            path = CANDIDATES / f"{card}_s{seed}.png"
            if not path.exists():
                images = client.run(recipe.variant_graph(uploaded, instruction, seed, prefix="vr_card_retry"))
                Image.open(io.BytesIO(images["save_cutout"][0])).save(path)
                Image.open(io.BytesIO(images["save"][0])).save(CANDIDATES / f"{card}_s{seed}_raw.png")
                print(f"  {card} seed {seed}", flush=True)
            cells.append((Image.open(path).convert("RGBA").rotate(turn, expand=True), f"{card[5:]} seed {seed}"))
    pp.contact_sheet(cells, len(SEEDS), (312, 190), "CARD RETRIES (facing +X, as on the card)", checker=True) \
        .save(SHEETS / "cards_retry.png")
    print("sheet: docs/mockups/candidates/cards_retry.png")


if __name__ == "__main__":
    main()

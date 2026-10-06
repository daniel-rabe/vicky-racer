"""Listening page for the Phase 21 island sounds (DESIGN.md §21.3, §21.5).

    python tools/comfy/listen_island.py

The same page as listen_boats.py: every candidate cut the way `build` cuts it, as MP3
previews with an index.html, in docs/mockups/sfx/listen_island/. The pirate ship's bell, the
first candidate for the swap, is played beside the new swap sounds. The ear decides.
"""
from pathlib import Path

import generate_music as gm
import generate_sfx as gs
import listen_boats as lb

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "mockups" / "sfx" / "listen_island"
SFX = ["harbour_swap", "horn_pirate", "seagull", "dolphin"]
USE = {
    "harbour_swap": "Swapping car and boat at the harbour (a new bell)",
    "horn_pirate": "Or reuse the pirate ship's bell for the swap (already in the game as its horn)",
    "seagull": "A gull flapping away from a horn",
    "dolphin": "A dolphin leaping beside the boat",
}
INTRO = ('<p class="intro"><b>Three sounds to pick.</b> For the <b>swap</b> at the harbour: one of the new bells, or the '
         'pirate ship\'s bell you already chose (yellow, IN THE GAME). Then a <b>seagull</b> and a <b>dolphin</b>. Each '
         'candidate plays as the game will use it, trimmed and faded. <b>SUGGESTED</b> is a measurement, not a listen. '
         'Tell Claude your picks, for example "swap 104, gull 102, dolphin 107", or "swap: the pirate bell".</p>')


def main() -> None:
    lb.OUT, lb.SFX, lb.MUSIC, lb.USE, lb.INTRO = OUT, SFX, [], USE, INTRO
    page = gm.LISTEN_PAGE
    gm.LISTEN_PAGE = page.replace("<title>Vicky Racer Music</title>", "<title>Vicky Racer Island Sounds</title>")
    lb.main()
    index = OUT / "index.html"
    index.write_text(index.read_text(encoding="utf-8").replace("<h1>BOAT SOUNDS</h1>", "<h1>ISLAND SOUNDS</h1>")
                     .replace("Vicky Racer Boat Sounds", "Vicky Racer Island Sounds"), encoding="utf-8")


if __name__ == "__main__":
    main()

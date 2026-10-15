"""Listening page for the Free Drive sounds (DESIGN.md §23).

    python tools/comfy/listen_town_fun.py

The same page as listen_boats.py: every candidate cut the way `build` cuts it, as MP3
previews with an index.html, in docs/mockups/sfx/listen_town_fun/. The ear decides.
"""
from pathlib import Path

import generate_music as gm
import generate_sfx as gs
import listen_boats as lb

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "mockups" / "sfx" / "listen_town_fun"
SFX = ["rain_loop", "cheer", "water_spray", "fire_out", "bus_bell"]
USE = {
    "rain_loop": "A shower over the town (loops while it rains)",
    "cheer": "A goal, a delivery, the puppy home",
    "water_spray": "The fire engine's hose (loops while spraying)",
    "fire_out": "A bonfire put out",
    "bus_bell": "The bus doors opening at a stop",
}
INTRO = ('<p class="intro"><b>Five sounds to pick</b> for Free Drive: the <b>rain</b>, a <b>cheer</b>, the fire '
         'engine\'s <b>water spray</b>, a bonfire going <b>out</b>, and the <b>bus bell</b>. Each candidate plays as '
         'the game will use it, trimmed and faded. <b>SUGGESTED</b> is a measurement, not a listen. Tell Claude your '
         'picks, for example "rain 103, cheer 101, spray 106, fire 102, bell 104".</p>')


def main() -> None:
    lb.OUT, lb.SFX, lb.MUSIC, lb.USE, lb.INTRO = OUT, SFX, [], USE, INTRO
    page = gm.LISTEN_PAGE
    gm.LISTEN_PAGE = page.replace("<title>Vicky Racer Music</title>", "<title>Vicky Racer Free Drive Sounds</title>")
    lb.main()
    index = OUT / "index.html"
    index.write_text(index.read_text(encoding="utf-8").replace("<h1>BOAT SOUNDS</h1>", "<h1>FREE DRIVE SOUNDS</h1>")
                     .replace("Vicky Racer Boat Sounds", "Vicky Racer Free Drive Sounds"), encoding="utf-8")


if __name__ == "__main__":
    main()

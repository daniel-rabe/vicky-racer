"""Listening page for the Soapbox's sounds (DESIGN.md §4.2).

    python tools/comfy/listen_soapbox.py

The same page as listen_boats.py: every candidate cut the way `build` cuts it, as MP3
previews with an index.html, in docs/mockups/sfx/listen_soapbox/. The toy car engine the
Soapbox uses now is played beside the wheel rattles. The ear decides.
"""
from pathlib import Path

import generate_music as gm
import listen_boats as lb

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "mockups" / "sfx" / "listen_soapbox"
SFX = ["rattle_loop", "engine_loop", "horn_soapbox"]
USE = {
    "rattle_loop": "The Soapbox rolling: wooden wheels instead of an engine, pitched by speed",
    "engine_loop": "Or keep the toy car engine every other car has (in the game now)",
    "horn_soapbox": "The Soapbox's horn: a bicycle bell",
}
INTRO = ('<p class="intro"><b>Two sounds to pick for the Soapbox.</b> Its <b>rolling sound</b>: one of the wooden-wheel '
         'rattles, or the toy engine it has now (IN THE GAME). Then its <b>horn</b>, a bicycle bell. Loops play three '
         'times round so you can hear the seam. <b>SUGGESTED</b> is a measurement, not a listen. Tell Claude your picks, '
         'for example "rattle 104, bell 106".</p>')


def main() -> None:
    lb.OUT, lb.SFX, lb.MUSIC, lb.USE, lb.INTRO = OUT, SFX, [], USE, INTRO
    gm.LISTEN_PAGE = gm.LISTEN_PAGE.replace("<title>Vicky Racer Music</title>", "<title>Soapbox Sounds</title>")
    lb.main()
    index = OUT / "index.html"
    index.write_text(index.read_text(encoding="utf-8").replace("<h1>BOAT SOUNDS</h1>", "<h1>SOAPBOX SOUNDS</h1>")
                     .replace("Vicky Racer Boat Sounds", "Soapbox Sounds"), encoding="utf-8")


if __name__ == "__main__":
    main()

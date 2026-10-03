"""Composite the race HUD over the chosen style anchor at true 1920 x 1080 size.

    python tools/layouts/screen_mockup.py

Takes docs/mockups/hud_layout.svg, strips its placeholder world and the pink spec
annotations, lays it over docs/mockups/style_anchor.png and renders
docs/mockups/screen_mockup.png. Re-run after changing either input.
"""
import base64
import re
from pathlib import Path

from render_svg import render

ROOT = Path(__file__).resolve().parents[2]
MOCKUPS = ROOT / "docs" / "mockups"


def main() -> None:
    svg = (MOCKUPS / "hud_layout.svg").read_text(encoding="utf-8")
    # Placeholder world: the grass rect, the two road strokes and the stand-in car.
    svg = re.sub(r'<!-- Placeholder world behind the HUD -->.*?(?=\n\s*<!-- Safe area)', "", svg, flags=re.S)
    # Spec annotations: every element carrying the spec classes.
    svg = re.sub(r'\s*<(rect|text)[^>]*class="spec(-text)?"[^>]*?(/>|>.*?</text>)', "", svg, flags=re.S)
    anchor = base64.b64encode((MOCKUPS / "style_anchor.png").read_bytes()).decode()
    background = (f'<image href="data:image/png;base64,{anchor}" x="0" y="0" width="1920" height="1080" '
                  'preserveAspectRatio="xMidYMid slice"/>')
    svg = svg.replace("</defs>", "</defs>\n  " + background, 1)
    out = MOCKUPS / "screen_mockup.svg"
    out.write_text(svg, encoding="utf-8")
    print(render(out))


if __name__ == "__main__":
    main()

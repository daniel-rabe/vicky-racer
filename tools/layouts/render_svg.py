"""Rasterise layout SVGs to PNG with headless Edge, using the real HUD font.

    python tools/layouts/render_svg.py docs/mockups/hud_layout.svg [more.svg ...]

Writes a .png next to each .svg. The Public Pixel font is embedded as a data URI in a
wrapper page, because a file:// page cannot reliably load a font from another file path.
"""
import base64
import re
import subprocess
import sys
import tempfile
from pathlib import Path

EDGE = Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")
FONT = Path("G:/Godot/external_assets/fonts/Public_Pixel_Font_1_24/PublicPixel.ttf")


def render(svg_path: Path) -> Path:
    svg = svg_path.read_text(encoding="utf-8")
    width = int(float(re.search(r'<svg[^>]*\swidth="([\d.]+)"', svg).group(1)))
    height = int(float(re.search(r'<svg[^>]*\sheight="([\d.]+)"', svg).group(1)))
    font_b64 = base64.b64encode(FONT.read_bytes()).decode()
    page = (
        "<!doctype html><html><head><meta charset='utf-8'><style>"
        f"@font-face {{ font-family: 'Public Pixel'; src: url(data:font/ttf;base64,{font_b64}); }}"
        "html, body { margin: 0; padding: 0; overflow: hidden; } svg { display: block; }"
        f"</style></head><body>{svg}</body></html>"
    )
    out = svg_path.with_suffix(".png")
    with tempfile.TemporaryDirectory() as tmp:
        html = Path(tmp) / "page.html"
        html.write_text(page, encoding="utf-8")
        subprocess.run([
            str(EDGE), "--headless=new", "--disable-gpu", "--hide-scrollbars",
            f"--user-data-dir={tmp}/profile", f"--window-size={width},{height}",
            "--virtual-time-budget=2000", f"--screenshot={out}", html.as_uri(),
        ], check=True, capture_output=True, timeout=120)
    return out


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for arg in sys.argv[1:]:
        print(render(Path(arg).resolve()))

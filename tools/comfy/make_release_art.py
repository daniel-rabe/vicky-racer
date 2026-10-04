"""The release build's art (docs/DESIGN.md §17), composed from approved assets — nothing new is
generated: the player's red car master and the title's own font and colours.

    python tools/comfy/make_release_art.py

Writes art/ui/release/icon.png (256 px, the project and window icon), icon.ico (16-256 px,
the Windows .exe icon) and splash.png (the boot splash shown while the game loads).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

import postprocess as pp

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art" / "ui" / "release"
CAR = Path(__file__).parent / "masters" / "car_red.png"   # nose down, cut out
FONT = ROOT / "ui" / "fonts" / "PublicPixel.ttf"
NAVY = (20, 32, 46)            # the menus' background
GRASS = (122, 178, 66)
YELLOW = (255, 210, 63)        # VICKY on the title
RED = (230, 57, 70)            # RACER on the title
OUTLINE = (14, 20, 28)


def car(angle: float) -> Image.Image:
    """The red car, nose up and then turned `angle` degrees (counter-clockwise)."""
    return Image.open(CAR).convert("RGBA").rotate(180 + angle, expand=True, resample=Image.BICUBIC)


def shadow(img: Image.Image, offset: tuple[int, int], blur: int, alpha: int = 90) -> Image.Image:
    shade = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shade.putalpha(img.getchannel("A").point(lambda v: v * alpha // 255))
    shade = shade.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", (img.width + abs(offset[0]) + blur * 2, img.height + abs(offset[1]) + blur * 2))
    out.alpha_composite(shade, (blur + max(offset[0], 0), blur + max(offset[1], 0)))
    out.alpha_composite(img, (blur, blur))
    return out


def icon(size: int = 1024) -> Image.Image:
    """A rounded grass-green tile with a road band and the red car racing up it at a slant."""
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=size // 5, fill=255)
    body = Image.new("RGBA", (size, size), GRASS + (255,))
    draw = ImageDraw.Draw(body)
    road = size * 0.36  # a diagonal road band behind the car, with kerbs
    centre = [(-size, 2 * size), (2 * size, -size)]
    draw.line(centre, fill=(232, 228, 210), width=int(road + size * 0.06))
    draw.line(centre, fill=(86, 92, 104), width=int(road))
    tile.paste(body, (0, 0), mask)
    racer = car(-45)
    racer = pp.fit_sprite(racer, (int(size * 0.86), int(size * 0.86)))
    racer = shadow(racer, (size // 40, size // 40), size // 60)
    tile.alpha_composite(racer, ((size - racer.width) // 2, (size - racer.height) // 2))
    ring = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle((0, 0, size - 1, size - 1), radius=size // 5, outline=OUTLINE,
                                           width=size // 40)
    tile.alpha_composite(ring)
    return tile


def title_text(draw: ImageDraw.ImageDraw, text: str, centre_x: int, top: int, size: int, colour) -> None:
    font = ImageFont.truetype(str(FONT), size)
    width = draw.textlength(text, font=font)
    draw.text((centre_x - width / 2, top), text, font=font, fill=colour, stroke_width=size // 6, stroke_fill=OUTLINE)


def splash() -> Image.Image:
    """The boot splash: VICKY RACER as on the title, the car racing past beneath it."""
    img = Image.new("RGBA", (1920, 1080), NAVY + (255,))
    draw = ImageDraw.Draw(img)
    title_text(draw, "VICKY", 960, 170, 150, YELLOW)
    title_text(draw, "RACER", 960, 360, 150, RED)
    racer = pp.fit_sprite(car(-90), (420, 240))  # nose to the right
    racer = shadow(racer, (10, 12), 10)
    img.alpha_composite(racer, ((1920 - racer.width) // 2, 640))
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    big = icon()
    big.resize((256, 256), Image.LANCZOS).save(OUT / "icon.png")
    big.save(OUT / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    splash().convert("RGB").save(OUT / "splash.png")
    print("wrote art/ui/release/icon.png, icon.ico, splash.png")


if __name__ == "__main__":
    main()

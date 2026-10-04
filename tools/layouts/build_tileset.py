"""Builds the ground tileset: grass and sand, with every corner combination between them.

    python tools/layouts/build_tileset.py

Writes art/tiles/ground_atlas.png (4 x 4 tiles of 128 px) and track/ground_tiles.tres, a TileSet
with a "Grass / Sand" terrain in Match Corners mode, so sand traps can be painted by hand in
Godot's TileMap editor and the edges join up on their own (docs/DESIGN.md §7.2).

Tile c (0-15) has sand on corner bits tl=8, tr=4, bl=2, br=1. Inside a tile the sand is where
the bilinear blend of its four corners exceeds 0.5. Neighbouring tiles share corners, so the
edge runs on across tile borders without a seam, and the rounded shape comes for free.
track.gd uses the same rule to tell whether a car is on sand.
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TILE = 128
RIM = (201, 162, 74)        # darker sand outline, as on the track layout
RIM_HALF_WIDTH = 3.0        # px either side of the sand edge
CORNER_BITS = {"tl": 8, "tr": 4, "bl": 2, "br": 1}


def corners(c: int) -> tuple[int, int, int, int]:
    return tuple(int(bool(c & CORNER_BITS[k])) for k in ("tl", "tr", "bl", "br"))


def render_tile(c: int, grass: np.ndarray, sand: np.ndarray, rim=RIM) -> np.ndarray:
    """One tile: `grass` is the base fill, `sand` the patch fill (any pair, per theme)."""
    tl, tr, bl, br = corners(c)
    v, u = (np.mgrid[0:TILE, 0:TILE].astype(np.float32) + 0.5) / TILE
    f = tl * (1 - u) * (1 - v) + tr * u * (1 - v) + bl * (1 - u) * v + br * u * v
    # Signed distance to the f = 0.5 edge in pixels, from the analytic gradient of the blend.
    dfu = (tr - tl) * (1 - v) + (br - bl) * v
    dfv = (bl - tl) * (1 - u) + (br - tr) * u
    grad = np.hypot(dfu, dfv) / TILE
    dist = np.where(grad > 1e-6, (f - 0.5) / np.maximum(grad, 1e-6), np.where(f > 0.5, 1e6, -1e6))
    sand_w = np.clip(dist + 0.5, 0.0, 1.0)[..., None]                    # antialiased fill
    rim_w = np.clip(RIM_HALF_WIDTH + 0.5 - np.abs(dist), 0.0, 1.0)[..., None]
    base = grass * (1 - sand_w) + sand * sand_w
    return base * (1 - rim_w) + np.array(rim, np.float32) * rim_w


def tileset_tres(atlas: str = "art/tiles/ground_atlas.png", base_name: str = "Grass", patch_name: str = "Sand",
                 base_colour: str = "Color(0.66, 0.75, 0.27, 1)", patch_colour: str = "Color(0.91, 0.8, 0.48, 1)") -> str:
    lines = [
        '[gd_resource type="TileSet" load_steps=3 format=3]',
        "",
        f'[ext_resource type="Texture2D" path="res://{atlas}" id="1_atlas"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_ground"]',
        'texture = ExtResource("1_atlas")',
        "texture_region_size = Vector2i(128, 128)",
    ]
    names = {"tl": "top_left_corner", "tr": "top_right_corner", "bl": "bottom_left_corner", "br": "bottom_right_corner"}
    for c in range(16):
        x, y = c % 4, c // 4
        bits = dict(zip(("tl", "tr", "bl", "br"), corners(c)))
        key = f"{x}:{y}/0"
        lines += [f"{key} = 0", f"{key}/terrain_set = 0",
                  f"{key}/terrain = {1 if all(bits.values()) else 0}"]
        lines += [f"{key}/terrains_peering_bit/{names[k]} = {bits[k]}" for k in ("tl", "tr", "bl", "br")]
        lines.append(f"{key}/custom_data_0 = {c}")
    lines += [
        "",
        "[resource]",
        "tile_size = Vector2i(128, 128)",
        "terrain_set_0/mode = 1",
        f'terrain_set_0/terrain_0/name = "{base_name}"',
        f"terrain_set_0/terrain_0/color = {base_colour}",
        f'terrain_set_0/terrain_1/name = "{patch_name}"',
        f"terrain_set_0/terrain_1/color = {patch_colour}",
        'custom_data_layer_0/name = "sand_corners"',
        "custom_data_layer_0/type = 2",
        'sources/0 = SubResource("TileSetAtlasSource_ground")',
        "",
    ]
    return "\n".join(lines)


def build_atlas(base_png: Path, patch_png: Path, atlas_out: Path, rim=RIM) -> None:
    base = np.asarray(Image.open(base_png).convert("RGB"), np.float32)
    patch = np.asarray(Image.open(patch_png).convert("RGB"), np.float32)
    atlas = np.zeros((4 * TILE, 4 * TILE, 3), np.float32)
    for c in range(16):
        x, y = c % 4, c // 4
        atlas[y * TILE:(y + 1) * TILE, x * TILE:(x + 1) * TILE] = render_tile(c, base, patch, rim)
    atlas_out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(atlas, 0, 255).astype(np.uint8)).save(atlas_out)


def main() -> None:
    """Track 01's meadow tiles. Every theme's tiles: tools/layouts/theme_art.py."""
    build_atlas(ROOT / "art/tiles/grass.png", ROOT / "art/tiles/sand.png", ROOT / "art/tiles/ground_atlas.png")
    out = ROOT / "track" / "ground_tiles.tres"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(tileset_tres(), encoding="utf-8", newline="\n")
    print("wrote art/tiles/ground_atlas.png and track/ground_tiles.tres")


if __name__ == "__main__":
    main()

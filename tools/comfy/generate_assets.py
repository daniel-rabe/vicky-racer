"""Produces every game asset listed in asset_manifest.json, using the frozen pipeline.json.

    python tools/comfy/generate_assets.py candidates [--only tree,coin]
    python tools/comfy/generate_assets.py variant-candidates [--only card_police]
    python tools/comfy/generate_assets.py pick tree 13
    python tools/comfy/generate_assets.py build [--only car_blue] [--force]
    python tools/comfy/generate_assets.py paint-sheet

`candidates` renders every candidate seed for sprites that have no seed yet and writes a
review sheet to docs/mockups/candidates/<id>.png; `variant-candidates` does the same for
Kontext variants (edits of another asset's master). `pick` pins the chosen seed in the
manifest, for either kind. `build` writes the final, game-sized PNGs into art/.

The manifest's `paints` section is the paint shop: every car in every palette colour, as a
Kontext recolour of the car's master, written as a card (art/ui/cards/paint/) and a race body
(art/cars/paint/). It expands into ordinary variants and copies (`expand`), so it builds like
everything else; `paint-sheet` lays all of them out for review.

Full-resolution masters (cut-out and raw) are kept in tools/comfy/masters/, outside
Godot's import, because recolours and card art are made from them, not from the
128 px sprites. The recipe is reproducible, so a master is only rendered once.
"""
import argparse
import io
import json
from pathlib import Path

from PIL import Image

import postprocess as pp
import recipe
from comfy_client import ComfyClient

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
MANIFEST_PATH = HERE / "asset_manifest.json"
MASTERS = HERE / "masters"
CANDIDATES = MASTERS / "candidates"
SHEETS = ROOT / "docs" / "mockups" / "candidates"
# Rotation (PIL degrees, counter-clockwise) that turns a sprite's facing into +X.
TO_PLUS_X = {"up": -90, "down": 90, "left": 180, "right": 0, None: 0}
GRASS = tuple(recipe.PIPELINE["ground"]["grass"]["base"])


def load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def save_manifest(manifest: dict) -> None:
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def expand(manifest: dict) -> dict:
    """The manifest with its `paints` section unrolled into variants and copies."""
    paints = manifest.get("paints")
    if not paints:
        return manifest
    variants, copies = list(manifest["variants"]), list(manifest["copies"])
    for car, source in paints["cars"].items():
        for colour, words in paints["palette"].items():
            key = f"{car}_{colour}"
            card_out = f"art/ui/cards/paint/{key}.png"
            body_out = f"art/cars/paint/{key}.png"
            reuse = paints.get("reuse", {}).get(key)
            if reuse:  # an existing asset already is this car in this colour
                copies.append({"id": f"paint_{key}", "source": reuse, "box": [312, 190], "out": card_out})
                copies.append({"id": f"paint_{key}_body", "source": reuse, "box": [128, 72], "out": body_out})
                continue
            variants.append({"id": f"paint_{key}", "source": source, "box": [312, 190], "out": card_out,
                             "seed": paints.get("seeds", {}).get(key, paints["seed"]),
                             "instruction": paints["instruction"].format(colour=words)})
            copies.append({"id": f"paint_{key}_body", "source": f"paint_{key}", "box": [128, 72], "out": body_out})
    return {**manifest, "variants": variants, "copies": copies}


def all_entries(manifest: dict) -> dict[str, dict]:
    entries = {}
    for section in ("sprites", "variants", "copies", "procedural"):
        for entry in manifest.get(section, []):
            entries[entry["id"]] = {**entry, "_section": section}
    return entries


def facing_of(entry: dict, entries: dict) -> str | None:
    """Variants and copies keep the orientation of the asset they were made from."""
    while "facing" not in entry and "source" in entry:
        entry = entries[entry["source"]]
    return entry.get("facing")


def render_sprite(client: ComfyClient, ref: str, entry: dict, seed: int) -> tuple[Image.Image, Image.Image]:
    """(cut-out, raw) for a sprite. A background (`size` set) has no cut-out: both are the picture.
    A building (`sketch` set) is Kontext's edit of its block sketch (pipeline.json `buildings`)."""
    if "sketch" in entry:
        buf = io.BytesIO()
        pp.building_sketch(entry["sketch"]).save(buf, "PNG")
        uploaded = client.upload_image(buf.getvalue(), f"vr_sketch_{entry['id']}.png")
        images = client.run(recipe.building_graph(uploaded, entry["subject"], entry["details"], seed))
        return (Image.open(io.BytesIO(images["save_cutout"][0])).convert("RGBA"),
                Image.open(io.BytesIO(images["save"][0])).convert("RGB"))
    if "size" in entry:
        images = client.run(recipe.background_graph(entry["subject"], seed, tuple(entry["size"]), ref))
        raw = Image.open(io.BytesIO(images["save"][0])).convert("RGB")
        return raw, raw
    images = client.run(recipe.sprite_graph(entry["subject"], seed, ref, prefix="vr_asset"))
    return (Image.open(io.BytesIO(images["save_cutout"][0])).convert("RGBA"),
            Image.open(io.BytesIO(images["save"][0])).convert("RGB"))


POST_STEPS = {"punch_hole": pp.punch_center_hole, "sticker": pp.sticker_border}


def finalize(master: Image.Image, entry: dict, entries: dict) -> Image.Image:
    if "size" in entry:
        return pp.cover(master, tuple(entry["box"]))
    for step in entry.get("post", []):
        master = POST_STEPS[step](master)
    turned = master.rotate(TO_PLUS_X[facing_of(entry, entries)], expand=True)
    fitted = pp.fit_sprite(turned, tuple(entry["box"]))
    # A building is placed by its picture's edges (its front on the pavement): no margin.
    return fitted.crop(fitted.getchannel("A").getbbox()) if "sketch" in entry else fitted


def write_art(img: Image.Image, rel: str) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"  wrote {rel} {img.size}", flush=True)


# --- commands -------------------------------------------------------------------------

def cmd_candidates(only: list[str] | None) -> None:
    manifest = load_manifest()
    entries = all_entries(manifest)
    pending = [e for e in manifest["sprites"] if e["seed"] is None and (not only or e["id"] in only)]
    if not pending:
        print("No sprites without a seed" + (f" among {only}" if only else "") + ".")
        return
    client = ComfyClient()
    client.check_alive()
    ref = recipe.upload_style_reference(client)
    CANDIDATES.mkdir(parents=True, exist_ok=True)
    SHEETS.mkdir(parents=True, exist_ok=True)
    for entry in pending:
        big, small = [], []
        for seed in manifest["candidate_seeds"]:
            cut_path = CANDIDATES / f"{entry['id']}_s{seed}.png"
            if cut_path.exists():
                cut = Image.open(cut_path).convert("RGBA")
            else:
                cut, raw = render_sprite(client, ref, entry, seed)
                cut.save(cut_path)
                raw.save(CANDIDATES / f"{entry['id']}_s{seed}_raw.png")
                print(f"  {entry['id']} seed {seed}", flush=True)
            big.append((cut, f"seed {seed}"))
            if "size" in entry:
                continue
            # Shown at final size on grass, scaled 2x so it is inspectable.
            tile = Image.new("RGB", (max(entry["box"]) + 32,) * 2, GRASS)
            sprite = finalize(cut, entry, entries)
            tile.paste(sprite, ((tile.width - sprite.width) // 2, (tile.height - sprite.height) // 2), sprite)
            small.append((tile.resize((tile.width * 2, tile.height * 2), Image.NEAREST), f"seed {seed} in game, 2x"))
        if "size" in entry:  # a background: the pictures themselves, two to a row
            pp.contact_sheet([(finalize(c, entry, entries), l) for c, l in big], 2, (768, 432),
                             f"{entry['id'].upper()}: CANDIDATES").save(SHEETS / f"{entry['id']}.png")
            print(f"sheet: docs/mockups/candidates/{entry['id']}.png", flush=True)
            continue
        top = pp.contact_sheet(big, len(big), (256, 256), f"{entry['id'].upper()}: CANDIDATES", checker=True)
        side = max(256, small[0][0].width)
        bottom = pp.contact_sheet(small, len(small), (side, side), "AT GAME SIZE ON GRASS (2x)")
        sheet = Image.new("RGB", (max(top.width, bottom.width), top.height + bottom.height), (40, 44, 52))
        sheet.paste(top, (0, 0))
        sheet.paste(bottom, (0, top.height))
        sheet.save(SHEETS / f"{entry['id']}.png")
        print(f"sheet: docs/mockups/candidates/{entry['id']}.png", flush=True)


def cmd_variant_candidates(only: list[str] | None) -> None:
    """Every candidate seed for variants without a seed, as one sheet per variant. Each cell
    shows the cut-out turned to face +X, as it will on a card and in the race, so a variant
    that came out pointing the wrong way is visible at a glance."""
    manifest = expand(load_manifest())
    entries = all_entries(manifest)
    pending = [e for e in manifest["variants"] if e["seed"] is None and (not only or e["id"] in only)]
    if not pending:
        print("No variants without a seed" + (f" among {only}" if only else "") + ".")
        return
    client = ComfyClient()
    client.check_alive()
    CANDIDATES.mkdir(parents=True, exist_ok=True)
    SHEETS.mkdir(parents=True, exist_ok=True)
    uploads = {}
    for entry in pending:
        source = entry["source"]
        if source not in uploads:
            uploads[source] = client.upload_image((MASTERS / f"{source}_raw.png").read_bytes(), f"vr_src_{source}.png")
        cells = []
        for seed in manifest["candidate_seeds"]:
            path = CANDIDATES / f"{entry['id']}_s{seed}.png"
            if not path.exists():
                images = client.run(recipe.variant_graph(uploads[source], entry["instruction"], seed, prefix="vr_variant"))
                Image.open(io.BytesIO(images["save_cutout"][0])).convert("RGBA").save(path)
                Image.open(io.BytesIO(images["save"][0])).convert("RGB").save(CANDIDATES / f"{entry['id']}_s{seed}_raw.png")
                print(f"  {entry['id']} seed {seed}", flush=True)
            cells.append((finalize(Image.open(path).convert("RGBA"), entry, entries), f"seed {seed} (facing +X)"))
        sheet = pp.contact_sheet(cells, len(cells), tuple(entry["box"]), f"{entry['id'].upper()}: CANDIDATES", checker=True)
        sheet.save(SHEETS / f"{entry['id']}.png")
        print(f"sheet: docs/mockups/candidates/{entry['id']}.png", flush=True)


def cmd_pick(asset_id: str, seed: int) -> None:
    manifest = load_manifest()
    if asset_id.startswith("paint_"):
        # A paint re-roll: pinned in paints.seeds; delete the old master so build re-renders it.
        key = asset_id[len("paint_"):]
        manifest["paints"].setdefault("seeds", {})[key] = seed
        save_manifest(manifest)
        for suffix in ("", "_raw"):
            (MASTERS / f"{asset_id}{suffix}.png").unlink(missing_ok=True)
        print(f"{asset_id}: seed {seed} pinned; run build --only {asset_id},{asset_id}_body")
        return
    entry = next((e for e in manifest["sprites"] + manifest["variants"] if e["id"] == asset_id), None)
    if entry is None:
        raise SystemExit(f"No sprite or variant called {asset_id!r}")
    candidate = CANDIDATES / f"{asset_id}_s{seed}.png"
    if candidate.exists():
        # Reproducible recipe: the candidate already IS the master for this seed.
        MASTERS.mkdir(parents=True, exist_ok=True)
        Image.open(candidate).save(MASTERS / f"{asset_id}.png")
        Image.open(CANDIDATES / f"{asset_id}_s{seed}_raw.png").save(MASTERS / f"{asset_id}_raw.png")
    entry["seed"] = seed
    save_manifest(manifest)
    print(f"{asset_id}: seed {seed} pinned")


def cmd_build(only: list[str] | None, force: bool) -> None:
    manifest = expand(load_manifest())
    entries = all_entries(manifest)
    wanted = lambda e: not only or e["id"] in only  # noqa: E731
    MASTERS.mkdir(parents=True, exist_ok=True)
    client = ref = None

    def comfy():
        nonlocal client, ref
        if client is None:
            client = ComfyClient()
            client.check_alive()
            ref = recipe.upload_style_reference(client)
        return client

    unpicked = [e["id"] for e in manifest["sprites"] if e["seed"] is None and wanted(e)]
    if unpicked:
        print(f"Skipping sprites with no seed yet: {', '.join(unpicked)} (run candidates, then pick)")

    for entry in manifest["sprites"]:
        if not wanted(entry) or entry["seed"] is None:
            continue
        master = MASTERS / f"{entry['id']}.png"
        if force or not master.exists():
            cut, raw = render_sprite(comfy(), ref, entry, entry["seed"])
            cut.save(master)
            raw.save(MASTERS / f"{entry['id']}_raw.png")
        write_art(finalize(Image.open(master), entry, entries), entry["out"])

    for entry in manifest["variants"]:
        if not wanted(entry) or entry["seed"] is None:
            continue
        master = MASTERS / f"{entry['id']}.png"
        if force or not master.exists():
            source_raw = MASTERS / f"{entry['source']}_raw.png"
            if not source_raw.exists():
                print(f"  {entry['id']}: source {entry['source']} has no master yet, skipped")
                continue
            c = comfy()
            uploaded = c.upload_image(source_raw.read_bytes(), f"vr_src_{entry['source']}.png")
            images = c.run(recipe.variant_graph(uploaded, entry["instruction"], entry["seed"], prefix="vr_variant"))
            Image.open(io.BytesIO(images["save_cutout"][0])).convert("RGBA").save(master)
            Image.open(io.BytesIO(images["save"][0])).convert("RGB").save(MASTERS / f"{entry['id']}_raw.png")
        write_art(finalize(Image.open(master), entry, entries), entry["out"])

    for entry in manifest["copies"]:
        source = MASTERS / f"{entry['source']}.png"
        if wanted(entry) and source.exists():
            write_art(finalize(Image.open(source), entry, entries), entry["out"])

    ground = recipe.PIPELINE["ground"]
    for entry in manifest["procedural"]:
        if not wanted(entry):
            continue
        if "fill" in entry:
            params = {k: v for k, v in ground[entry["fill"]].items() if not k.startswith("_")}
            params["base"] = tuple(params["base"])
            write_art(pp.flat_fill(ground["tile_px"], seed=len(entry["fill"]), **params), entry["out"])
        elif entry["kind"] == "kerb":
            k = ground["kerb"]
            write_art(pp.kerb_strip(4 * k["block"] * 2, k["thickness"], k["block"], tuple(k["red"]), tuple(k["cream"])), entry["out"])
        elif entry["kind"] == "chequer":
            write_art(pp.chequer(), entry["out"])


def cmd_paint_sheet() -> None:
    """Every car (rows) in every paint (columns), from the built cards, for review."""
    paints = load_manifest()["paints"]
    cells = []
    for car in paints["cars"]:
        for colour in paints["palette"]:
            path = ROOT / f"art/ui/cards/paint/{car}_{colour}.png"
            img = Image.open(path).convert("RGBA") if path.exists() else Image.new("RGBA", (312, 190))
            cells.append((img, f"{car} {colour}"))
    pp.contact_sheet(cells, len(paints["palette"]), (312, 190), "PAINT SHOP", checker=True) \
        .save(SHEETS / "paint_shop.png")
    print("sheet: docs/mockups/candidates/paint_shop.png")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    c = sub.add_parser("candidates", help="render candidate seeds for unpicked sprites")
    c.add_argument("--only", help="comma-separated asset ids")
    v = sub.add_parser("variant-candidates", help="render candidate seeds for unpicked variants")
    v.add_argument("--only", help="comma-separated asset ids")
    p = sub.add_parser("pick", help="pin a candidate seed")
    p.add_argument("asset_id")
    p.add_argument("seed", type=int)
    b = sub.add_parser("build", help="write final art into art/")
    b.add_argument("--only", help="comma-separated asset ids")
    b.add_argument("--force", action="store_true", help="re-render masters even if they exist")
    sub.add_parser("paint-sheet", help="review sheet of every car in every paint")
    args = parser.parse_args()
    only = args.only.split(",") if getattr(args, "only", None) else None
    if args.command == "candidates":
        cmd_candidates(only)
    elif args.command == "variant-candidates":
        cmd_variant_candidates(only)
    elif args.command == "paint-sheet":
        cmd_paint_sheet()
    elif args.command == "pick":
        cmd_pick(args.asset_id, args.seed)
    else:
        cmd_build(only, args.force)


if __name__ == "__main__":
    main()

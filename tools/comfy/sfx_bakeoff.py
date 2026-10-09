"""Bake-off for less metallic sound effects (2026-10-09).

    python tools/comfy/sfx_bakeoff.py render     # needs ComfyUI running
    python tools/comfy/sfx_bakeoff.py listen     # writes docs/mockups/sfx/bakeoff/index.html

Three probe sounds (wall_bump, engine_loop, town_ambience), four seeds per arm:

- NOW  the sound in the game today, cut the way `build` cuts it, for comparison.
- A    the same Stable Audio 3 medium_base, with a fixed recipe: a regular sampler instead of lcm,
       a lower cfg, prompts that ask for a real recording, and negatives against ringing tones.
- B    Stable Audio 3 Small-SFX, the variant made for effects (distilled: cfg 1, few steps).
- C    real CC0 recordings dropped into masters/sfx_cc0/<sound id>/ (wav, ogg or flac), if any.

Every arm goes through the same trim/loop step as the game, except for the stereo-to-mono step:
generate_sfx.to_mono() averages left and right, which on wide stereo cancels part of the sound
(town_ambience loses 4 dB). Here A, B and C use `mono()`, which only averages when the channels
agree and otherwise keeps the louder one. NOW keeps the old averaging, so the difference is heard.

Masters go to masters/sfx_bakeoff/ (not committed). Nothing in the game changes until a pick is
copied into sfx_manifest.json.
"""
import argparse
import html
import io
import json
from pathlib import Path

import numpy as np
import soundfile as sf

import generate_sfx as gs
from comfy_client import ComfyClient

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
MASTERS = HERE / "masters" / "sfx_bakeoff"
CC0 = HERE / "masters" / "sfx_cc0"
OUT = ROOT / "docs" / "mockups" / "sfx" / "bakeoff"
SEEDS = range(101, 105)
RATE = gs.RATE

NEGATIVE = ("music, melody, musical notes, tonal, ringing, metallic, bell, chime, synthesizer, electronic, beep, "
            "speech, voice, singing, distortion, clipping, low quality")

# Realistic wording: ask for a recording of the thing rather than a "cartoon sound effect".
PROMPTS = {
    "wall_bump": "a single soft dull thud of a small plastic toy car bumping into a rubber tyre, one short impact, "
                 "close microphone foley recording, natural, realistic, no ringing",
    "engine_loop": "steady idle hum of a small electric toy car motor and a tiny petrol go-kart engine at constant "
                   "medium revs, even pitch, close microphone field recording, natural, realistic",
    "town_ambience": "quiet small town park on a sunny morning, birdsong and sparrows chirping, light breeze in "
                     "the leaves, calm and continuous, no cars, no people, natural field recording, stereo",
}

ARMS = {
    "A": {"title": "Same model, fixed recipe", "checkpoint": "stable_audio_3_medium_base.safetensors",
          "steps": 50, "cfg": 4.5, "sampler": "euler", "scheduler": "simple"},
    "B": {"title": "Stable Audio 3 Small-SFX", "checkpoint": "small_sfx",  # resolved against ComfyUI's list
          "steps": 8, "cfg": 1.0, "sampler": "euler", "scheduler": "simple"},
}


def mono(data: np.ndarray) -> np.ndarray:
    """Average only when left and right agree; otherwise averaging comb-filters, so keep the louder side."""
    if data.ndim == 1:
        return data
    left, right = data[:, 0], data[:, 1]
    if np.corrcoef(left, right)[0, 1] > 0.9:
        return data.mean(axis=1)
    return left if np.mean(left ** 2) >= np.mean(right ** 2) else right


def master(arm: str, sid: str, seed: int) -> Path:
    return MASTERS / f"{sid}_{arm}_{seed}.flac"


def resolve_checkpoint(client: ComfyClient, name: str) -> str:
    if name.endswith(".safetensors"):
        return name
    names = client._get_json("/object_info/CheckpointLoaderSimple")[
        "CheckpointLoaderSimple"]["input"]["required"]["ckpt_name"][0]
    hits = [n for n in names if name in n.lower().replace("-", "_")]
    if not hits:
        raise SystemExit(f"no checkpoint matching '{name}' in ComfyUI: {names}")
    return hits[0]


def cmd_render(_args) -> None:
    client = ComfyClient()
    client.check_alive()
    base = gs.load_manifest()["recipe"]
    sounds = {s["id"]: s for s in gs.load_manifest()["sounds"]}
    for arm, spec in ARMS.items():
        recipe = {**base, **spec, "checkpoint": resolve_checkpoint(client, spec["checkpoint"]), "negative": NEGATIVE}
        for sid, prompt in PROMPTS.items():
            sound = {**sounds[sid], "id": f"bakeoff_{sid}_{arm}", "prompt": prompt, "negative": NEGATIVE}
            for seed in SEEDS:
                path = master(arm, sid, seed)
                if path.exists():
                    continue
                entry = client.wait(client.queue(gs.graph(recipe, sound, seed)))
                refs = [r for out in entry["outputs"].values() for r in out.get("audio", [])]
                data, rate = sf.read(io.BytesIO(client.fetch_image(refs[0])))
                path.parent.mkdir(parents=True, exist_ok=True)
                sf.write(path, data, rate)
                print(path.relative_to(ROOT))


# --- listening page ------------------------------------------------------------------------

def cut(x: np.ndarray, sound: dict) -> np.ndarray:
    if sound["kind"] == "loop":
        return np.tile(gs.loop(x, sound), 3)
    return gs.oneshot(x, sound)


def to_rate(x: np.ndarray, rate: int) -> np.ndarray:
    if rate == RATE:
        return x
    n = int(len(x) * RATE / rate)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x)


def write_mp3(name: str, x: np.ndarray) -> str:
    with sf.SoundFile(OUT / name, "w", RATE, 1, format="MP3", compression_level=0.2) as f:
        f.write(x.astype(np.float32))
    return name


def cmd_listen(_args) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sounds = {s["id"]: s for s in gs.load_manifest()["sounds"]}
    sections = []
    for sid in PROMPTS:
        sound = sounds[sid]
        rows = []
        data, _ = sf.read(gs.master_path(sid, sound["seed"]))
        rows.append(("NOW", f"in the game today (seed {sound['seed']}, old mono step)",
                     write_mp3(f"{sid}_now.mp3", cut(gs.to_mono(data), sound))))
        n = 1
        for arm, spec in ARMS.items():
            for seed in SEEDS:
                path = master(arm, sid, seed)
                if not path.exists():
                    continue
                data, rate = sf.read(path)
                rows.append((str(n), f"{arm}: {spec['title']}, seed {seed}",
                             write_mp3(f"{sid}_{n}.mp3", cut(to_rate(mono(data), rate), sound))))
                n += 1
        for path in sorted((CC0 / sid).glob("*")) if (CC0 / sid).is_dir() else []:
            if path.suffix.lower() not in (".wav", ".ogg", ".flac"):
                continue
            data, rate = sf.read(path)
            rows.append((str(n), f"C: CC0 recording {path.name}",
                         write_mp3(f"{sid}_{n}.mp3", cut(to_rate(mono(data), rate), sound))))
            n += 1
        items = "\n".join(
            f'<li><b>{num}</b> <span>{html.escape(note)}</span><audio controls preload="none" src="{f}"></audio></li>'
            for num, note, f in rows)
        sections.append(f"<h2>{sid}</h2><p class=p>{html.escape(PROMPTS[sid])}</p><ul>{items}</ul>")
    page = PAGE.replace("{sections}", "\n".join(sections))
    (OUT / "index.html").write_text(page, encoding="utf-8")
    print(OUT / "index.html")


PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Sound Bake-off</title>
<meta name="viewport" content="width=device-width, initial-scale=1"><style>
body{font:16px system-ui,sans-serif;background:#1d1f24;color:#eee;max-width:760px;margin:0 auto;padding:16px}
h2{margin-top:32px;color:#ffd970}.p{color:#aab;font-size:14px}ul{list-style:none;padding:0}
li{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:8px 0;border-bottom:1px solid #333}
li b{width:44px;font-size:20px;color:#7fd0ff}li span{flex:1;min-width:200px;font-size:14px}audio{width:280px}
</style></head><body><h1>Less metallic sounds</h1>
<p>Each sound plays the way the game uses it; loops repeat three times so you can hear the seam.
<b>NOW</b> is what the game has today. Tell Claude the numbers you like, for example
"bump 3, engine 6, town 2", or "none" for a sound.</p>
{sections}</body></html>"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("render").set_defaults(func=cmd_render)
    sub.add_parser("listen").set_defaults(func=cmd_listen)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

"""Sound effects for the game, generated with Stable Audio 3 through local ComfyUI.

    python tools/comfy/generate_sfx.py candidates [--only skid_loop,coin]
    python tools/comfy/generate_sfx.py pick skid_loop 3
    python tools/comfy/generate_sfx.py build [--only coin]

`candidates` renders `recipe.candidates` seeds per sound that has no pinned seed yet,
keeps the raw FLACs in tools/comfy/masters/sfx/ and writes a spectrogram + waveform review
sheet to docs/mockups/sfx/<id>.png. `pick` pins a seed in sfx_manifest.json. `build`
renders each pinned seed (reusing the cached master) and writes the game-ready mono 16-bit
WAVs into art/sfx/: one-shots trimmed and faded, loops cut from their steadiest stretch and
cross-faded so they repeat without a click. Two beeps are synthesised rather than
generated (see the manifest).

Like the art, sound is a build-time product: the WAVs are committed and the game never
talks to ComfyUI. The recipe is deterministic, so a pinned seed fully defines a sound.
"""
import argparse
import io
import json
from pathlib import Path

import numpy as np
import soundfile as sf
from PIL import Image, ImageDraw

from comfy_client import ComfyClient
import derive_sfx

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
MANIFEST_PATH = HERE / "sfx_manifest.json"
MASTERS = HERE / "masters" / "sfx"
SHEETS = ROOT / "docs" / "mockups" / "sfx"
RATE = 44100
FIRST_SEED = 101


def load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def save_manifest(manifest: dict) -> None:
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# --- generation ----------------------------------------------------------------------------

def graph(recipe: dict, sound: dict, seed: int) -> dict:
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": recipe["checkpoint"]}},
        "2": {"class_type": "CLIPLoader", "inputs": {
            "clip_name": recipe["text_encoder"], "type": "stable_audio", "device": "default"}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"text": sound["prompt"], "clip": ["2", 0]}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {
            "text": sound.get("negative", recipe["negative"]), "clip": ["2", 0]}},
        "5": {"class_type": "EmptyLatentAudio", "inputs": {"seconds": sound["seconds"], "batch_size": 1}},
        "6": {"class_type": "KSampler", "inputs": {
            "model": ["1", 0], "positive": ["3", 0], "negative": ["4", 0], "latent_image": ["5", 0],
            "seed": seed, "steps": recipe["steps"], "cfg": recipe["cfg"],
            "sampler_name": recipe["sampler"], "scheduler": recipe["scheduler"], "denoise": 1.0}},
        "7": {"class_type": "VAEDecodeAudio", "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {"class_type": "SaveAudio", "inputs": {"audio": ["7", 0], "filename_prefix": f"vicky_sfx/{sound['id']}"}},
    }


def master_path(sound_id: str, seed: int) -> Path:
    return MASTERS / f"{sound_id}_{seed}.flac"


def render(client: ComfyClient, recipe: dict, sound: dict, seed: int) -> Path:
    path = master_path(sound["id"], seed)
    if path.exists():
        return path
    entry = client.wait(client.queue(graph(recipe, sound, seed)))
    refs = [r for out in entry["outputs"].values() for r in out.get("audio", [])]
    data, rate = sf.read(io.BytesIO(client.fetch_image(refs[0])))
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, data, rate)
    return path


# --- post-processing -----------------------------------------------------------------------

def to_mono(data: np.ndarray) -> np.ndarray:
    return data.mean(axis=1) if data.ndim > 1 else data


def envelope(x: np.ndarray, window: int = 441) -> np.ndarray:
    """RMS over ~10 ms windows, one value per sample."""
    padded = np.pad(x ** 2, (window // 2, window - window // 2 - 1), mode="edge")
    return np.sqrt(np.convolve(padded, np.ones(window) / window, mode="valid"))


def fade(x: np.ndarray, fade_in: float, fade_out: float) -> np.ndarray:
    x = x.copy()
    n_in, n_out = int(fade_in * RATE), int(fade_out * RATE)
    if n_in:
        x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    if n_out:
        x[-n_out:] *= np.linspace(1.0, 0.0, n_out) ** 2
    return x


def normalise(x: np.ndarray, peak_db: float) -> np.ndarray:
    return x / max(np.abs(x).max(), 1e-9) * 10 ** (peak_db / 20)


def oneshot(x: np.ndarray, sound: dict) -> np.ndarray:
    """From the first sound above the noise floor, at most max_seconds, ending in a fade."""
    env = envelope(x)
    if env.max() <= 1e-6:
        raise SystemExit(f"{sound['id']}: the clip is silent - pick another seed")
    loud = np.nonzero(env > env.max() * 10 ** (-30 / 20))[0]
    start = max(loud[0] - int(0.005 * RATE), 0)
    end = min(loud[-1], start + int(sound["max_seconds"] * RATE))
    clip = x[start:end]
    return normalise(fade(clip, 0.003, min(0.08, len(clip) / RATE / 3)), sound["peak_db"])


def loop(x: np.ndarray, sound: dict) -> np.ndarray:
    """The steadiest loop_seconds of the clip, its tail cross-faded into its head."""
    length = int(sound["loop_seconds"] * RATE)
    overlap = int(0.25 * RATE)
    span = length + overlap
    if len(x) < span + RATE:
        raise SystemExit(f"{sound['id']}: {len(x) / RATE:.1f}s clip is too short for a "
                         f"{sound['loop_seconds']}s loop; raise 'seconds' in the manifest")
    env = envelope(x, 2205)
    # Skip the first and last half second, where generated clips swell in and die out.
    best, best_score = None, np.inf
    for start in range(int(0.5 * RATE), len(x) - span - int(0.5 * RATE), int(0.05 * RATE)):
        e = env[start:start + span]
        score = e.std() / max(e.mean(), 1e-9) - 0.2 * e.mean() / env.max()
        if score < best_score:
            best, best_score = start, score
    seg = x[best:best + span]
    body = seg[:length].copy()
    t = np.linspace(0.0, np.pi / 2, overlap)
    # Equal-power cross-fade: the segment's continuation fades out over the loop's head.
    body[:overlap] = seg[length:] * np.cos(t) + body[:overlap] * np.sin(t)
    return normalise(body, sound["peak_db"])


def synth_beep(spec: dict) -> np.ndarray:
    """A clean, friendly beep: sine plus a little octave, quick attack, smooth release."""
    t = np.arange(int(spec["seconds"] * RATE)) / RATE
    tone = np.sin(2 * np.pi * spec["freq"] * t) + 0.25 * np.sin(4 * np.pi * spec["freq"] * t)
    env = np.minimum(1.0, t / 0.008) * np.exp(-t * 3.0 / spec["seconds"])
    return normalise(fade(tone * env, 0.0, 0.03), spec["peak_db"])


def write_wav(x: np.ndarray, out: str) -> None:
    path = ROOT / out
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, x.astype(np.float32), RATE, subtype="PCM_16")


# --- review sheets -------------------------------------------------------------------------

def spectrogram(x: np.ndarray, w: int = 640, h: int = 180) -> Image.Image:
    n = 2048
    x = np.pad(x, (0, max(0, n - len(x))))
    hop = max(1, (len(x) - n) // w)
    win = np.hanning(n)
    frames = np.array([np.abs(np.fft.rfft(x[i * hop:i * hop + n] * win))
                       for i in range(w) if i * hop + n <= len(x)])
    s = 20 * np.log10(frames.T + 1e-6)
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    rows = np.searchsorted(freqs, np.geomspace(40, 16000, h)[::-1]).clip(0, len(freqs) - 1)
    s = ((s[rows] - (s.max() - 80)) / 80).clip(0, 1)
    rgb = np.stack([s ** 0.7 * 255, s ** 1.5 * 200, (1 - s) * s * 4 * 255], -1).astype(np.uint8)
    spec = Image.fromarray(rgb).resize((w, h))
    out = Image.new("RGB", (w, h + 50), (20, 20, 24))
    out.paste(spec, (0, 0))
    draw = ImageDraw.Draw(out)
    step = len(x) / w
    for px in range(w):
        a = float(np.abs(x[int(px * step):int((px + 1) * step) + 1]).max(initial=0.0))
        draw.line([(px, h + 25 - a * 24), (px, h + 25 + a * 24)], fill=(120, 200, 255))
    return out


def review_sheet(sound: dict, seeds: list[int]) -> Path:
    tiles = []
    for seed in seeds:
        data, _ = sf.read(master_path(sound["id"], seed))
        tiles.append((seed, spectrogram(to_mono(data))))
    sheet = Image.new("RGB", (660, 40 + len(tiles) * 254), (40, 40, 44))
    draw = ImageDraw.Draw(sheet)
    draw.text((10, 10), f"{sound['id']}: {sound['prompt'][:100]}", fill=(255, 255, 255))
    for i, (seed, tile) in enumerate(tiles):
        draw.text((10, 34 + i * 254), f"seed {seed}", fill=(255, 220, 120))
        sheet.paste(tile, (10, 50 + i * 254))
    SHEETS.mkdir(parents=True, exist_ok=True)
    path = SHEETS / f"{sound['id']}.png"
    sheet.save(path)
    return path


# --- commands ------------------------------------------------------------------------------

def selected(manifest: dict, only: str | None) -> list[dict]:
    wanted = set(only.split(",")) if only else None
    return [s for s in manifest["sounds"] if wanted is None or s["id"] in wanted]


def cmd_candidates(args) -> None:
    manifest = load_manifest()
    recipe = manifest["recipe"]
    client = ComfyClient()
    client.check_alive()
    for sound in selected(manifest, args.only):
        if ("seed" in sound and not args.only) or sound["kind"] == "derived":
            continue
        seeds = list(range(FIRST_SEED, FIRST_SEED + sound.get("candidates", recipe["candidates"])))
        for seed in seeds:
            render(client, recipe, sound, seed)
        print(f"{sound['id']}: {review_sheet(sound, seeds).relative_to(ROOT)}")


def cmd_pick(args) -> None:
    manifest = load_manifest()
    for sound in manifest["sounds"]:
        if sound["id"] == args.id:
            sound["seed"] = args.seed
            save_manifest(manifest)
            print(f"{args.id}: seed {args.seed}")
            return
    raise SystemExit(f"no sound {args.id}")


def cmd_build(args) -> None:
    manifest = load_manifest()
    recipe = manifest["recipe"]
    client = None
    for sound in selected(manifest, args.only):
        if sound.get("seed") is None:
            print(f"{sound['id']}: no seed picked yet, skipped")
            continue
        if sound["kind"] == "derived":  # cut from approved masters (derive_sfx.py), not generated
            x, _ = derive_sfx.derive(sound, sound["seed"])  # already shaped, levelled and faded
            write_wav(x, sound["out"])
            print(f"{sound['id']}: {sound['out']} ({len(x) / RATE:.2f}s, derived from {sound['source']})")
            continue
        path = master_path(sound["id"], sound["seed"])
        if not path.exists():
            client = client or ComfyClient()
            render(client, recipe, sound, sound["seed"])
        data, rate = sf.read(path)
        assert rate == RATE, f"{path.name}: expected {RATE} Hz, got {rate}"
        x = to_mono(data)
        x = loop(x, sound) if sound["kind"] == "loop" else oneshot(x, sound)
        write_wav(x, sound["out"])
        print(f"{sound['id']}: {sound['out']} ({len(x) / RATE:.2f}s)")
    for spec in manifest["synth"]:
        if args.only and spec["id"] not in args.only.split(","):
            continue
        write_wav(synth_beep(spec), spec["out"])
        print(f"{spec['id']}: {spec['out']} (synthesised)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("candidates")
    p.add_argument("--only")
    p.set_defaults(func=cmd_candidates)
    p = sub.add_parser("pick")
    p.add_argument("id")
    p.add_argument("seed", type=int)
    p.set_defaults(func=cmd_pick)
    p = sub.add_parser("build")
    p.add_argument("--only")
    p.set_defaults(func=cmd_build)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

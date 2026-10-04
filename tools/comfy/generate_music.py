"""Music for the game, generated with Stable Audio 3 through local ComfyUI.

    python tools/comfy/generate_music.py candidates [--only menu,podium]
    python tools/comfy/generate_music.py pick race_beach 104
    python tools/comfy/generate_music.py build [--only menu]
    python tools/comfy/generate_music.py listen

`candidates` renders `recipe.candidates` seeds per piece that has no pinned seed yet, keeps
the raw FLACs in tools/comfy/masters/music/, cuts each one into its loop exactly as `build`
would, scores it and writes a spectrogram sheet to docs/mockups/music/<id>.png. `pick` pins a
seed in music_manifest.json. `build` writes the game-ready stereo Ogg Vorbis files into
art/music/ and one MusicPiece resource per piece into game/configs/music/. `listen` writes
MP3 previews of every candidate and an HTML page to pick them by ear (docs/mockups/music/).

A looping piece is cut to a whole number of bars: the loop length is the prompted tempo's
`bars` bars, refined against the music itself, and the loop starts where the music `bars`
later sounds most like it does there. The file keeps `intro_bars` bars of lead-in before the
loop; the game plays from the top and jumps back to `loop_offset` (in the .tres) at the end.
The last 60 ms before the jump are cross-faded with the 60 ms before the loop start, so the
seam is the same music both ways. Every loop gets a seam check: the spectral jump across the
seam must be no bigger than the music's own jumps from beat to beat.

Like the SFX, music is a build-time product: the game never talks to ComfyUI.
"""
import argparse
import io
import json
import shutil
from pathlib import Path

import numpy as np
import soundfile as sf
from PIL import Image, ImageDraw

import generate_sfx as sfx
from comfy_client import ComfyClient

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
MANIFEST_PATH = HERE / "music_manifest.json"
MASTERS = HERE / "masters" / "music"
SHEETS = ROOT / "docs" / "mockups" / "music"
CONFIGS = ROOT / "game" / "configs" / "music"
RATE = 44100
FIRST_SEED = 101
HOP = 512
XFADE = int(0.06 * RATE)


def load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def save_manifest(manifest: dict) -> None:
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def master_path(piece_id: str, seed: int) -> Path:
    return MASTERS / f"{piece_id}_{seed}.flac"


def render(client: ComfyClient, recipe: dict, piece: dict, seed: int) -> Path:
    path = master_path(piece["id"], seed)
    if path.exists():
        return path
    graph = sfx.graph(recipe, piece, seed)
    graph["8"]["inputs"]["filename_prefix"] = f"vicky_music/{piece['id']}"
    entry = client.wait(client.queue(graph))
    refs = [r for out in entry["outputs"].values() for r in out.get("audio", [])]
    data, rate = sf.read(io.BytesIO(client.fetch_image(refs[0])))
    assert rate == RATE, f"expected {RATE} Hz, got {rate}"
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, data, rate)
    return path


def read_stereo(path: Path) -> np.ndarray:
    data, _ = sf.read(path, always_2d=True)
    return data if data.shape[1] == 2 else np.repeat(data[:, :1], 2, axis=1)


# --- analysis ------------------------------------------------------------------------------

def bands(x: np.ndarray, n: int = 2048, count: int = 48) -> np.ndarray:
    """Log-magnitude in `count` log-spaced bands, one row per HOP samples."""
    win = np.hanning(n)
    starts = range(0, len(x) - n, HOP)
    spec = np.array([np.abs(np.fft.rfft(x[i:i + n] * win)) for i in starts])
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    edges = np.searchsorted(freqs, np.geomspace(50, 16000, count + 1))
    out = np.stack([spec[:, a:max(b, a + 1)].mean(1) for a, b in zip(edges[:-1], edges[1:])], 1)
    return np.log1p(out * 20)


def similarity(f: np.ndarray, a: int, b: int, width: int) -> float:
    """Mean cosine similarity of the frames around a and around b."""
    p, q = f[a - width:a + width], f[b - width:b + width]
    num = (p * q).sum(1)
    den = np.linalg.norm(p, axis=1) * np.linalg.norm(q, axis=1) + 1e-9
    return float((num / den).mean())


def tempo(f: np.ndarray) -> float:
    flux = np.maximum(np.diff(f, axis=0), 0).sum(1)
    flux = np.maximum(flux - np.convolve(flux, np.ones(16) / 16, mode="same"), 0)
    flux -= flux.mean()
    ac = np.correlate(flux, flux, "full")[len(flux) - 1:]
    lags = np.arange(1, len(ac))
    bpm = 60 * RATE / HOP / lags
    keep = (bpm > 70) & (bpm < 190)
    return float(bpm[keep][np.argmax(ac[1:][keep])])


def find_loop(x: np.ndarray, piece: dict) -> dict:
    """The loop start and length in samples (see the module doc) and how well it fits."""
    mono = x.mean(1)
    f = bands(mono)
    beat = 60.0 / piece["bpm"] * RATE
    nominal = piece["bars"] * 4 * beat
    width = int(RATE / HOP)  # compare one second either side
    margin = int(2 * RATE / HOP)
    # 1. The exact loop length: the lag within half a percent whose frames match best.
    lo, hi = int(nominal * 0.995 / HOP), int(nominal * 1.005 / HOP) + 1
    usable = len(f) - hi - margin
    if usable <= margin:
        raise SystemExit(f"{piece['id']}: {len(x) / RATE:.0f}s is too short for {piece['bars']} bars")
    rows = np.arange(margin, usable)
    scores = []
    for lag in range(lo, hi + 1):
        p, q = f[rows], f[rows + lag]
        scores.append(((p * q).sum(1) / (np.linalg.norm(p, axis=1) * np.linalg.norm(q, axis=1) + 1e-9)).mean())
    lag = lo + int(np.argmax(scores))
    # 2. The loop start: the beat whose surroundings match the music one loop later best.
    intro = piece.get("intro_bars", 0) * 4 * beat
    first = max(margin * HOP, int(intro + 0.5 * RATE))
    best, best_score = None, -1.0
    start = first
    while start / HOP + lag + width < len(f) - margin // 2:
        s = similarity(f, int(start / HOP), int(start / HOP) + lag, width)
        if s > best_score:
            best, best_score = int(start), s
        start += beat
    # 3. To the sample: line the waveform up across the seam within half a frame.
    length = lag * HOP
    probe = mono[best - 2048:best + 2048]
    shifts = range(-HOP, HOP + 1)
    corr = [float(np.dot(probe, mono[best + length + d - 2048:best + length + d + 2048])) for d in shifts]
    length += shifts[int(np.argmax(corr))]
    return {"start": best, "length": length, "match": best_score,
            "bpm_heard": tempo(f), "bars_seconds": nominal / RATE}


def cut(x: np.ndarray, piece: dict, loop: dict) -> tuple[np.ndarray, int]:
    """The game file: lead-in plus one loop, its end cross-faded into the music before the loop
    start. Returns the audio and the loop offset in samples."""
    s, length = loop["start"], loop["length"]
    beat = 60.0 / piece["bpm"] * RATE
    a = max(0, int(round(s - piece.get("intro_bars", 0) * 4 * beat)))
    y = x[a:s + length].copy()
    t = np.linspace(0.0, np.pi / 2, XFADE)[:, None]
    # Just before the jump, fade from "what comes next" into "what came before the loop".
    y[-XFADE:] = x[s + length - XFADE:s + length] * np.cos(t) + x[s - XFADE:s] * np.sin(t)
    if a > 0:
        y[:int(0.01 * RATE)] *= np.linspace(0.0, 1.0, int(0.01 * RATE))[:, None]
    return y, s - a


def seam_check(y: np.ndarray, offset: int) -> float:
    """The spectral jump across the seam as played (end -> loop offset), divided by the 95th
    percentile of the music's own frame-to-frame jumps. At most 1.0 passes."""
    n = 8 * HOP
    played = np.concatenate([y[-n:], y[offset:offset + n]]).mean(1)
    whole = bands(y.mean(1))
    jumps = np.abs(np.diff(whole, axis=0)).sum(1)
    seam = bands(played)
    middle = len(seam) // 2
    seam_jump = np.abs(np.diff(seam, axis=0)).sum(1)[middle - 2:middle + 2].max()
    return float(seam_jump / np.percentile(jumps, 95))


def sting(x: np.ndarray, piece: dict) -> np.ndarray:
    mono = x.mean(1)
    env = sfx.envelope(mono)
    loud = np.nonzero(env > env.max() * 10 ** (-30 / 20))[0]
    a = max(loud[0] - int(0.005 * RATE), 0)
    b = min(loud[-1], a + int(piece["max_seconds"] * RATE))
    # End at the first fifth of a second of quiet: the chord has died away, and whatever the
    # model started after it is not part of the sting.
    quiet = env < env.max() * 10 ** (-35 / 20)
    run = int(0.2 * RATE)
    counts = np.convolve(quiet.astype(np.int32), np.ones(run, dtype=np.int32), mode="valid")
    gaps = np.nonzero(counts[a:] == run)[0]
    if len(gaps):
        b = min(b, a + int(gaps[0]) + run // 4)
    y = x[a:b].copy()
    n_out = int(min(0.4, (b - a) / RATE / 3) * RATE)
    y[:int(0.003 * RATE)] *= np.linspace(0.0, 1.0, int(0.003 * RATE))[:, None]
    y[-n_out:] *= (np.linspace(1.0, 0.0, n_out) ** 2)[:, None]
    return y


def loudness(y: np.ndarray, recipe: dict) -> np.ndarray:
    """To the target RMS, then a gentle limiter keeps the peaks under the ceiling."""
    rms = np.sqrt(np.mean(y ** 2))
    y = y * 10 ** (recipe["rms_db"] / 20) / max(rms, 1e-9)
    ceiling = 10 ** (recipe["peak_db"] / 20)
    knee = ceiling * 0.8
    over = np.abs(y) > knee
    y[over] = np.sign(y[over]) * (knee + (ceiling - knee) * np.tanh((np.abs(y[over]) - knee) / (ceiling - knee)))
    return y


def process(piece: dict, recipe: dict, seed: int) -> dict:
    """Cut, level and score one master the way `build` uses it."""
    x = read_stereo(master_path(piece["id"], seed))
    clipped = int((np.abs(x) >= 0.999).sum())
    if piece.get("kind") == "sting":
        y = loudness(sting(x, piece), recipe)
        return {"seed": seed, "audio": y, "offset": None, "clipped": clipped, "score": -clipped,
                "summary": f"{len(y) / RATE:.1f}s, {clipped} clipped samples"}
    loop = find_loop(x, piece)
    y, offset = cut(x, piece, loop)
    seam = seam_check(y, offset)
    on_tempo = min(abs(loop["bpm_heard"] / piece["bpm"] - k) for k in (0.5, 1.0, 2.0)) < 0.03
    score = loop["match"] - 0.3 * max(0.0, seam - 1.0) - 0.0005 * clipped - (0.0 if on_tempo else 1.0)
    return {"seed": seed, "audio": loudness(y, recipe), "offset": offset, "loop": loop, "seam": seam,
            "clipped": clipped, "on_tempo": on_tempo, "score": score,
            "summary": (f"tempo {loop['bpm_heard']:.0f}{'' if on_tempo else ' OFF'}, loop match {loop['match']:.3f}, "
                        f"seam {seam:.2f}{'' if seam <= 1.0 else ' FAIL'}, {clipped} clipped, "
                        f"loop {loop['length'] / RATE:.2f}s from {offset / RATE:.2f}s")}


# --- output --------------------------------------------------------------------------------

def write_compressed(path: Path, y: np.ndarray, **kwargs) -> None:
    """Ogg or MP3 in one-second blocks: libsndfile's encoders kill the process on one big write."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with sf.SoundFile(path, "w", RATE, 2, **kwargs) as f:
        for i in range(0, len(y), RATE):
            f.write(y[i:i + RATE].astype(np.float32))


def write_ogg(y: np.ndarray, out: str) -> None:
    write_compressed(ROOT / out, y, format="OGG", subtype="VORBIS", compression_level=0.25)


def write_piece_resource(piece: dict, result: dict) -> Path:
    """game/configs/music/<id>.tres: the stream and where its loop starts."""
    CONFIGS.mkdir(parents=True, exist_ok=True)
    loops = result["offset"] is not None
    lines = [
        '[gd_resource type="Resource" script_class="MusicPiece" load_steps=3 format=3]',
        "",
        '[ext_resource type="Script" path="res://game/configs/music_piece.gd" id="1_script"]',
        f'[ext_resource type="AudioStream" path="res://{piece["out"]}" id="2_stream"]',
        "",
        "[resource]",
        'script = ExtResource("1_script")',
        f'id = &"{piece["id"]}"',
        'stream = ExtResource("2_stream")',
        f"loops = {'true' if loops else 'false'}",
        f"loop_offset = {result['offset'] / RATE if loops else 0.0:.6f}",
        f"bpm = {float(piece.get('bpm', 0)):.1f}",
        "",
    ]
    path = CONFIGS / f"{piece['id']}.tres"
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return path


def sheet(piece: dict, results: list[dict], picked: int | None) -> Path:
    tiles = []
    for r in results:
        tile = sfx.spectrogram(r["audio"].mean(1))
        if r["offset"] is not None:
            draw = ImageDraw.Draw(tile)
            px = int(r["offset"] / len(r["audio"]) * tile.width)
            draw.line([(px, 0), (px, tile.height)], fill=(255, 255, 255), width=2)
        tiles.append((r, tile))
    img = Image.new("RGB", (660, 40 + len(tiles) * 254), (40, 40, 44))
    draw = ImageDraw.Draw(img)
    draw.text((10, 10), f"{piece['id']}: {piece['prompt'][:100]}", fill=(255, 255, 255))
    for i, (r, tile) in enumerate(tiles):
        mark = "  <- picked" if r["seed"] == picked else ""
        draw.text((10, 34 + i * 254), f"seed {r['seed']}: {r['summary']}{mark}", fill=(255, 220, 120))
        img.paste(tile, (10, 50 + i * 254))
    SHEETS.mkdir(parents=True, exist_ok=True)
    path = SHEETS / f"{piece['id']}.png"
    img.save(path)
    return path


# --- commands ------------------------------------------------------------------------------

def selected(manifest: dict, only: str | None) -> list[dict]:
    wanted = set(only.split(",")) if only else None
    return [p for p in manifest["pieces"] if wanted is None or p["id"] in wanted]


def candidate_seeds(recipe: dict) -> list[int]:
    return list(range(FIRST_SEED, FIRST_SEED + recipe["candidates"]))


def cmd_candidates(args) -> None:
    manifest = load_manifest()
    recipe = manifest["recipe"]
    client = ComfyClient()
    client.check_alive()
    for piece in selected(manifest, args.only):
        if "seed" in piece and not args.only:
            continue
        results = []
        for seed in candidate_seeds(recipe):
            render(client, recipe, piece, seed)
            results.append(process(piece, recipe, seed))
        best = max(results, key=lambda r: r["score"])
        for r in results:
            print(f"  {piece['id']} {r['seed']}: {r['summary']}{'  <- best' if r is best else ''}")
        print(f"{piece['id']}: {sheet(piece, results, piece.get('seed')).relative_to(ROOT)}")


def cmd_pick(args) -> None:
    manifest = load_manifest()
    for piece in manifest["pieces"]:
        if piece["id"] == args.id:
            piece["seed"] = args.seed
            save_manifest(manifest)
            print(f"{args.id}: seed {args.seed}")
            return
    raise SystemExit(f"no piece {args.id}")


def cmd_build(args) -> None:
    manifest = load_manifest()
    recipe = manifest["recipe"]
    client = None
    failed = []
    for piece in selected(manifest, args.only):
        if "seed" not in piece:
            print(f"{piece['id']}: no seed picked yet, skipped")
            continue
        if not master_path(piece["id"], piece["seed"]).exists():
            client = client or ComfyClient()
            render(client, recipe, piece, piece["seed"])
        result = process(piece, recipe, piece["seed"])
        if result["offset"] is not None and result["seam"] > 1.0:
            failed.append(piece["id"])
        write_ogg(result["audio"], piece["out"])
        write_piece_resource(piece, result)
        print(f"{piece['id']}: {piece['out']} ({result['summary']})")
    if failed:
        raise SystemExit(f"seam check failed: {', '.join(failed)} - pick another seed")


def cmd_listen(args) -> None:
    """MP3 previews of every candidate: the lead-in, the loop, then the seam and 8 s more,
    so the jump back can be heard. Plus an index.html to compare them."""
    manifest = load_manifest()
    recipe = manifest["recipe"]
    out = SHEETS / "listen"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    sections = []
    for piece in manifest["pieces"]:
        rows = []
        for seed in candidate_seeds(recipe):
            if not master_path(piece["id"], seed).exists():
                continue
            r = process(piece, recipe, seed)
            y = r["audio"]
            if r["offset"] is not None:
                y = np.concatenate([y, y[r["offset"]:r["offset"] + 8 * RATE]])
            name = f"{piece['id']}_{seed}.mp3"
            write_compressed(out / name, y, format="MP3", compression_level=0.45)
            seam = "" if r["offset"] is None else f" · the seam is at {(len(r['audio'])) / RATE:.0f}s"
            pick = " <b>← in the game</b>" if piece.get("seed") == seed else ""
            rows.append(f'<li><span>seed {seed}{pick}<small>{r["summary"]}{seam}</small></span>'
                        f'<audio controls preload="none" src="{name}"></audio></li>')
        sections.append(f"<section><h2>{piece['id']} <small>{piece['use']}</small></h2>"
                        f"<p>{piece['prompt']}</p><ul>{''.join(rows)}</ul></section>")
    (out / "index.html").write_text(LISTEN_PAGE.replace("{sections}", "\n".join(sections)), encoding="utf-8")
    print(f"{(out / 'index.html').relative_to(ROOT)}")


LISTEN_PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Vicky Racer Music</title>
<style>
:root { --bg: #f6f3ec; --card: #fff; --ink: #1d2430; --dim: #5d6673; --accent: #d9481e; }
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #14181f; --card: #1e242d; --ink: #e9edf2; --dim: #9aa4b1; --accent: #ff8a5c; } }
:root[data-theme="dark"] { --bg: #14181f; --card: #1e242d; --ink: #e9edf2; --dim: #9aa4b1; --accent: #ff8a5c; }
body { margin: 0; padding: 24px 16px; background: var(--bg); color: var(--ink); font: 16px/1.45 system-ui, sans-serif; }
main { max-width: 860px; margin: 0 auto; }
h1 { margin: 0 0 4px; } h2 { margin: 0 0 4px; } h2 small { color: var(--dim); font-weight: 400; font-size: 15px; }
section { background: var(--card); border-radius: 12px; padding: 16px; margin: 16px 0; }
section > p { color: var(--dim); font-size: 14px; margin: 0 0 8px; }
ul { list-style: none; padding: 0; margin: 0; }
li { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; justify-content: space-between; padding: 8px 0; border-top: 1px solid color-mix(in srgb, var(--dim) 25%, transparent); }
li span { flex: 1 1 260px; } li small { display: block; color: var(--dim); font-size: 13px; }
li b { color: var(--accent); }
audio { width: min(100%, 340px); }
code { background: color-mix(in srgb, var(--dim) 18%, transparent); padding: 1px 5px; border-radius: 4px; }
</style></head><body><main>
<h1>Vicky Racer music</h1>
<p>Every candidate as the game would play it: the lead-in, one loop, then the jump back to the loop start
and 8 more seconds, so the seam can be heard. To swap one: <code>python tools/comfy/generate_music.py pick &lt;piece&gt; &lt;seed&gt;</code>,
then <code>build</code>.</p>
{sections}
</main></body></html>
"""


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
    p = sub.add_parser("listen")
    p.set_defaults(func=cmd_listen)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

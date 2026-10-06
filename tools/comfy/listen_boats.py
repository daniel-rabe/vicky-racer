"""Listening page for the Phase 20 boat sounds and music (DESIGN.md §20.6).

    python tools/comfy/listen_boats.py

Every candidate is cut the way `build` cuts it: one-shots trimmed and faded, loops cut to their
steadiest stretch and played three times round so the seam can be heard, music as the game
plays it (lead-in, one loop, the jump back). MP3 previews and an index.html go to
docs/mockups/sfx/listen_boats/. The suggested seed is a measurement, not a listen: for a loop
the steadiest level, for a one-shot the most single event, for music the score generate_music
already gives. The ear decides.
"""
import html
from pathlib import Path

import numpy as np
import soundfile as sf

import generate_music as gm
import derive_sfx
import generate_sfx as gs

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "mockups" / "sfx" / "listen_boats"
SFX = ["splash", "ramp_whoosh", "horn_pirate", "motor_loop", "jet_loop", "hover_loop", "wake_loop", "wave_ambience", "boat_bump",
       "horn_boat", "horn_tugboat", "horn_swan", "horn_steamer"]
MUSIC = ["race_river", "race_lagoon"]
USE = {
    "motor_loop": "Speedboat, tugboat, pirate ship, steamer, duck, swan: the motor, pitched by speed",
    "jet_loop": "Jet ski and banana boat motor", "hover_loop": "Hovercraft fan",
    "wake_loop": "Water rushing past, louder when gliding wide", "wave_ambience": "Under every boat race",
    "splash": "Landing a jump", "ramp_whoosh": "Taking off from a ramp", "boat_bump": "Bumping a buoy, rock or boat",
    "horn_boat": "Horn: speedboat, jet ski, hovercraft, banana boat", "horn_tugboat": "Horn: tugboat",
    "horn_swan": "Horn: swan pedalo", "horn_pirate": "Horn: pirate ship", "horn_steamer": "Horn: paddle steamer",
    "race_river": "Race music: Jungle River", "race_lagoon": "Race music: Pirate Cove",
}


def mp3(path: Path, y: np.ndarray, rate: int, channels: int) -> None:
    with sf.SoundFile(path, "w", rate, channels, format="MP3", compression_level=0.5) as f:
        for i in range(0, len(y), rate):
            f.write(y[i:i + rate].astype(np.float32))


def sfx_score(x: np.ndarray, clip: np.ndarray, sound: dict) -> tuple[float, str]:
    """Higher is better. A loop: an even level. A one-shot: one event, not several."""
    if sound["kind"] == "loop":
        env = gs.envelope(clip, 2205)
        cv = env.std() / max(env.mean(), 1e-9)
        return -cv, f"level varies {cv * 100:.0f}%"
    env = gs.envelope(x, 2205)
    loud = env > env.max() * 0.35
    events = int(np.count_nonzero(np.diff(loud.astype(int)) == 1)) + int(loud[0])
    return -abs(events - 1), f"{events} burst{'s' if events != 1 else ''} of sound"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sm = {s["id"]: s for s in gs.load_manifest()["sounds"]}
    sections = []
    for sid in SFX:
        sound = sm[sid]
        rows, scored = [], []
        derived = sound["kind"] == "derived"
        seeds = (range(1, derive_sfx.VARIANTS + 1) if derived
                 else range(101, 101 + sound.get("candidates", gs.load_manifest()["recipe"]["candidates"])))
        for seed in seeds:
            if derived:
                x, rate = derive_sfx.derive(sound, seed)
            else:
                path = gs.master_path(sid, seed)
                if not path.exists():
                    continue
                data, rate = sf.read(path)
                x = gs.to_mono(data)
            if derived:
                clip = x
                score, note = 0.0, f"variant {seed}, made from the approved water recordings"
                name = f"{sid}_v{seed}.mp3"
                mp3(OUT / name, clip, rate, 1)
                scored.append((score, seed, note, name))
                continue
            clip = gs.loop(x, sound) if sound["kind"] == "loop" else gs.oneshot(x, sound)
            score, note = sfx_score(x, clip, sound)
            play = np.tile(clip, 3) if sound["kind"] == "loop" else clip
            name = f"{sid}_{seed}.mp3"
            mp3(OUT / name, play, rate, 1)
            scored.append((score, seed, note, name))
        picked = sound.get("seed")
        best = None if picked or derived or not scored else max(scored)[1]
        for score, seed, note, name in scored:
            rows.append(row(sid, seed, note, name, seed == best, f"python tools/comfy/generate_sfx.py pick {sid} {seed}",
                            seed == picked))
        sections.append(section(sid, sound.get("prompt", ""), rows, sound["kind"] == "loop", sound.get("seed") is None))
    mm = gm.load_manifest()
    chosen = {"race_river": (102, 103, 104), "race_lagoon": (101,)}  # the river keeps three takes
    recipe = mm["recipe"]
    pieces = {p["id"]: p for p in mm["pieces"]}
    for pid in MUSIC:
        piece = pieces[pid]
        results = []
        for seed in gm.candidate_seeds(recipe):
            if gm.master_path(pid, seed).exists():
                results.append(gm.process(piece, recipe, seed))
        rows = []
        for r in results:
            y = r["audio"]
            if r["offset"] is not None:
                y = np.concatenate([y, y[r["offset"]:r["offset"] + 8 * gm.RATE]])
            name = f"{pid}_{r['seed']}.mp3"
            mp3(OUT / name, y, gm.RATE, 2)
            rows.append(row(pid, r["seed"], r["summary"], name, False,
                            f"python tools/comfy/generate_music.py pick {pid} {r['seed']}",
                            r["seed"] in chosen.get(pid, ())))
        sections.append(section(pid, piece["prompt"], rows, False))
    page = gm.LISTEN_PAGE.replace("<title>Vicky Racer Music</title>", "<title>Vicky Racer Boat Sounds</title>")
    page = page.replace("<h1>VICKY RACER MUSIC</h1>", "<h1>BOAT SOUNDS</h1>")
    start = page.index('<p class="intro">')
    end = page.index("</p>", start) + 4
    page = page[:start] + INTRO + page[end:]
    page = page.replace("{sections}", "\n".join(sections))
    (OUT / "index.html").write_text(page, encoding="utf-8")
    print(OUT / "index.html", len(list(OUT.glob("*.mp3"))), "previews")


INTRO = ('<p class="intro"><b>Three sounds are still to pick, at the top.</b> The splash and the ramp take-off are now '
         'cut from the water recordings you approved (the waves and the wake), six variants each; the pirate horn is '
         'now a ship\'s bell. Further down, yellow <b>IN THE GAME</b> marks your picks. Each candidate plays as the '
         'game will use it: one-shots trimmed, loops played three times round so you can hear where they repeat, '
         'music with its jump back to the loop start. <b>SUGGESTED</b> is a measurement, not a listen. Tell Claude '
         'your picks, for example "splash 3, ramp 5, pirate 104".</p>')


def row(sid: str, seed: int, note: str, name: str, suggested: bool, command: str, in_game: bool = False) -> str:
    label = f"VARIANT {seed}" if seed < 100 else f"SEED {seed}"
    chip = "<span class=chip>IN THE GAME</span>" if in_game else ("<span class=chip>SUGGESTED</span>" if suggested else "")
    return (f'<li class="{"picked" if in_game or suggested else ""}"><div class="who"><span class="seed">{label}</span>'
            f'{chip}<small>{html.escape(note)}</small></div>'
            f'<audio controls preload="none" src="{name}"></audio>'
            f'<button type="button" data-cmd="{command}" title="{command}">Copy pick</button></li>')


def section(sid: str, prompt: str, rows: list[str], is_loop: bool, to_pick: bool = False) -> str:
    title = sid.replace("_", " ").upper() + (" · STILL TO PICK" if to_pick else "")
    use = USE[sid] + (" (plays three times round)" if is_loop else "")
    return (f'<section><h2>{title}</h2><p class="use">{html.escape(use)}</p>'
            f'<p class="prompt">{html.escape(prompt)}</p><ul>{"".join(rows)}</ul></section>')


if __name__ == "__main__":
    main()

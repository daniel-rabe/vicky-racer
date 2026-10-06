"""Race music for Jungle Run, Candy Lane and Moon Base, synthesised (docs/DESIGN.md §13).

    python tools/comfy/synth_music.py [--only race_jungle] [--preview]

The first four race pieces were generated with Stable Audio 3 (generate_music.py). These three
are written note by note instead: a four-chord progression, a bass line, drums and a lead
melody built from the chords' notes, on a few small synthesised instruments, with the same
loudness and Ogg output as the generated pieces. The 16 bars are rendered with the end's
ringing notes wrapped round to the start, so the loop is seamless and starts at 0 s.
`--preview` also writes an MP3 of two times round each loop to docs/mockups/music/listen/.

Seeded: a rebuild writes the same music.
"""
import argparse
import json
import math
import subprocess
from pathlib import Path

import numpy as np

import generate_music as gm

ROOT = Path(__file__).resolve().parents[2]
RATE = gm.RATE
RECIPE = json.loads((Path(__file__).parent / "music_manifest.json").read_text(encoding="utf-8"))["recipe"]
NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
QUALITY = {"": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "maj7": (0, 4, 7, 11), "add9": (0, 4, 7, 14)}

PIECES = [
    {
        "id": "race_jungle", "use": "Jungle Run", "bpm": 120, "seed": 5, "out": "art/music/race_jungle.ogg",
        "key": "G", "scale": (0, 2, 4, 7, 9), "chords": ["G", "Em", "C", "D"],
        "lead": "marimba", "bass": "pluck", "pad": None, "drums": "bongos",
        "about": "marimba and kalimba over bongos, shaker and a plucked bass",
    },
    {
        "id": "race_candy", "use": "Candy Lane", "bpm": 132, "seed": 11, "out": "art/music/race_candy.ogg",
        "key": "F", "scale": (0, 2, 4, 7, 9), "chords": ["F", "Dm", "A#", "C"],
        "lead": "musicbox", "bass": "bouncy", "pad": "organ", "drums": "pop",
        "about": "music box and glockenspiel, a bouncy bass, claps and a toy organ",
    },
    {
        "id": "race_moon", "use": "Moon Base", "bpm": 124, "seed": 3, "out": "art/music/race_moon.ogg",
        "key": "D", "scale": (0, 2, 4, 6, 7, 9, 11), "chords": ["Dmaj7", "E", "Bm", "A"],
        "lead": "square", "bass": "saw", "pad": "strings", "drums": "electro",
        "about": "bright synth arpeggios and a lydian square-wave lead over an electro beat",
    },
]
BARS = 16


def freq(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def chord_notes(name: str, octave: int) -> list[int]:
    root = name[:2] if len(name) > 1 and name[1] == "#" else name[:1]
    quality = name[len(root):]
    base = 12 * (octave + 1) + NOTE[root]
    return [base + i for i in QUALITY[quality]]


# --- instruments: each returns a mono note of `dur` seconds plus its ring-out --------------

def env(n, attack, decay, sustain=0.0, release=0.05, hold=None):
    t = np.arange(n) / RATE
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = sustain + (1 - sustain) * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))
    out = a * d
    if hold is not None:
        out *= np.clip(1 - (t - hold) / release, 0, 1)
    return out


def tone(f, n, partials=((1, 1.0),), phase=0.0):
    t = np.arange(n) / RATE
    return sum(a * np.sin(2 * np.pi * f * k * t + phase) for k, a in partials)


def instrument(name: str, f: float, dur: float, rng) -> np.ndarray:
    n = int((dur + 1.2) * RATE)
    if name == "marimba":
        return tone(f, n, ((1, 1.0), (4.0, 0.25), (9.8, 0.06))) * env(n, 0.002, 0.28)
    if name == "kalimba":
        return tone(f, n, ((1, 1.0), (5.4, 0.18))) * env(n, 0.002, 0.45)
    if name == "musicbox":
        return tone(f, n, ((1, 1.0), (2.0, 0.3), (5.9, 0.12))) * env(n, 0.001, 0.6)
    if name == "glock":
        return tone(f, n, ((1, 1.0), (2.76, 0.4), (5.4, 0.2))) * env(n, 0.001, 0.4)
    if name == "square":
        t = np.arange(n) / RATE
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.25, 0, 1)
        ph = np.cumsum(f * vib / RATE)
        wave = sum(np.sin(2 * np.pi * k * ph) / k * (0.8 ** k) for k in (1, 3, 5, 7))
        return wave * env(n, 0.01, 0.35, 0.55, 0.08, hold=dur * 0.9)
    if name == "arp":
        t = np.arange(n) / RATE
        wave = sum(np.sin(2 * np.pi * f * k * t) / k * (0.6 ** k) for k in range(1, 7))
        return wave * env(n, 0.003, 0.12)
    if name == "pluck":
        return tone(f, n, ((1, 1.0), (2, 0.35), (3, 0.1))) * env(n, 0.004, 0.22, 0.0)
    if name == "bouncy":
        t = np.arange(n) / RATE
        bend = f * (1 + 0.5 * np.exp(-t / 0.015))
        return np.sin(2 * np.pi * np.cumsum(bend) / RATE) * env(n, 0.003, 0.16, 0.2, 0.05, hold=dur * 0.8)
    if name == "saw":
        t = np.arange(n) / RATE
        wave = sum(np.sin(2 * np.pi * f * k * t) / k * (0.55 ** k) for k in range(1, 9))
        return wave * env(n, 0.005, 0.2, 0.5, 0.05, hold=dur * 0.85)
    if name == "organ":
        return tone(f, n, ((1, 1.0), (2, 0.5), (4, 0.2))) * env(n, 0.02, 1.0, 0.9, 0.1, hold=dur)
    if name == "strings":
        t = np.arange(n) / RATE
        wave = sum(np.sin(2 * np.pi * f * (1 + d) * t) for d in (-0.003, 0.0, 0.004)) / 3
        return wave * env(n, 0.25, 2.0, 0.8, 0.4, hold=dur)
    raise ValueError(name)


def drum(name: str, rng) -> np.ndarray:
    n = int(0.6 * RATE)
    t = np.arange(n) / RATE
    noise = rng.standard_normal(n)
    if name == "kick":
        f = 50 + 110 * np.exp(-t / 0.03)
        return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.18)
    if name == "snare":
        return (0.6 * noise * np.exp(-t / 0.07) + 0.5 * np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.05))
    if name == "clap":
        e = sum(np.exp(-np.maximum(t - d, 0) / 0.012) * (t >= d) for d in (0, 0.011, 0.022)) + np.exp(-t / 0.09) * 0.5
        return _highpass(noise, 0.6) * e * 0.7
    if name == "hat":
        return _highpass(noise, 0.9) * np.exp(-t / 0.025) * 0.5
    if name == "shaker":
        return _highpass(noise, 0.85) * np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.05) * 0.4
    if name in ("bongo_hi", "bongo_lo"):
        f0 = 380 if name == "bongo_hi" else 260
        f = f0 * (1 + 0.3 * np.exp(-t / 0.01))
        return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.09)
    raise ValueError(name)


def _highpass(x, amount):
    """A crude high-pass: the signal minus its own smoothed self."""
    k = max(2, int(12 * (1 - amount)) + 2)
    return x - np.convolve(x, np.ones(k) / k, mode="same")


# --- composing -----------------------------------------------------------------------------

DRUMS = {  # 16 sixteenths per bar: instrument -> steps
    "bongos": {"kick": [0, 8], "bongo_hi": [3, 6, 11, 14], "bongo_lo": [2, 10, 12], "shaker": list(range(0, 16, 2)),
               "clap": [4, 12]},
    "pop": {"kick": [0, 6, 8], "clap": [4, 12], "hat": [2, 6, 10, 14], "shaker": [1, 3, 5, 7, 9, 11, 13, 15]},
    "electro": {"kick": [0, 4, 8, 12], "snare": [4, 12], "hat": [2, 6, 10, 14, 15]},
}
RHYTHMS = [  # one bar of melody: (start sixteenth, length in sixteenths)
    [(0, 3), (3, 3), (6, 2), (8, 4), (12, 2), (14, 2)],
    [(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 4)],
    [(0, 4), (4, 2), (6, 2), (8, 3), (11, 5)],
    [(0, 2), (2, 2), (4, 2), (6, 2), (8, 6), (14, 2)],
]


def compose(piece: dict, rng) -> list[tuple]:
    """Notes as (instrument, midi, start beat, length beats, gain, pan)."""
    notes = []
    key = NOTE[piece["key"]]
    scale = [12 * o + key + s for o in range(5, 7) for s in piece["scale"]] + [12 * 7 + key]
    # A 4-bar phrase, repeated as A A' B A'': the same rhythm, the melody varied a little.
    phrase, last = [], scale.index(12 * 6 + key) if 12 * 6 + key in scale else len(scale) // 2
    motif_rhythms = [RHYTHMS[i] for i in rng.permutation(len(RHYTHMS))]
    for bar in range(4):
        chord = chord_notes(piece["chords"][bar % 4], 5)
        for start, length in motif_rhythms[bar]:
            strong = start in (0, 8)
            candidates = [i for i in range(len(scale)) if abs(i - last) <= 3]
            if strong:  # land on a chord note on the strong beats
                candidates = [i for i in candidates if scale[i] % 12 in {c % 12 for c in chord}] or candidates
            last = int(rng.choice(candidates))
            phrase.append((bar, start, length, last))
    for section in range(4):
        for bar, start, length, idx in phrase:
            if section == 1 and bar == 3:
                idx = max(0, idx - 2)
            if section == 2:
                idx = min(len(scale) - 1, idx + 2)  # the B part sits higher
            if section == 3 and bar == 3 and start >= 8:
                idx = scale.index(12 * 6 + key) if 12 * 6 + key in scale else idx  # home at the end
            beat = (section * 4 + bar) * 4 + start / 4
            notes.append((piece["lead"], scale[idx], beat, length / 4 * 0.95, 0.5, 0.15))
            if piece["lead"] == "marimba" and section == 2:
                notes.append(("kalimba", scale[idx] + 12, beat, length / 4, 0.18, -0.4))
            if piece["lead"] == "musicbox" and section in (1, 3):
                notes.append(("glock", scale[idx] + 12, beat, length / 4, 0.16, -0.35))
    for bar in range(BARS):
        name = piece["chords"][bar % 4]
        chord = chord_notes(name, 4)
        root = chord[0] - 24
        b = bar * 4
        if piece["bass"] == "pluck":
            for s, d in ((0, 1.5), (1.5, 0.5), (2, 1), (3, 0.5), (3.5, 0.5)):
                notes.append(("pluck", root + (7 if s == 3 else 0), b + s, d, 0.55, 0.0))
        elif piece["bass"] == "bouncy":
            for s in (0, 1, 1.5, 2, 3, 3.5):
                notes.append(("bouncy", root + (12 if s in (1.5, 3.5) else 0), b + s, 0.4, 0.5, 0.0))
        else:
            for s in np.arange(0, 4, 0.5):
                notes.append(("saw", root + (12 if s % 1 else 0), b + s, 0.4, 0.32, 0.0))
        if piece["pad"]:
            for k, m in enumerate(chord):
                notes.append((piece["pad"], m, b, 4.0, 0.07, (-0.5, 0.0, 0.5, 0.2)[k % 4]))
        if piece["id"] == "race_moon":  # the arpeggio: chord notes up and down in sixteenths
            up = chord + [chord[0] + 12]
            pattern = up + up[-2:0:-1]
            for k in range(16):
                notes.append(("arp", pattern[k % len(pattern)] + 12, b + k / 4, 0.2, 0.13, 0.45 if k % 2 else -0.45))
        if piece["id"] == "race_jungle" and bar % 2 == 1:  # kalimba answers
            for k, m in enumerate(chord):
                notes.append(("kalimba", m + 12, b + 2 + k * 0.5, 0.5, 0.14, -0.3))
    return notes


def render(piece: dict) -> np.ndarray:
    rng = np.random.default_rng(piece["seed"])
    beat = 60.0 / piece["bpm"]
    length = int(round(BARS * 4 * beat * RATE))
    out = np.zeros((length + 3 * RATE, 2))

    def add(sound, at_beat, gain, pan):
        i = int(round(at_beat * beat * RATE))
        left, right = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
        out[i:i + len(sound), 0] += sound * gain * left
        out[i:i + len(sound), 1] += sound * gain * right

    cache = {}
    for inst, midi, at, dur, gain, pan in compose(piece, rng):
        key = (inst, midi, round(dur, 3))
        if key not in cache:
            cache[key] = instrument(inst, freq(midi), dur * beat, rng)
        add(cache[key], at, gain, pan)
    kit = {name: drum(name, rng) for name in ("kick", "snare", "clap", "hat", "shaker", "bongo_hi", "bongo_lo")}
    gains = {"kick": 0.9, "snare": 0.45, "clap": 0.4, "hat": 0.22, "shaker": 0.2, "bongo_hi": 0.35, "bongo_lo": 0.4}
    pans = {"hat": 0.3, "shaker": -0.3, "bongo_hi": 0.35, "bongo_lo": -0.25}
    for bar in range(BARS):
        for inst, steps in DRUMS[piece["drums"]].items():
            for s in steps:
                accent = 1.0 if s % 4 == 0 else 0.8
                add(kit[inst], bar * 4 + s / 4, gains[inst] * accent, pans.get(inst, 0.0))
    # Wrap what rings past the end round to the start: the loop is seamless from 0 s.
    y = out[:length].copy()
    y[:len(out) - length] += out[length:]
    return y


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    for piece in PIECES:
        if args.only and piece["id"] not in args.only.split(","):
            continue
        y = gm.loudness(render(piece), RECIPE)
        gm.write_ogg(y, piece["out"])
        res = gm.write_piece_resource(piece, {"offset": 0})
        print(f"  {piece['out']}: {len(y) / RATE:.2f}s, {BARS} bars at {piece['bpm']} BPM -> {res.relative_to(ROOT)}")
        if args.preview:
            mp3 = ROOT / "docs/mockups/music/listen" / f"{piece['id']}_preview.mp3"
            mp3.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-stream_loop", "1", "-i", str(ROOT / piece["out"]),
                            "-q:a", "5", str(mp3)], check=True)


if __name__ == "__main__":
    main()

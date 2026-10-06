"""Sounds cut from other, already approved sounds instead of generated (DESIGN.md §20.6).

Stable Audio makes convincing continuous water (the wake and wave loops) but not a single wet
splash or the splash of taking off from a ramp: two rounds of prompts sounded like wind. So
these two are shaped from the approved water masters. A manifest entry with "kind": "derived"
names its `method` and `source` (a master in masters/sfx/), and its `seed` is the variant:
which splash in the source it starts from. Deterministic, like everything else here, so
`generate_sfx.py pick splash 3` and `build` work as for any sound.
"""
from pathlib import Path

import numpy as np
import soundfile as sf

HERE = Path(__file__).parent
MASTERS = HERE / "masters" / "sfx"
VARIANTS = 6


def _mono(path: Path) -> tuple[np.ndarray, int]:
    data, rate = sf.read(path)
    return (data.mean(axis=1) if data.ndim > 1 else data), rate


def _envelope(x: np.ndarray, window: int) -> np.ndarray:
    return np.sqrt(np.convolve(x ** 2, np.ones(window) / window, mode="same"))


def _resample(x: np.ndarray, ratio) -> np.ndarray:
    """Play x back `ratio` times as fast (a number, or one ratio per output sample)."""
    if np.isscalar(ratio):
        pos = np.arange(0.0, len(x) - 1, ratio)
    else:
        pos = np.cumsum(ratio)
        pos = pos[pos < len(x) - 1]
    return np.interp(pos, np.arange(len(x)), x)


def _peaks(x: np.ndarray, rate: int, gap: float = 0.25) -> list[int]:
    """The loudest wet slaps in a recording, loudest first, at least `gap` seconds apart."""
    env = _envelope(x, int(0.01 * rate))
    edge = int(0.3 * rate)
    order = np.argsort(env[edge:-edge])[::-1] + edge
    chosen: list[int] = []
    for i in order:
        if all(abs(i - j) > gap * rate for j in chosen):
            chosen.append(int(i))
        if len(chosen) >= VARIANTS * 2:
            break
    return chosen


def _decay(n: int, rate: int, attack: float, tau: float) -> np.ndarray:
    t = np.arange(n) / rate
    return np.minimum(1.0, t / attack) * np.exp(-np.maximum(0.0, t - attack) / tau)


def splash(source: np.ndarray, rate: int, variant: int, slaps: np.ndarray | None = None) -> np.ndarray:
    """A single splash. Its body is a burst of the wake's dense rushing water, pitched down for
    weight, with a sharp attack and a quick decay; the impact on top is one slap of the waves,
    and a few smaller slaps, pitched up, fall back as droplets."""
    n = int(0.75 * rate)
    offset = int((0.4 + 0.7 * (variant - 1)) * rate) % max(len(source) - 2 * n, 1)
    body = _resample(source[offset: offset + 2 * n], 0.78)[:n]
    body = np.pad(body, (0, n - len(body)))
    body *= _decay(n, rate, 0.006, 0.13 + 0.02 * (variant % 3))
    out = body / max(np.abs(body).max(), 1e-9)
    if slaps is not None:
        peaks = _peaks(slaps, rate)
        at = peaks[(variant - 1) % len(peaks)]
        hit = slaps[max(at - int(0.004 * rate), 0): at + int(0.06 * rate)]
        hit = hit / max(np.abs(hit).max(), 1e-9) * _decay(len(hit), rate, 0.001, 0.025)
        out[: len(hit)] += 0.7 * hit
        for k, delay in enumerate((0.16, 0.24, 0.33, 0.45)):
            p = peaks[(variant + 3 + k) % len(peaks)]
            drop = _resample(slaps[p: p + int(0.08 * rate)], 1.35 + 0.1 * k)
            drop = drop / max(np.abs(drop).max(), 1e-9) * _decay(len(drop), rate, 0.001, 0.02) * (0.32 - 0.05 * k)
            i = int(delay * rate)
            out[i: i + len(drop)] += drop[: n - i]
    return out


def ramp(source: np.ndarray, rate: int, variant: int) -> np.ndarray:
    """Taking off: a burst of rushing water swelling and rising in pitch as the boat climbs the
    ramp, cut off as it leaves the water, with a light slap of spray at the lip."""
    n = int(0.75 * rate)
    start = int((0.3 + 0.55 * (variant - 1)) * rate) % max(len(source) - 2 * n, 1)
    seg = _resample(source[start: start + 2 * n], np.linspace(0.8, 1.45, n))[:n]
    seg = np.pad(seg, (0, n - len(seg)))
    # Even out the recording's own swells first, so the shape below is what is heard.
    level = _envelope(seg, int(0.03 * rate))
    seg = seg / np.maximum(level, level.max() * 0.05)
    t = np.linspace(0.0, 1.0, n)
    swell = 0.18 + 0.82 * t ** 0.9
    cut = int(0.06 * rate)
    swell[-cut:] *= np.linspace(1.0, 0.0, cut)
    out = seg * swell
    out /= max(np.abs(out).max(), 1e-9)
    lip = int(0.7 * n)
    spray = _resample(source[start + n: start + n + int(0.25 * rate)], 1.6)
    spray = spray / max(np.abs(spray).max(), 1e-9) * _decay(len(spray), rate, 0.003, 0.06) * 0.45
    out[lip: lip + len(spray)] += spray[: n - lip]
    return out


METHODS = {"splash": splash, "ramp": ramp}


def derive(sound: dict, variant: int) -> tuple[np.ndarray, int]:
    """The variant, normalised to the sound's peak and faded at both ends, ready to play."""
    source, rate = _mono(MASTERS / f"{sound['source']}.flac")
    extra = {}
    if "slaps" in sound:
        extra["slaps"] = _mono(MASTERS / f"{sound['slaps']}.flac")[0]
    x = METHODS[sound["method"]](source, rate, variant, **extra)
    x[: int(0.002 * rate)] *= np.linspace(0.0, 1.0, int(0.002 * rate))
    tail = int(0.03 * rate)
    x[-tail:] *= np.linspace(1.0, 0.0, tail)
    return x / max(np.abs(x).max(), 1e-9) * 10 ** (sound.get("peak_db", -3.0) / 20), rate

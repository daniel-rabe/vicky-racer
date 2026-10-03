"""Measures how smoothly the view scrolls while driving, from frames the game actually renders.

    python tools/dev/motion_check.py                # interpolation as configured
    python tools/dev/motion_check.py --no-interp    # for comparison

Godot's movie writer renders at a fixed 100 fps while physics runs at 60 Hz: the same beat a
100 Hz monitor sees. The car drives a steady circle (--drive-circle) and a hay bale, which never
moves in the world, is tracked on screen: its motion is purely the camera's. Frames where a bale
is entering or leaving the view are skipped, because a half-visible bale's centre jumps.

"Unevenness" is the change in the per-frame step, reported as median and 90th percentile.

Tracking the car itself does not work: it rotates fast on the circle, and its stripes shift
the red-pixel centre by several pixels per frame.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
GODOT = "G:/Godot/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64_console.exe"
FPS = 100
SKIP = 120     # let the car settle into its circle first
FRAMES = 320


def bale(path: Path) -> tuple[float, float, int]:
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    mask = (a[..., 0] > 200) & (a[..., 1] > 150) & (a[..., 2] < 100)
    ys, xs = np.nonzero(mask)
    return (float(xs.mean()), float(ys.mean()), int(mask.sum())) if mask.sum() > 50 else (np.nan, np.nan, 0)


def main() -> None:
    extra = [a for a in sys.argv[1:] if a.startswith("--")]
    tmp = tempfile.mkdtemp()
    try:
        subprocess.run([GODOT, "--path", str(ROOT), "--resolution", "1920x1080", "--fixed-fps", str(FPS),
                        "--write-movie", f"{tmp}/frame.png", "--quit-after", str(FRAMES), "--",
                        "--save=user://motion_check.cfg", "--screen=race", "--drive-circle", *extra],
                       check=True, capture_output=True, timeout=600)
        samples = np.array([bale(f) for f in sorted(Path(tmp).glob("frame*.png"))[SKIP:]])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    # Skip frames where a bale crosses the screen edge: its pixel count jumps from one frame
    # to the next. Sub-pixel drift changes it by a few percent at most.
    counts = samples[:, 2]
    whole = np.zeros(len(counts), dtype=bool)
    for i in range(1, len(counts)):
        whole[i] = counts[i] > 0 and counts[i - 1] > 0 and abs(counts[i] - counts[i - 1]) < 0.06 * counts[i]
    steps, uneven = [], []
    for i in range(2, len(samples)):
        if whole[i] and whole[i - 1] and whole[i - 2]:
            s1 = np.hypot(*(samples[i - 1, :2] - samples[i - 2, :2]))
            s2 = np.hypot(*(samples[i, :2] - samples[i - 1, :2]))
            steps.append(s2)
            uneven.append(abs(s2 - s1))
    label = " ".join(extra) or "as configured"
    # Median, not mean: the odd bale sliding in at the screen edge still skews single frames.
    print(f"{label}: {len(uneven)} frames, view scroll {np.median(steps):.1f} px/frame, "
          f"unevenness median {np.median(uneven):.2f} px, 90th percentile {np.percentile(uneven, 90):.2f} px")


if __name__ == "__main__":
    main()

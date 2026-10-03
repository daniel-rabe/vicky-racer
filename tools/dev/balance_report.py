"""Balance pass for Phase 8: race every drift setup at several player paces and tabulate.

The player's car runs on autopilot (the AI driver at full skill) with a pace multiplier
standing in for how well a child drives: 1.0 = clean, 0.7 = struggling. Each cell is one
headless run of tests/race_test.tscn. Prints a Markdown table of finishing position and the
player's gap to the winner (or lead over 2nd), ready for docs/DESIGN.md.

    python tools/dev/balance_report.py [--paces 1.0 0.85 0.7] [--setups starter banana]
"""
import argparse
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

GODOT = r"G:\Godot\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
ROOT = Path(__file__).resolve().parents[2]
SETUPS = ["starter", "grippy", "slider", "rocket", "kart", "banana"]
RESULT = re.compile(r"results are in finishing order \(\[(.*)\]\)")
ENTRY = re.compile(r'"(\w+) ([\d.]+)s"')


def race(setup: str, pace: float) -> dict:
    out = subprocess.run(
        [GODOT, "--path", str(ROOT), "--headless", "--fixed-fps", "60", "res://tests/race_test.tscn",
         "--", f"--autopilot={pace}", f"--setup={setup}"],
        capture_output=True, text=True, timeout=600).stdout
    found = RESULT.search(out)
    if not found:
        return {"setup": setup, "pace": pace, "error": out[-400:]}
    order = [(name, float(t)) for name, t in ENTRY.findall(found.group(1))]
    names = [n for n, _ in order]
    place = names.index("YOU") + 1
    you = order[place - 1][1]
    gap = you - order[0][1] if place > 1 else you - order[1][1]  # negative = winning margin
    rescues = re.search(r"player rescues (\d+)", out)
    return {"setup": setup, "pace": pace, "place": place, "gap": gap, "time": you,
            "spread": order[-1][1] - order[0][1], "rescues": int(rescues.group(1)) if rescues else -1,
            "passed": "ALL RACE TESTS PASSED" in out}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--paces", type=float, nargs="+", default=[1.0, 0.85, 0.7])
    parser.add_argument("--setups", nargs="+", default=SETUPS)
    parser.add_argument("--jobs", type=int, default=6)
    args = parser.parse_args()
    jobs = [(s, p) for s in args.setups for p in args.paces]
    with ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(lambda j: race(*j), jobs))
    print("| Setup | " + " | ".join(f"pace {p:g}" for p in args.paces) + " |")
    print("| --- |" + " --- |" * len(args.paces))
    for setup in args.setups:
        cells = []
        for p in args.paces:
            r = next(r for r in results if r["setup"] == setup and r["pace"] == p)
            if "error" in r:
                cells.append("error")
                continue
            ordinal = {1: "1st", 2: "2nd", 3: "3rd", 4: "4th"}[r["place"]]
            extra = (" rescued" if r["rescues"] > 0 else "") + ("" if r["passed"] else " FAIL")
            cells.append(f"{ordinal} {r['gap']:+.1f}s{extra}")
        print(f"| {setup} | " + " | ".join(cells) + " |")
    for r in results:
        if "error" in r:
            print(f"\n{r['setup']} @ {r['pace']}: no result\n{r['error']}")


if __name__ == "__main__":
    main()

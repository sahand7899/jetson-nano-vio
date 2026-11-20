#!/usr/bin/env python3
"""Time per step of VINS-Mono, read from the debug messages of a timing run.

VINS-Mono writes no timing file. Started with its debug messages on (TIMING=1
run_vins-mono_euroc.sh <bag>) it prints how long each step took. Writing these messages
costs processor time itself, so the numbers are a little higher than in a measured run.

  vins_estimator: one answer per tracked image that the tracker passes on (10 per second,
                  so the time limit is 100 ms). "whole answer" is the authors' own number
                  ("vo solver costs"); the optimisation inside it is limited by the authors'
                  settings max_solver_time (0.04 s) and max_num_iterations (8).
  feature_tracker: every camera image (20 per second, limit 50 ms): sum of the printed steps.

Writes timing_summary.txt into the run folder.
usage: vins_mono_timing.py <run folder>
"""
import os
import re
import statistics
import sys
from collections import Counter


def pct(v, p):
    s = sorted(v)
    k = (len(s) - 1) * p / 100.0
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def line(name, v, limit=None):
    text = f"{name:<34}{statistics.median(v):6.1f} / {pct(v, 95):6.1f} / {max(v):6.1f} ms"
    if limit:
        over = sum(x > limit for x in v)
        text += f"   over {limit:.0f} ms: {over} of {len(v)} ({100.0 * over / len(v):.1f} %)"
    return text


def main(run):
    whole, solve, iters = [], [], []
    with open(os.path.join(run, "vins.log"), errors="replace") as f:
        for l in f:
            if m := re.search(r"\]: vo solver costs: ([\d.]+) ms", l):
                whole.append(float(m.group(1)))
            elif m := re.search(r"\]: solver costs: ([\d.]+)$", l):
                solve.append(float(m.group(1)))
            elif m := re.search(r"\]: Iterations : (\d+)", l):
                iters.append(int(m.group(1)))
    track, cur = [], None
    with open(os.path.join(run, "feature_tracker.log"), errors="replace") as f:
        for l in f:
            if "processing camera 0" in l:
                if cur is not None:
                    track.append(cur)
                cur = 0.0
            elif cur is not None and (m := re.search(r"(?:CLAHE|temporal optical flow|set mask|detect feature|selectFeature) costs:? ([\d.]+)ms", l)):
                cur += float(m.group(1))
    if cur is not None:
        track.append(cur)
    out = ["time per step: median / 95 % / longest"]
    out.append(line("estimator, whole answer", whole, 100))
    out.append(line("  of that: optimisation (Ceres)", solve, 40))
    c = Counter(iters)
    allowed = "?"
    cfg = os.path.join(run, "config", "euroc_config.yaml")
    if os.path.exists(cfg) and (m := re.search(r"^max_num_iterations:\s*(\d+)", open(cfg).read(), re.M)):
        allowed = m.group(1)
    out.append("  optimisation rounds per answer:   " + ", ".join(f"{k} rounds: {100.0 * c[k] / len(iters):.0f} %" for k in sorted(c))
               + f"   (the settings allow {allowed})")
    out.append(line("tracker, per camera image", track, 50))
    text = "\n".join(out) + "\n"
    with open(os.path.join(run, "timing_summary.txt"), "w") as f:
        f.write(text)
    print(text, end="")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])

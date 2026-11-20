#!/usr/bin/env python3
"""Prints one table of all runs under results/jetson_euroc.

Each line is one run folder: where it ran, algorithm, recording, start time of the playback,
ATE RMSE over the run's own whole path, RPE, lost camera images, median time per image,
how far the answers were behind the camera at the end of the run (near 0 = keeps up),
and whether a live viewer was attached (such runs are for watching, not for measurements).

usage:  python3 evaluation/list_results.py            # plain table
        python3 evaluation/list_results.py --markdown # table for results/README.md
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results")
STAGES = [("jetson_euroc", "Jetson")]


def first(path, pattern, default=""):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            m = re.search(pattern, f.read(), re.M)
        return m.group(1) if m else default
    except OSError:
        return default


def rows():
    for folder, where in STAGES:
        base = os.path.join(ROOT, folder)
        if not os.path.isdir(base):
            continue
        for algo in sorted(os.listdir(base)):
            for seq in sorted(os.listdir(os.path.join(base, algo))):
                if seq.startswith("_") or not os.path.isdir(os.path.join(base, algo, seq)):
                    continue  # e.g. _build_record: the build log, not a recording
                for run in sorted(os.listdir(os.path.join(base, algo, seq))):
                    d = os.path.join(base, algo, seq, run)
                    if not os.path.isdir(d):
                        continue
                    ate = first(os.path.join(d, "vio_ate.txt"), r"^\s*rmse\s+([\d.]+)", "failed")
                    rpe = first(os.path.join(d, "vio_rpe.txt"), r"^\s*rmse\s+([\d.]+)", "-")
                    start = first(os.path.join(d, "run_info.txt"), r"starting ([\d.]+) s into", "?")
                    viewer = first(os.path.join(d, "run_info.txt"), r"^live viewer:\s+(\S+)", "?")
                    frames = first(os.path.join(d, "frame_check.txt"), r"^(\w+):", "?")
                    ms = first(os.path.join(d, "summary_resources.txt"), r"time per frame median\s+([\d.]+) ms", "")
                    if not ms:  # VINS-Fusion: time per answer (it answers for every second image)
                        per_answer = first(os.path.join(d, "summary_resources.txt"), r"optimisation per answer median\s+([\d.]+) ms", "")
                        ms = f"{per_answer} per answer" if per_answer else "-"
                    common = first(os.path.join(d, "vio_common_ate.txt"), r"^\s*rmse\s+([\d.]+)", "-")
                    late = first(os.path.join(d, "delay_check.txt"), r"last 10 % of run\s+([\d.]+) s", "-")
                    yield [where, algo, seq, run, start, ate, common, rpe, frames, ms, late, "yes" if viewer == "ON" else "no"]


def main():
    head = ["where", "algorithm", "recording", "run", "start [s]", "ATE own path [m]", "ATE common window [m]", "RPE [m]",
            "images", "ms per image (median)", "behind camera at end [s]", "viewer"]
    data = list(rows())
    if "--markdown" in sys.argv:
        print("| " + " | ".join(head) + " |")
        print("|" + "---|" * len(head))
        for r in data:
            print("| " + " | ".join(r) + " |")
        return
    widths = [max(len(str(x)) for x in col) for col in zip(head, *data)] if data else [len(h) for h in head]
    for r in [head] + data:
        print("  ".join(str(x).ljust(w) for x, w in zip(r, widths)))


if __name__ == "__main__":
    main()

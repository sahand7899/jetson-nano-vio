#!/usr/bin/env python3
"""Summarises the computer load of one run folder and writes it to summary_resources.txt.

Reads (when present):
  resources.csv     - container CPU % and memory over time (only for the earlier Docker runs on a PC)
  traj_timing.txt   - OpenVINS's own processing time per camera frame
  vins.log          - VINS-Fusion: the authors' own "process time" of every answer (ms)

usage: summarize_run.py <run_dir> [camera_rate_hz]
"""
import csv
import re
import os
import statistics
import sys


def percentile(values, p):
    s = sorted(values)
    k = (len(s) - 1) * p / 100.0
    lo, hi = int(k), min(int(k) + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def main(run_dir, camera_hz=20.0):
    lines = []
    res = os.path.join(run_dir, "resources.csv")
    if os.path.exists(res):
        with open(res) as f:
            rows = [r for r in csv.DictReader(f) if r["cpu_percent"]]
        cpu = [float(r["cpu_percent"]) for r in rows]
        mem = [float(r["mem_MiB"]) for r in rows]
        if cpu:
            lines += [f"container samples        {len(cpu)}",
                      f"CPU mean / max           {statistics.mean(cpu):.0f} % / {max(cpu):.0f} %   (100 % = 1 core)",
                      f"RAM mean / max           {statistics.mean(mem):.0f} MiB / {max(mem):.0f} MiB"]

    # Jetson runs: load.csv from jetson/<algorithm>/run_*_euroc.sh (one line per second)
    load = os.path.join(run_dir, "load.csv")
    if os.path.exists(load):
        with open(load) as f:
            rows = [r for r in csv.DictReader(f) if r["est_cpu_percent"]]
        if rows:
            cpu = [float(r["est_cpu_percent"]) for r in rows]
            mem = [float(r["est_mem_MiB"]) for r in rows]
            sys_cpu = [float(r["system_cpu_percent"]) for r in rows]
            temp = [float(r["cpu_temp_C"]) for r in rows if r["cpu_temp_C"]]
            lines += [f"load samples             {len(cpu)}",
                      f"estimator CPU mean / max {statistics.mean(cpu):.0f} % / {max(cpu):.0f} %   (100 % = 1 core)",
                      f"estimator RAM mean / max {statistics.mean(mem):.0f} MiB / {max(mem):.0f} MiB",
                      f"whole Jetson CPU mean    {statistics.mean(sys_cpu):.0f} %   (400 % = all 4 cores)"]
            if temp:
                lines.append(f"temperature mean / max   {statistics.mean(temp):.1f} C / {max(temp):.1f} C")
            # VINS-Mono is two programs; "estimator" above is both together, here each alone
            for col, name in (("tracker", "feature_tracker"), ("estimator", "vins_estimator")):
                if rows[0].get(f"{col}_cpu_percent"):
                    c = [float(r[f"{col}_cpu_percent"]) for r in rows]
                    m = [float(r[f"{col}_mem_MiB"]) for r in rows]
                    lines.append(f"  {name + ' CPU mean / max':<31}{statistics.mean(c):.0f} % / {max(c):.0f} %, "
                                 f"RAM max {max(m):.0f} MiB")

    timing = os.path.join(run_dir, "traj_timing.txt")
    if os.path.exists(timing):
        with open(timing) as f:
            header = f.readline().lstrip("#").strip().split(",")
            # sqrtVINS writes ~9.2e12 s ("not a time") for steps that did not run in a frame
            data = [[0.0 if i > 0 and float(x) > 1e6 else float(x) for i, x in enumerate(line.split(","))]
                    for line in f if line.strip()]
        total = [row[-1] * 1000 for row in data]  # seconds -> milliseconds
        budget = 1000.0 / camera_hz
        lines += [f"frames timed             {len(total)}",
                  f"time per frame mean      {statistics.mean(total):.1f} ms",
                  f"time per frame median    {statistics.median(total):.1f} ms",
                  f"time per frame 95th pct  {percentile(total, 95):.1f} ms",
                  f"time per frame max       {max(total):.1f} ms",
                  f"frames over {budget:.0f} ms budget  {sum(t > budget for t in total)} "
                  f"({100.0 * sum(t > budget for t in total) / len(total):.1f} %)"]
        for i, name in enumerate(header[1:-1], start=1):
            lines.append(f"  {name.strip():<22} {statistics.mean(r[i] for r in data) * 1000:.1f} ms on average")

    # VINS-Fusion prints the time of its optimisation for every answer itself
    # ("solver costs: 41.2 [ms]"; it includes the marginalisation). The feature tracking runs
    # in a second thread and is not in this number; the delay check covers both.
    # It answers for every second camera image (10 per second), so the limit is 100 ms.
    vlog = os.path.join(run_dir, "vins.log")
    if os.path.exists(vlog) and not os.path.exists(timing):
        with open(vlog, errors="replace") as f:
            proc = [float(m.group(1)) for l in f for m in [re.search(r"solver costs: ([\d.]+) \[ms\]", l)] if m]
        if proc:
            limit = 2000.0 / camera_hz
            over = sum(t > limit for t in proc)
            lines += [f"answers timed            {len(proc)}   (VINS-Fusion's own 'solver costs')",
                      f"optimisation per answer median {statistics.median(proc):.1f} ms",
                      f"optimisation per answer 95th   {percentile(proc, 95):.1f} ms",
                      f"optimisation per answer max    {max(proc):.1f} ms",
                      f"answers over {limit:.0f} ms limit {over} ({100.0 * over / len(proc):.1f} %)   (10 answers per second)"]

    text = "\n".join(lines) + "\n"
    with open(os.path.join(run_dir, "summary_resources.txt"), "w") as f:
        f.write(text)
    print(text, end="")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 20.0)

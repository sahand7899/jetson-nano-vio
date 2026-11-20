#!/usr/bin/env python3
"""Convert a EuRoC-style CSV trajectory to TUM format, which evo reads directly.

Both VINS-Mono's result files (vins_result_no_loop.csv / vins_result_loop.csv) and the
EuRoC ground truth (mav0/state_groundtruth_estimate0/data.csv) start every line with
    timestamp [ns], px, py, pz, qw, qx, qy, qz, ...
TUM format is one pose per line:
    timestamp [s] px py pz qx qy qz qw

usage: euroc_csv_to_tum.py <input.csv> <output.tum>
"""
import sys


def ns_to_seconds_str(t_ns: int) -> str:
    # Integer arithmetic keeps full nanosecond precision (a float would round it)
    return f"{t_ns // 10**9}.{t_ns % 10**9:09d}"


def convert(src: str, dst: str) -> int:
    poses = {}
    with open(src) as fin:
        for line in fin:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # VINS-Mono ends every line with a trailing comma -> drop empty fields
            v = [x.strip() for x in line.split(",") if x.strip()]
            t_ns = int(v[0]) if v[0].isdigit() else int(float(v[0]))
            px, py, pz, qw, qx, qy, qz = v[1:8]
            poses[t_ns] = (px, py, pz, qx, qy, qz, qw)  # a repeated timestamp keeps the last pose

    with open(dst, "w") as fout:
        for t_ns in sorted(poses):
            fout.write(ns_to_seconds_str(t_ns) + " " + " ".join(poses[t_ns]) + "\n")
    return len(poses)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    n = convert(sys.argv[1], sys.argv[2])
    print(f"{sys.argv[2]}: {n} poses")

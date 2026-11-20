#!/usr/bin/env python3
"""Check a run for lost camera frames and write the verdict to frame_check.txt in its folder.

On the development laptop, WSL sometimes froze for up to about a second. Afterwards the recording catches
up in a burst; if more images arrive than a program keeps waiting, some are lost and the run
is not comparable. The algorithm's output has one line per processed frame, so a gap longer
than 1.5 frame periods means frames were lost.

  OpenVINS / sqrtVINS: traj_timing.txt (one line per camera frame, 20 per second)
  VINS-Mono:           vio.tum         (one pose per processed frame, 10 per second)

usage: check_frame_gaps.py <file> <frames per second>
"""
import os
import sys


def first_column(path):
    times = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            times.append(float(line.replace(",", " ").split()[0]))
    return times


def main(path, fps):
    period = 1.0 / fps
    t = first_column(path)
    gaps = [(a - t[0], b - a) for a, b in zip(t, t[1:]) if b - a > 1.5 * period]
    lost = sum(round(g / period) - 1 for _, g in gaps)
    if gaps:
        where = ", ".join(f"{g:.2f} s gap at {s:.1f} s" for s, g in gaps[:10])
        text = (f"WARNING: about {lost} camera frames were lost ({where}; times after the first "
                f"frame). Probably the computer paused; repeat this run before using its numbers.")
    else:
        text = f"OK: no camera frames lost ({len(t)} frames checked)."
    with open(os.path.join(os.path.dirname(path), "frame_check.txt"), "w") as f:
        f.write(text + "\n")
    print(text)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], float(sys.argv[2]))

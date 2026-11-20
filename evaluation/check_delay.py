#!/usr/bin/env python3
"""How far behind the camera did the estimator run? (one run folder with a poses/ bag)

Every pose message carries the time of the camera image it belongs to (header stamp), and the
recorder notes when the message arrived. If the estimator keeps up, arrival time minus image
time stays constant during the run. If it is too slow, images wait in the queue and the
difference grows: the pose arrives later and later after its image.

The smallest difference seen in the run is taken as "no waiting", so the printed delay is the
extra waiting on top of the normal processing time.

Writes delay_check.txt into the run folder (or the file name given as third argument, used
for the second topic of VINS-Mono: what its feature tracker hands to its estimator).
Needs the "rosbags" package (installed with evo): run with ~/venvs/evo/bin/python3.
usage: check_delay.py <run folder> <pose topic, e.g. /ov_msckf/poseimu> [output file name]
"""
import sys
from pathlib import Path

from rosbags.highlevel import AnyReader
from rosbags.typesys import Stores, get_typestore


def main(run: str, topic: str, name: str = "delay_check.txt") -> None:
    rows = []
    with AnyReader([Path(run) / "poses"], default_typestore=get_typestore(Stores.ROS2_HUMBLE)) as reader:
        conns = [c for c in reader.connections if c.topic == topic]
        if not conns:
            sys.exit(f"topic {topic} not found")
        for conn, arrived_ns, raw in reader.messages(connections=conns):
            s = reader.deserialize(raw, conn.msgtype).header.stamp
            rows.append((s.sec + s.nanosec * 1e-9, arrived_ns * 1e-9))
    base = min(a - t for t, a in rows)
    delay = [(t - rows[0][0], a - t - base) for t, a in rows]
    n = len(delay)
    tenth = max(1, n // 10)
    mean = lambda part: sum(d for _, d in part) / len(part)
    worst = max(delay, key=lambda x: x[1])
    lines = [
        f"{'poses checked' if name == 'delay_check.txt' else 'messages checked':<32}{n}",
        f"delay in the first 10 % of run  {mean(delay[:tenth]):.2f} s",
        f"delay in the middle 10 %        {mean(delay[n // 2 - tenth // 2: n // 2 + tenth // 2 + 1]):.2f} s",
        f"delay in the last 10 % of run   {mean(delay[-tenth:]):.2f} s",
        f"largest delay                   {worst[1]:.2f} s (at {worst[0]:.0f} s after the first pose)",
        f"path covers                     {delay[-1][0]:.1f} s of the recording",
    ]
    text = "\n".join(lines) + "\n"
    (Path(run) / name).write_text(text)
    print(text, end="")


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    main(*sys.argv[1:])

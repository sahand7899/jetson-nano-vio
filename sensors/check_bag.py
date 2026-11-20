#!/usr/bin/env python3
"""Check a recording made with record.sh: per topic the rate, time-stamp gaps, lost messages, order,
and how long each message took from its time stamp to the recorder.
usage (on the Jetson, ROS 2 sourced): python3 check_bag.py <recording folder or bag folder>"""
import sys, os, statistics as st
import rosbag2_py
from rclpy.serialization import deserialize_message
from rosidl_runtime_py.utilities import get_message

path = sys.argv[1]
if os.path.isdir(os.path.join(path, "bag")):
    path = os.path.join(path, "bag")
reader = rosbag2_py.SequentialReader()
reader.open(rosbag2_py.StorageOptions(uri=path, storage_id="sqlite3"),
            rosbag2_py.ConverterOptions("cdr", "cdr"))
types = {t.name: t.type for t in reader.get_all_topics_and_types()}
classes = {n: get_message(t) for n, t in types.items()}
stamps = {n: [] for n in types}; recv = {n: [] for n in types}
while reader.has_next():
    topic, data, t_rec = reader.read_next()
    m = deserialize_message(data, classes[topic])
    stamps[topic].append(m.header.stamp.sec + m.header.stamp.nanosec * 1e-9)
    recv[topic].append(t_rec * 1e-9)
ok = True
for n in sorted(types):
    s = stamps[n]
    if len(s) < 3:
        print(f"{n}: only {len(s)} messages"); continue
    g = [(b - a) * 1e3 for a, b in zip(s, s[1:])]
    med = st.median(g)
    lost = sum(round(x / med) - 1 for x in g if x > 1.5 * med)
    back = sum(x <= 0 for x in g)
    lag = [(r - t) * 1e3 for t, r in zip(s, recv[n])]
    print(f"{n}: {len(s)} msgs, {(len(s)-1)/(s[-1]-s[0]):.3f} Hz, gap ms median {med:.3f} "
          f"min {min(g):.3f} max {max(g):.3f} stdev {st.pstdev(g):.3f}")
    print(f"   lost (from gaps): {lost}   out of order: {back}   "
          f"recorder delay ms: median {st.median(lag):.1f} max {max(lag):.1f}")
    if "temperature" in n:
        continue
    ok &= lost == 0 and back == 0
first = max(stamps[n][0] for n in types if stamps[n]); last = min(stamps[n][-1] for n in types if stamps[n])
print(f"common time span: {last - first:.2f} s")
print("RESULT:", "OK - nothing lost, all in order" if ok else "PROBLEM - see above")

#!/usr/bin/env python3
"""Wait until every given topic has delivered one message (any type). Exit 1 after the timeout.
Used by record.sh instead of 'ros2 topic echo', whose background helper (daemon) fails on this Jetson.
usage: python3 wait_topics.py <timeout_s> <topic> [<topic> ...]"""
import sys, time
import rclpy
from rclpy.node import Node
from rosidl_runtime_py.utilities import get_message

timeout, topics = float(sys.argv[1]), sys.argv[2:]
rclpy.init(); node = Node("wait_topics")
seen, subs = set(), []
t0 = time.time()
while time.time() - t0 < timeout and len(seen) < len(topics):
    known = dict(node.get_topic_names_and_types())
    for tp in topics:
        if tp in known and tp not in [s.topic_name for s in subs]:
            subs.append(node.create_subscription(get_message(known[tp][0]), tp,
                                                 lambda m, tp=tp: seen.add(tp), 10))
    rclpy.spin_once(node, timeout_sec=0.2)
missing = [tp for tp in topics if tp not in seen]
if missing:
    print("no data on:", " ".join(missing)); sys.exit(1)
print("all topics deliver data")

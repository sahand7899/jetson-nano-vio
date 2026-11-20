#!/usr/bin/env python3
"""Convert the poses on one topic of a ROS 2 bag to TUM format, which evo reads directly.

Used for the ROS 2 builds of OpenVINS / sqrtVINS, whose pose topic (.../poseimu) is recorded
with "ros2 bag record". Each message becomes one line
    timestamp [s] px py pz qx qy qz qw
using the timestamp in the message header (the camera time the pose belongs to), not the time
the message was recorded. Supported message types: PoseWithCovarianceStamped, PoseStamped,
Odometry.

Needs the "rosbags" package (installed with evo): run with ~/venvs/evo/bin/python3.
usage: ros2_pose_bag_to_tum.py <bag folder> <topic> <output.tum>
"""
import sys
from pathlib import Path

from rosbags.highlevel import AnyReader
from rosbags.typesys import Stores, get_typestore


def pose_of(msg):
    # PoseWithCovarianceStamped and Odometry nest the pose one level deeper than PoseStamped
    pose = msg.pose.pose if hasattr(msg.pose, "pose") else msg.pose
    return pose.position, pose.orientation


def convert(bag: str, topic: str, dst: str) -> int:
    poses = {}
    with AnyReader([Path(bag)], default_typestore=get_typestore(Stores.ROS2_HUMBLE)) as reader:
        conns = [c for c in reader.connections if c.topic == topic]
        if not conns:
            sys.exit(f"topic {topic} not found in {bag}")
        for conn, _, raw in reader.messages(connections=conns):
            msg = reader.deserialize(raw, conn.msgtype)
            stamp = msg.header.stamp
            p, q = pose_of(msg)
            # Integer arithmetic keeps full nanosecond precision (a float would round it)
            t = f"{stamp.sec}.{stamp.nanosec:09d}"
            poses[(stamp.sec, stamp.nanosec)] = f"{t} {p.x} {p.y} {p.z} {q.x} {q.y} {q.z} {q.w}"

    with open(dst, "w") as fout:
        for key in sorted(poses):  # a repeated timestamp keeps the last pose
            fout.write(poses[key] + "\n")
    return len(poses)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    n = convert(*sys.argv[1:])
    print(f"{sys.argv[3]}: {n} poses")

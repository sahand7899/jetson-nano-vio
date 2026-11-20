#!/usr/bin/env python3
"""Check the IMU stream on the Jetson: rate, time-stamp spacing, delay, and (if the board lies still) the values.
usage: python3 check_imu.py [seconds] [topic]     (ROS 2 sourced; the driver must be running)"""
import sys, time, math, statistics as st
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Imu

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 20.0
topic = sys.argv[2] if len(sys.argv) > 2 else "/imu/data_raw"
rclpy.init(); node = Node("imu_check")
S, A, ACC, GYR = [], [], [], []
def cb(m):
    S.append(m.header.stamp.sec + m.header.stamp.nanosec * 1e-9)
    A.append(time.time())
    ACC.append((m.linear_acceleration.x, m.linear_acceleration.y, m.linear_acceleration.z))
    GYR.append((m.angular_velocity.x, m.angular_velocity.y, m.angular_velocity.z))
node.create_subscription(Imu, topic, cb, 1000)
t0 = time.time()
while time.time() - t0 < secs:
    rclpy.spin_once(node, timeout_sec=0.05)
if len(S) < 10:
    sys.exit(f"only {len(S)} messages on {topic}")
gaps = [(b - a) * 1e3 for a, b in zip(S, S[1:])]
lag = [(a - s) * 1e3 for s, a in zip(S, A)]
med = st.median(gaps)
print(f"messages {len(S)} in {S[-1]-S[0]:.1f} s  -> {(len(S)-1)/(S[-1]-S[0]):.3f} Hz")
print(f"stamp gap ms: median {med:.4f}  min {min(gaps):.4f}  max {max(gaps):.4f}  stdev {st.pstdev(gaps):.4f}")
print(f"  non-increasing stamps: {sum(g <= 0 for g in gaps)}   gaps > 1.5x median (lost samples): {sum(g > 1.5*med for g in gaps)}")
print(f"arrival minus stamp ms: median {st.median(lag):.2f}  min {min(lag):.2f}  max {max(lag):.2f}")
for name, data, unit in (("accel", ACC, "m/s^2"), ("gyro", GYR, "rad/s")):
    cols = list(zip(*data))
    print(f"{name} mean  " + "  ".join(f"{st.mean(c):+.4f}" for c in cols) + f"  {unit}"
          f"   stdev " + "  ".join(f"{st.pstdev(c):.4f}" for c in cols))
print(f"|accel| mean {st.mean(math.sqrt(x*x+y*y+z*z) for x, y, z in ACC):.4f} m/s^2 (still board: about 9.81)")

#!/usr/bin/env python3
"""Check the raw camera stream: rate, time-stamp spacing, delay, brightness; saves the last image as PNG.
usage: python3 check_camera.py [seconds] [topic] [png_path]"""
import sys, time, zlib, struct, statistics as st
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Image

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 15.0
topic = sys.argv[2] if len(sys.argv) > 2 else "/camera/image_raw"
png = sys.argv[3] if len(sys.argv) > 3 else "/tmp/camera_check.png"
rclpy.init(); node = Node("camera_check")
S, A, last = [], [], [None]
def cb(m):
    S.append(m.header.stamp.sec + m.header.stamp.nanosec * 1e-9); A.append(time.time()); last[0] = m
node.create_subscription(Image, topic, cb, 100)
t0 = time.time()
while time.time() - t0 < secs:
    rclpy.spin_once(node, timeout_sec=0.05)
if len(S) < 10:
    sys.exit(f"only {len(S)} images on {topic}")
gaps = [(b - a) * 1e3 for a, b in zip(S, S[1:])]
lag = [(a - s) * 1e3 for s, a in zip(S, A)]
med = st.median(gaps)
m = last[0]
print(f"images {len(S)} in {S[-1]-S[0]:.1f} s -> {(len(S)-1)/(S[-1]-S[0]):.2f} Hz   {m.width}x{m.height} {m.encoding}")
print(f"stamp gap ms: median {med:.3f}  min {min(gaps):.3f}  max {max(gaps):.3f}  stdev {st.pstdev(gaps):.3f}")
print(f"  non-increasing: {sum(g <= 0 for g in gaps)}   gaps > 1.5x median (lost images): {sum(g > 1.5*med for g in gaps)}")
print(f"arrival minus stamp ms: median {st.median(lag):.2f}  min {min(lag):.2f}  max {max(lag):.2f}")
px = bytes(m.data)
print(f"brightness: mean {sum(px)/len(px):.1f} of 255   too dark (<10) {100*sum(p < 10 for p in px)/len(px):.1f} %   saturated (>250) {100*sum(p > 250 for p in px)/len(px):.1f} %")
if m.encoding == "mono8":
    rows = b"".join(b"\x00" + px[r*m.step:r*m.step+m.width] for r in range(m.height))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    with open(png, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", m.width, m.height, 8, 0, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))
    print("last image saved to", png)

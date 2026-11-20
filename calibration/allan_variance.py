#!/usr/bin/env python3
"""IMU noise from a long still recording (Allan deviation), for the calibration (Kalibr) and the algorithms.

usage (PC):  ~/venvs/evo/bin/python calibration/allan_variance.py <recording folder> [--skip S] [--topic T]
  <recording folder>  made by sensors/record.sh ... --imu-only (contains bag/), copied to the PC
  --skip S            ignore the first S seconds (warm-up; default 900 = 15 min, use 0 for short tests)
writes into the recording folder:
  allan_result.txt    the four numbers per axis + the chosen values, and how they were read off
  allan_imu.yaml      the same in Kalibr's imu.yaml format
  allan_plot.pdf      Allan deviation per axis with the fitted lines, and the IMU temperature

What the numbers mean (plain words):
  noise density  (white noise) : how much each single reading jitters      -> slope -1/2 part of the curve, read at tau = 1 s
  random walk    (bias drift)  : how fast the slowly changing offset wanders -> slope +1/2 part, read at tau = 3 s
  bias instability             : the flattest point of the curve / 0.664 (reported, not used by the algorithms)
  random walk upper limit      : when no +1/2 part is reached, the largest random walk the curve still allows
                                 (min over tau >= 10 s of adev*sqrt(3/tau)); a bound, not a measurement
Method: overlapping Allan deviation (IEEE Std 952-1997, Annex C); the same quantities as allan_variance_ros
and Kalibr's IMU noise model (github.com/ethz-asl/kalibr/wiki/IMU-Noise-Model).
"""
import argparse, os, sys
import numpy as np
from rosbags.highlevel import AnyReader
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("folder")
ap.add_argument("--skip", type=float, default=900.0)
ap.add_argument("--topic", default="/imu/data_raw")
args = ap.parse_args()
folder = Path(args.folder)
bag = folder / "bag" if (folder / "bag").is_dir() else folder

t, gyr, acc, temp_t, temp = [], [], [], [], []
try:  # ROS 2 Humble bags carry no message definitions: give rosbags the Humble ones
    from rosbags.typesys import Stores, get_typestore
    reader_kwargs = dict(default_typestore=get_typestore(Stores.ROS2_HUMBLE))
except ImportError:
    reader_kwargs = {}
with AnyReader([bag], **reader_kwargs) as reader:
    conns = [c for c in reader.connections if c.topic in (args.topic, "/imu/temperature")]
    for conn, _, raw in reader.messages(connections=conns):
        m = reader.deserialize(raw, conn.msgtype)
        s = m.header.stamp.sec + m.header.stamp.nanosec * 1e-9
        if conn.topic == args.topic:
            t.append(s)
            gyr.append((m.angular_velocity.x, m.angular_velocity.y, m.angular_velocity.z))
            acc.append((m.linear_acceleration.x, m.linear_acceleration.y, m.linear_acceleration.z))
        else:
            temp_t.append(s); temp.append(m.temperature)
t = np.array(t); gyr = np.array(gyr); acc = np.array(acc)
if len(t) < 1000:
    sys.exit(f"only {len(t)} IMU messages")
t0 = t[0]
keep = t >= t0 + args.skip
t, gyr, acc = t[keep], gyr[keep], acc[keep]
dt_all = np.diff(t)
dt = float(np.median(dt_all))
lost = int(np.sum(np.round(dt_all[dt_all > 1.5 * dt] / dt) - 1))
duration = t[-1] - t[0]
print(f"{len(t)} samples, {duration/3600:.2f} h used (first {args.skip:.0f} s skipped), rate {1/dt:.3f} Hz, lost {lost}")


def allan(x, dt):
    """overlapping Allan deviation at ~log-spaced cluster sizes"""
    n = len(x)
    theta = np.concatenate([[0.0], np.cumsum(x) * dt])
    ms = np.unique(np.logspace(0, np.log10((n - 1) / 9), 150).astype(int))  # keep >= ~9 clusters
    taus, adev = [], []
    for m in ms:
        d = theta[2 * m:] - 2 * theta[m:-m] + theta[:-2 * m]
        tau = m * dt
        taus.append(tau)
        adev.append(np.sqrt(np.sum(d * d) / (2 * tau * tau * (n - 2 * m))))
    return np.array(taus), np.array(adev)


def read_off(taus, adev, slope, tau_at, tau_min, tau_max):
    """value of the straight line with the given log-log slope that touches the curve where the curve's
    own slope is closest to it (searched only between tau_min and tau_max: white noise dominates short
    cluster times, bias drift long ones); returns (value at tau_at, tau where it touches, local slope there)"""
    lt, la = np.log10(taus), np.log10(adev)
    local = np.gradient(la, lt)
    allowed = (taus >= tau_min) & (taus <= tau_max)
    if not allowed.any():
        return None, float("nan"), float("nan")
    i = int(np.argmin(np.where(allowed, np.abs(local - slope), np.inf)))
    if abs(local[i] - slope) > 0.15:
        return None, taus[i], local[i]
    b = la[i] - slope * lt[i]
    return 10 ** (slope * np.log10(tau_at) + b), taus[i], local[i]


names = ["x", "y", "z"]
res = {}
for sensor, data, unit_n, unit_k in (("gyroscope", gyr, "rad/s/sqrt(Hz)", "rad/s^2/sqrt(Hz)"),
                                     ("accelerometer", acc, "m/s^2/sqrt(Hz)", "m/s^3/sqrt(Hz)")):
    for k in range(3):
        taus, adev = allan(data[:, k] - data[:, k].mean(), dt)
        n_val, n_tau, n_sl = read_off(taus, adev, -0.5, 1.0, 0.02, 10.0)
        k_val, k_tau, k_sl = read_off(taus, adev, +0.5, 3.0, 10.0, 1e9)
        # upper limit for the random walk: its line K*sqrt(tau/3) can never lie above the measured curve
        drift = taus >= 10.0
        k_ub = float(np.min(adev[drift] * np.sqrt(3.0 / taus[drift]))) if drift.any() else None
        res[(sensor, k)] = dict(taus=taus, adev=adev, N=n_val, N_tau=n_tau, N_sl=n_sl, K_ub=k_ub,
                                K=k_val, K_tau=k_tau, K_sl=k_sl, B=adev.min() / 0.664,
                                B_tau=taus[np.argmin(adev)], unit_n=unit_n, unit_k=unit_k)

lines = [f"Allan deviation of {bag}",
         f"samples {len(t)}, used {duration/3600:.2f} h after skipping {args.skip:.0f} s, rate {1/dt:.3f} Hz, lost samples {lost}",
         f"IMU temperature {min(temp):.1f} .. {max(temp):.1f} C" if temp else "no temperature topic", ""]
chosen = {}
for sensor in ("gyroscope", "accelerometer"):
    lines.append(sensor)
    for k in range(3):
        r = res[(sensor, k)]
        nn = f"{r['N']:.3e}" if r["N"] is not None else "not found"
        kk = f"{r['K']:.3e}" if r["K"] is not None else "not reached (recording too short)"
        lines.append(f"  {names[k]}: noise density {nn} {r['unit_n']} (slope {r['N_sl']:+.2f} at tau {r['N_tau']:.2f} s)   "
                     f"random walk {kk} {r['unit_k']} (slope {r['K_sl']:+.2f} at tau {r['K_tau']:.0f} s)   "
                     f"bias instability {r['B']:.3e} at tau {r['B_tau']:.0f} s   "
                     f"random walk upper limit {r['K_ub']:.3e}")
    ns = [res[(sensor, k)]["N"] for k in range(3) if res[(sensor, k)]["N"] is not None]
    ks = [res[(sensor, k)]["K"] for k in range(3) if res[(sensor, k)]["K"] is not None]
    ubs = [res[(sensor, k)]["K_ub"] for k in range(3) if res[(sensor, k)]["K_ub"] is not None]
    chosen[sensor] = (max(ns) if ns else None, max(ks) if len(ks) == 3 else None, max(ubs) if ubs else None)
    lines.append(f"  chosen (largest of the three axes): noise density {chosen[sensor][0]}, random walk {chosen[sensor][1]}, "
                 f"random walk upper limit {chosen[sensor][2]}")
    lines.append("")
lines.append("These are measured values of a still sensor. Real use (motion, vibration, temperature changes) is noisier;")
lines.append("the factor by which the algorithms inflate them is part of the platform adaptation, the same rule for all.")
text = "\n".join(lines)
print(text)
(folder / "allan_result.txt").write_text(text + "\n")

fmt = lambda v: f"{v:.6e}" if v is not None else "null   # not determined"
(folder / "allan_imu.yaml").write_text(
    "# from calibration/allan_variance.py (Allan deviation of a still recording; values NOT inflated)\n"
    f"rostopic: {args.topic}\n"
    f"update_rate: {1/dt:.3f}\n"
    f"accelerometer_noise_density: {fmt(chosen['accelerometer'][0])}   # m/s^2/sqrt(Hz)\n"
    f"accelerometer_random_walk: {fmt(chosen['accelerometer'][1])}   # m/s^3/sqrt(Hz); upper limit {chosen['accelerometer'][2]:.6e}\n"
    f"gyroscope_noise_density: {fmt(chosen['gyroscope'][0])}   # rad/s/sqrt(Hz)\n"
    f"gyroscope_random_walk: {fmt(chosen['gyroscope'][1])}   # rad/s^2/sqrt(Hz); upper limit {chosen['gyroscope'][2]:.6e}\n")

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
fig, axs = plt.subplots(1, 3, figsize=(16, 5))
for ax, sensor, unit in ((axs[0], "gyroscope", "rad/s"), (axs[1], "accelerometer", "m/s²")):
    for k, col in zip(range(3), ("tab:red", "tab:green", "tab:blue")):
        r = res[(sensor, k)]
        ax.loglog(r["taus"], r["adev"], color=col, label=f"{names[k]}")
        if r["N"] is not None:
            ax.loglog(r["taus"], r["N"] / np.sqrt(r["taus"]), color=col, ls=":", lw=0.8)
        if r["K"] is not None:
            ax.loglog(r["taus"], r["K"] * np.sqrt(r["taus"] / 3), color=col, ls="--", lw=0.8)
    ax.set_title(f"{sensor}: Allan deviation (dotted: noise density, dashed: random walk)", fontsize=9)
    ax.set_xlabel("cluster time tau [s]"); ax.set_ylabel(f"Allan deviation [{unit}]")
    ax.grid(True, which="both", alpha=0.3); ax.legend()
if temp:
    axs[2].plot((np.array(temp_t) - t0) / 60, temp)
    axs[2].axvline(args.skip / 60, color="gray", ls="--", label="analysis starts")
    axs[2].legend()
axs[2].set_title("IMU temperature", fontsize=9); axs[2].set_xlabel("minutes since start"); axs[2].set_ylabel("°C")
axs[2].grid(True, alpha=0.3)
fig.tight_layout()
fig.savefig(folder / "allan_plot.pdf")
print("written:", folder / "allan_result.txt", folder / "allan_imu.yaml", folder / "allan_plot.pdf")

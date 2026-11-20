# calibration

## IMU noise (`allan_variance.py`)

VIO algorithms and Kalibr need four numbers that describe the IMU: the noise density and the
random walk of the gyroscope and of the accelerometer. They are read from an Allan deviation
plot of a long recording with the IMU lying completely still (overlapping Allan deviation,
IEEE Std 952-1997):

- noise density: where the curve falls with slope -1/2, read at τ = 1 s
- random walk: where it rises again with slope +1/2, read at τ = 3 s
- bias instability (flattest point / 0.664) is reported too, but the algorithms do not use it

If the recording is too short, or the sensor too stable, for a +1/2 slope to appear, the script
reports an upper limit for the random walk instead: the largest value whose +1/2 line still stays
below the measured curve.

Recording, on the Jetson (fan off, board on a stable surface, nobody walking around):

```
ssh -t jetson ~/sensors_ws/record.sh allan_static 18000 --imu-only     # 5 hours
```

Analysis, on a PC after copying the recording folder (needs the evo environment from
`evaluation/install_evo.sh`, which also contains `rosbags` and matplotlib):

```
~/venvs/evo/bin/python calibration/allan_variance.py <recording folder> [--skip 900] [--topic /imu/data_raw]
```

`--skip` leaves out the first seconds while the board warms up (default 15 min). The script writes
into the recording folder:

- `allan_result.txt`: all values per axis and how they were read off
- `allan_imu.yaml`: the largest of the three axes in Kalibr's `imu.yaml` format (a random walk that
  could not be determined is left empty, with the upper limit as a comment)
- `allan_plot.pdf`: the curves with the fitted lines, and the IMU temperature over time

The values are for a still sensor. On a moving platform the noise is higher, so algorithms
usually get inflated values; how much is a tuning decision, not part of this script.

Result for the ICM-20948 on the Waveshare board (5 h, 228 Hz, 29 to 31 °C): noise density
1.25e-4 rad/s/√Hz (gyroscope) and 1.29e-3 m/s²/√Hz (accelerometer); random walk below 3.5e-6 and
5.9e-5, no +1/2 slope within 4.75 h.

Camera and camera-IMU calibration with Kalibr will be added after it has been done with the
calibration target.

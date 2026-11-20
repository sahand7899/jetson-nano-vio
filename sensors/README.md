# sensors

Camera and IMU data from the Waveshare IMX219-83 board on a Jetson Nano, as ROS 2 topics
suitable for calibration and VIO. Nothing has to be installed with apt: the IMU driver only needs
ROS 2 Humble, and the camera uses the gscam build that the nano-OS robot software already has in
`~/foxy_ws`.

Copy this folder to the Jetson as `~/sensors_ws` and build once:

```
scp -r sensors jetson:~/sensors_ws
ssh jetson ~/sensors_ws/build.sh        # about 45 s
```

## IMU driver (`icm20948_imu/`)

The ICM-20948 on the camera board is not connected through the camera cable for data. It needs
two wires to the Jetson's 40-pin header:

| IMU board | Jetson header |
|---|---|
| SDA | pin 3 |
| SCL | pin 5 |

These are physical pin numbers. Some carrier boards print labels such as "D3" next to the pins
that do not match the pin numbers, so count the pins. The board itself is powered through the
camera cable. The chip then appears on `/dev/i2c-1` at address 0x68 (check with
`sudo i2cdetect -y -r 1`).

The robot software's own IMU path (MPU-6050 on the robot board) cannot be used when the Jetson
is not on the robot, which is why this driver was written.

Run it on its own with

```
source ~/sensors_ws/install/setup.bash
ros2 run icm20948_imu icm20948_node
```

It publishes `/imu/data_raw` (`sensor_msgs/Imu`, about 228 Hz, reliable QoS, depth 1000,
orientation marked as unknown) and `/imu/temperature` (1 Hz).

How it works: the chip writes every sample into its own FIFO buffer, and the driver empties the
buffer about every 10 ms over I2C. The timestamp of each sample is computed from the chip's own
sample clock (sample count times the measured sample period, with the offset fitted over a
30 s window) instead of the moment Linux happened to read it, so scheduling jitter on the Nano
does not end up in the timestamps. FIFO overflows are detected and reset. Every 10 s it logs
the number of samples, the measured chip rate, overflows and I2C errors.

Parameters (defaults):

| Parameter | Default | Meaning |
|---|---|---|
| `device` | `/dev/i2c-1` | I2C bus |
| `address` | `0x68` | I2C address |
| `sample_rate_div` | 4 | 1125 Hz / (1 + div), so 225 Hz nominal; the chip's clock gives 228.1 Hz |
| `gyro_range_dps` | 500 | ±250, 500, 1000 or 2000 °/s |
| `accel_range_g` | 4 | ±2, 4, 8 or 16 g |
| `gyro_dlpf_cfg`, `accel_dlpf_cfg` | 3 | on-chip low-pass filter, about 51 Hz |
| `poll_period_ms` | 10 | how often the FIFO is read |
| `frame_id` | `imu` | frame of the messages |
| `warmup_s` | 2 | samples dropped after start |
| `clock_window_s` | 30 | window for fitting the chip clock |

Measured with the board standing still: no lost or out-of-order samples over 5 hours, about 4 %
of one core.

## Camera (`camera_raw.sh`)

Starts gscam with a GStreamer pipeline (`nvarguscamerasrc`) that gives VIO-friendly images on
`/camera/image_raw`: greyscale 640x480 at 30 Hz, uncompressed, fixed exposure, no denoising or
edge enhancement, timestamps taken inside the pipeline. It stops the robot software first
(`foxy-bringup`), because only one program can use the camera.

```
~/sensors_ws/camera_raw.sh                     # defaults
EXPOSURE_MS=5 SENSOR=1 ~/sensors_ws/camera_raw.sh
tmux kill-session -t camera                    # stop
```

Settings are environment variables (see the top of the script): `SENSOR` (0 or 1), `EXPOSURE_MS`
(10; also one flicker period of 50 Hz lamps), `GAIN_MAX`, `WIDTH`/`HEIGHT`, `FPS`, and `STAMPS`
(`gst` or `arrival`). With three of four cores busy, `gst` timestamps stayed even (spread
0.27 ms) while arrival timestamps spread to 1.1 ms, so `gst` is the default.

## Recording (`record.sh`)

Starts the IMU driver and the camera, waits until both deliver, records them into a ROS 2 bag
and writes a `recording_info.txt` with the state of the Jetson (temperature, fan, CPU, driver
version and settings, camera settings) at start and end.

```
ssh -t jetson ~/sensors_ws/record.sh test 60              # camera + IMU, 60 s
ssh -t jetson ~/sensors_ws/record.sh allan_static 18000 --imu-only
```

The result goes to `~/recordings/<date_time>_<name>/`. Without a duration it records until
Ctrl-C. `--keep` leaves the sensors running afterwards.

If you start it inside tmux right after a boot, stop the robot software first
(`sudo systemctl stop foxy-bringup`): that service owns the tmux server, and stopping it from
inside the script kills every tmux session, the script's own included.

## Checks

| Script | Checks |
|---|---|
| `check_bag.py <recording>` | per topic: rate, timestamp gaps, lost and out-of-order messages, delay to the recorder |
| `check_imu.py [seconds]` | live IMU stream: rate, spacing, delay, and the values if the board lies still |
| `check_camera.py [seconds]` | live camera stream: rate, spacing, delay, brightness; saves the last image as PNG |
| `wait_topics.py <timeout> <topics>` | waits until every topic has delivered once (used by `record.sh`, because `ros2 topic echo` was unreliable on this Jetson) |

All need ROS 2 sourced on the Jetson.

## Live camera view (`camera_view.sh`)

Shows the camera on a PC in the browser, without recording anything. It runs gscam with a JPEG
pipeline plus `foxglove_bridge` (`sudo apt install ros-humble-foxglove-bridge`, the only extra
package). On the PC, run the Lichtblick viewer, for example with Docker:

```
docker run --rm -p 8080:8080 ghcr.io/lichtblick-suite/lichtblick:latest
```

then open `http://localhost:8080/?ds=foxglove-websocket&ds.url=ws://<jetson address>:8765`
and add an Image panel with `/camera/image_raw/compressed`.

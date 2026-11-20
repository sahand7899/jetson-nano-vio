# vio

Native builds of five VIO algorithms on the Jetson Nano under ROS 2 Humble. None of them builds
or runs correctly on the Nano straight from upstream; the changes that were needed are kept as
small patch files so they can be checked against the original code. Each algorithm is pinned to
one commit.

| Algorithm | Source | Commit |
|---|---|---|
| VINS-Mono | ROS 2 port [dongbo19/VINS-MONO-ROS2](https://github.com/dongbo19/VINS-MONO-ROS2) of HKUST's VINS-Mono | `4c3cf08` |
| VINS-Fusion | ROS 2 port [zinuok/VINS-Fusion-ROS2](https://github.com/zinuok/VINS-Fusion-ROS2) of HKUST's VINS-Fusion | `af78d13` |
| OpenVINS | official [rpng/open_vins](https://github.com/rpng/open_vins) (ROS 2 support upstream) | `6948812` |
| sqrtVINS | official [rpng/sqrtVINS](https://github.com/rpng/sqrtVINS) | `30fafc8` |
| ROVIO | ROS 2 port [JacopoPan/rovio_ros2](https://github.com/JacopoPan/rovio_ros2) of ETH's ROVIO | `54c4947` |

All are run with one camera + IMU and without loop closure. The settings are the authors' own
EuRoC settings; where a port ships different settings, the official file is used or downloaded
for comparison.

## Folder layout

Each algorithm folder has the same scripts. Copy the folder to the Jetson as
`~/<algorithm>_ws`, for example `scp -r vio/openvins jetson:~/openvins_ws`, then run them there
in this order:

| Script | Does |
|---|---|
| `get_source.sh` | clones the pinned commit into `src/` and applies `patches/` |
| `install_deps.sh` | installs the apt packages it needs; `packages_added.txt` lists what it added on our Jetson, so they can be removed again |
| `build.sh` | `colcon build`, one job at a time |
| `run_<algorithm>_euroc.sh <bag> [start] [rate]` | plays one EuRoC ROS 2 bag into the estimator and records its poses, log and a per-second CPU/memory/temperature log into `~/results/<algorithm>/<sequence>/<date_time>/`, with a `run_info.txt` describing the exact code, settings and state of the Jetson |
| `live_demo.sh <sequence>` | the same run inside a four-pane tmux view (estimator log, position, rate, `top`); `--3d` also starts `foxglove_bridge` for a 3D view. Runs started this way are marked as not for measurements. |

VINS-Fusion and ROVIO needed no packages beyond those that OpenVINS and sqrtVINS had already
installed, so they have no `packages_added.txt`. VINS-Mono's folder also holds
`euroc_config.yaml`, HKUST's official EuRoC settings file with loop closure off, which replaces
the one shipped with the port.

Run scripts support variants with changed settings, for example
`VARIANT=slam25 OVERRIDES="max_slam=25" ./run_openvins_euroc.sh <bag>`. The changed settings go into
the run folder and the results into `~/results/openvins-slam25/`, so they never mix with the
authors' settings.

## Building on a 4 GB Nano

- Stop the robot software first: `sudo systemctl stop foxy-bringup`. With it running, a
  parallel build ran out of memory, froze the board and dropped Wi-Fi.
- Add a temporary 4 GB swap file for the build and switch it off again before measuring:

  ```
  sudo fallocate -l 4G /swapfile_build && sudo chmod 600 /swapfile_build
  sudo mkswap /swapfile_build && sudo swapon /swapfile_build
  # after the build:  sudo swapoff /swapfile_build
  ```
- Right after a boot, Ubuntu's automatic updates hold the apt lock for a few minutes;
  `install_deps.sh` waits for it.
- Build times at one job: OpenVINS about 70 min, sqrtVINS about 40 min for its main package.

For measurements, stop the robot software, the camera and any viewer, and run one algorithm at
a time.

## Patches

| Algorithm | Patch | Why |
|---|---|---|
| OpenVINS, sqrtVINS | `fix_imu_queue.patch` | The ROS 2 interface kept only the newest 5 IMU messages (25 ms at 200 Hz), so IMU data was thrown away while an image was processed. The authors' ROS 1 interface keeps 1000; set to 1000. |
| OpenVINS, sqrtVINS, ROVIO | `fix_image_queue.patch` | Room for 100 waiting images instead of 10 (ROVIO: 5). With OpenVINS on the Nano up to about 80 images were waiting at times; with the original queue they would have been dropped silently. |
| sqrtVINS | `fix_ros2_output_timestamp.patch` | The helper that writes the time into outgoing poses took a 32-bit float, which cannot hold a Unix time to better than 128 s, so all poses of a run got one of two timestamps. Now 64-bit, as in the ROS 1 code. |
| VINS-Mono, VINS-Fusion | `fix_result_csv_timestamp.patch` | The ports wrote the time in their own result file in whole seconds; restored to nanoseconds as in the official code. |
| VINS-Mono, VINS-Fusion | `fix_humble_build.patch` | One RViz display line did not compile on Humble (in VINS-Fusion `rclcpp::Duration(0)`, now `Duration(0, 0)`); replaced with the port author's own fix from a later version. Display only. |
| VINS-Fusion | `fix_gpu_mode_off.patch` | The port enables its GPU code, which needs OpenCV built with CUDA; the Nano's Ubuntu OpenCV is not. Switched off as in the port author's later version, so the original CPU code is used. |
| VINS-Fusion | `fix_marginalization_memory.patch` | The port had replaced the authors' `delete factors[i];` with `factors[i] = nullptr;`, so memory from every marginalisation was never freed. Restored. |
| ROVIO | `fix_arm_compile_flags.patch` | On ARM the port compiled with `-Ofast` and `-mtune=cortex-a76`. `-Ofast` allows floating-point reordering that can change results, and the A76 is not the Nano's CPU. Changed to the official `-march=native`. |
| ROVIO | `fix_no_system_install.patch` | A sub-library tried to install a CMake file into `/usr/share`, which fails without root. The library is header-only and already read from the source folder, so the sub-build is skipped. |

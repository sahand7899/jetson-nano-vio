# evaluation

Scripts for a PC with Ubuntu 22.04 (native or WSL) that prepare the EuRoC data and grade the runs
made on the Jetson. Paths are relative to the repository root; the EuRoC data is expected in
`datasets/euroc/` and run folders in `results/jetson_euroc/<algorithm>/<sequence>/<date_time>/`
(neither is part of the repository).

## Setup

```
bash evaluation/install_evo.sh
```

Creates `~/venvs/evo` with [evo](https://github.com/MichaelGrupp/evo) 1.38.0 (trajectory
evaluation) and [rosbags](https://gitlab.com/ternaris/rosbags) 0.11.9 (reads ROS 2 bags without a
ROS installation), and sets evo to save plots to files.

## EuRoC data

Download the room zips (`machine_hall.zip`, `vicon_room1.zip`, `vicon_room2.zip`) from the ETH
Research Collection into `datasets/euroc/`, then

```
evaluation/prepare_euroc.sh                       # extract bags and ground truth
evaluation/convert_euroc_to_ros2.sh V1_02_medium  # ROS 1 bag -> ROS 2 bag (data unchanged)
```

Copy the `<SEQ>_ros2/` folder to the Jetson (`~/datasets/`) for the run scripts in `vio/`.

## Grading one run

After copying a run folder from the Jetson (`~/results/...`) to `results/jetson_euroc/...`:

```
R=results/jetson_euroc/openvins/V1_02_medium/<date_time>
~/venvs/evo/bin/python3 evaluation/ros2_pose_bag_to_tum.py $R/poses /ov_msckf/poseimu $R/vio.tum
evaluation/evaluate_euroc.sh V1_02_medium $R/vio.tum
python3 evaluation/check_frame_gaps.py $R/traj_timing.txt 20
~/venvs/evo/bin/python3 evaluation/check_delay.py $R /ov_msckf/poseimu
python3 evaluation/summarize_run.py $R
```

Pose topic and output rate per algorithm:

| Algorithm | Pose topic | Poses per second | Lost-frame check on |
|---|---|---|---|
| OpenVINS | `/ov_msckf/poseimu` | 20 | `traj_timing.txt` |
| sqrtVINS | `/ov_srvins/poseimu` | 20 | `traj_timing.txt` |
| VINS-Mono | `/vins_estimator/odometry` | 10 | `vio.tum` |
| VINS-Fusion | `/odometry` | 10 | `vio.tum` |
| ROVIO | `/rovio/odometry` | 20 | `vio.tum` |

For VINS-Mono, also run `check_delay.py $R /feature_tracker/feature delay_check_tracker.txt` to
check its feature tracker separately, and `vins_mono_timing.py $R` on a timing run
(`TIMING=1 run_vins-mono_euroc.sh`).

## Scripts

| Script | Does |
|---|---|
| `evaluate_euroc.sh <SEQ> <estimate.tum>` | ATE (RMSE of position after SE(3) alignment, no scale) and RPE over 1 m segments with evo; writes `*_ate.txt`, `*_rpe.txt` and plots next to the estimate |
| `grade_window.sh <run> <from s> <to s\|end>` | the same over a fixed time window, so algorithms that start at different times can be compared over the same stretch |
| `euroc_csv_to_tum.py`, `ros2_pose_bag_to_tum.py` | convert EuRoC CSV files and ROS 2 pose topics to TUM format |
| `check_frame_gaps.py <file> <rate>` | were camera frames lost? (gap longer than 1.5 frame periods) |
| `check_delay.py <run> <topic>` | did the estimator keep up? Compares each pose's image time with its arrival time over the run |
| `summarize_run.py <run>` | time per image, CPU, memory and temperature from the run's logs |
| `list_results.py [--markdown]` | one table of all runs under `results/jetson_euroc/` |
| `vins_mono_timing.py <run>` | time per processing step of VINS-Mono from its debug output |

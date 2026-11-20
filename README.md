# jetson-nano-vio

Code and tools from my bachelor thesis on running visual-inertial odometry (VIO) on a
Jetson Nano. The goal of the thesis is to compare five open-source VIO algorithms on the Nano
and to adapt them to it, first with the EuRoC dataset and then with the Nano's own camera and IMU.

Everything here was used and tested on this setup:

- Jetson Nano 4 GB with the nano-OS "foxy" image (Ubuntu 22.04, L4T R32.7.6, kernel 4.9),
  ROS 2 Humble installed natively
- Waveshare IMX219-83 stereo camera board (two IMX219 cameras and an ICM-20948 IMU)
- a PC with Ubuntu 22.04 (native or WSL) for grading and analysis

## What is in here

| Folder | Contents |
|---|---|
| [`sensors/`](sensors/) | ROS 2 driver for the ICM-20948 on the camera board, a script that starts the camera with fixed settings for VIO, a recording script, stream checks, and a live camera viewer |
| [`vio/`](vio/) | Build and run scripts for VINS-Mono, VINS-Fusion, OpenVINS, sqrtVINS and ROVIO on the Nano under ROS 2 Humble, each pinned to one upstream commit, with the small patches that were needed |
| [`calibration/`](calibration/) | IMU noise analysis (Allan deviation) from a long still recording |
| [`evaluation/`](evaluation/) | EuRoC preparation, accuracy grading with evo (ATE/RPE), and checks for lost frames, delay and resource use |

Each folder has its own README with requirements and usage.

The scripts assume the Jetson user's home folder holds one workspace per part
(`~/sensors_ws`, `~/openvins_ws`, ...). To use a folder, copy it there, for example

```
scp -r sensors jetson:~/sensors_ws
scp -r vio/openvins jetson:~/openvins_ws
```

where `jetson` is an ssh host alias for the Nano.

## Results so far

EuRoC V1_02_medium, one camera + IMU, the authors' own EuRoC settings, loop closure off,
all on the Jetson Nano (one algorithm at a time, robot software stopped). ATE is the RMSE of
the position after aligning the estimated path to the ground truth (evo, SE(3) alignment).

| Algorithm | Runs | ATE median [m] | ATE range [m] | Time per image (median) | Keeps up with the camera? |
|---|---|---|---|---|---|
| OpenVINS | 6 | 0.062 | 0.062 to 0.066 | 48 ms | no, 2.7 to 3.9 s behind at the end |
| sqrtVINS | 5 | 0.078 | 0.069 to 0.078 | 31 ms | yes |
| VINS-Fusion | 5 | 0.115 | 0.115 to 0.116 | 59 ms per optimisation (10 per second) | yes |
| ROVIO | 5 | 0.184 | identical in all runs | not reported | yes |
| VINS-Mono | 5 | 0.230 | 0.191 to 0.376 | not reported | yes |

IMU noise of the camera board's ICM-20948, from a 5-hour still recording (228 Hz, nothing lost):

| | Noise density | Random walk |
|---|---|---|
| Gyroscope | 1.25e-4 rad/s/√Hz | below 3.5e-6 rad/s²/√Hz (no clear +1/2 slope in 4.75 h) |
| Accelerometer | 1.29e-3 m/s²/√Hz | below 5.9e-5 m/s³/√Hz (same) |

## Status

- The sensor driver, camera script and recording tools work and have been checked (no lost
  messages, even timestamps with the processor under load).
- Camera calibration and camera-IMU calibration (Kalibr) have not been done yet, so the
  algorithms have not run on the Nano's own camera so far. The calibration scripts will be added
  once they have been used on real data.
- Only one EuRoC sequence has been tested on the Nano.

## License

Not decided yet. The patch files in `vio/*/patches/` change upstream code and fall under the
licenses of those projects (GPLv3 for VINS-Mono, VINS-Fusion, OpenVINS and sqrtVINS; BSD for
ROVIO).

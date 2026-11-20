#!/bin/bash
# Downloads the ROS 2 port of VINS-Fusion at the exact version chosen for the tests
# (zinuok/VINS-Fusion-ROS2, commit af78d13 of 21 Aug 2023) and applies our four small fixes
# (see patches/ and vio/README.md).
# It also downloads HKUST's official one-camera settings file for EuRoC, only to compare
# with: every run_info.txt lists the differences.
set -e
COMMIT=af78d13438064b856622f2ca65c5dae4fcc0f54a
WS=~/vins-fusion_ws
mkdir -p $WS/src && cd $WS/src
git clone https://github.com/zinuok/VINS-Fusion-ROS2.git
cd VINS-Fusion-ROS2 && git checkout -q $COMMIT
git apply $WS/patches/fix_gpu_mode_off.patch
git apply $WS/patches/fix_humble_build.patch
git apply $WS/patches/fix_result_csv_timestamp.patch
git apply $WS/patches/fix_marginalization_memory.patch
OFFICIAL=https://raw.githubusercontent.com/HKUST-Aerial-Robotics/VINS-Fusion/be55a937a57436548ddfb1bd324bc1e9a9e828e0/config/euroc
curl -fsSL -o $WS/euroc_mono_imu_config_official.yaml $OFFICIAL/euroc_mono_imu_config.yaml
curl -fsSL -o $WS/cam0_mei_official.yaml $OFFICIAL/cam0_mei.yaml
git rev-parse HEAD; git status --short

#!/bin/bash
# Downloads the ROS 2 port of VINS-Mono at the exact version used for the tests and applies
# the two small fixes (see patches/ and vio/README.md).
# The settings file of the port is replaced by the official one of HKUST (with loop closure
# off): ~/vins-mono_ws/euroc_config.yaml (euroc_config.yaml in this folder).
set -e
COMMIT=4c3cf08fa5d9b57f3be9bd49241915e968ee2e1e
WS=~/vins-mono_ws
mkdir -p $WS/src && cd $WS/src
git clone https://github.com/dongbo19/VINS-MONO-ROS2.git
cd VINS-MONO-ROS2 && git checkout -q $COMMIT
git apply $WS/patches/fix_result_csv_timestamp.patch
git apply $WS/patches/fix_humble_build.patch
cp $WS/euroc_config.yaml config_pkg/config/euroc/euroc_config.yaml
# HKUST's own settings file, only to compare with: every run_info.txt lists the differences
curl -fsSL -o $WS/euroc_config_official.yaml https://raw.githubusercontent.com/HKUST-Aerial-Robotics/VINS-Mono/90dabb5ec79946ae42fd2e1e91d4e69aabe1e25d/config/euroc/euroc_config.yaml
git rev-parse HEAD; git status --short

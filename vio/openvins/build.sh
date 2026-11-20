#!/bin/bash
# Builds OpenVINS (ov_core + ov_init + ov_msckf), one compile job at a time (4 GB RAM)
cd ~/openvins_ws
source /opt/ros/humble/setup.bash
date +"BUILD_START %s"
MAKEFLAGS=-j1 colcon build --executor sequential --packages-up-to ov_msckf \
  --event-handlers console_direct+ --cmake-args -DCMAKE_BUILD_TYPE=Release
echo "BUILD_EXIT $?"; date +"BUILD_END %s"

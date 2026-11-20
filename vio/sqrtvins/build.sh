#!/bin/bash
# Builds sqrtVINS (ov_core + ov_srvins), one compile job at a time (4 GB RAM)
cd ~/sqrtvins_ws
source /opt/ros/humble/setup.bash
date +"BUILD_START %s"
MAKEFLAGS=-j1 colcon build --executor sequential --packages-up-to ov_srvins \
  --event-handlers console_direct+ --cmake-args -DCMAKE_BUILD_TYPE=Release
echo "BUILD_EXIT $?"; date +"BUILD_END %s"

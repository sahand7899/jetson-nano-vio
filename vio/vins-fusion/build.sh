#!/bin/bash
# Builds VINS-Fusion's odometry program (package "vins", program vins_node) and the camera
# model package it needs. The loop-closure package (loop_fusion) and the GPS package
# (global_fusion) are NOT built (project rule: no loop closure; no GPS used).
# Ceres 2.1.0 comes from ~/vins-fusion_ws/ceres (install_deps.sh), not from the system.
cd ~/vins-fusion_ws
source /opt/ros/humble/setup.bash
date +"BUILD_START %s"
MAKEFLAGS=-j${JOBS:-2} colcon build --executor sequential \
  --packages-up-to vins \
  --event-handlers console_direct+ \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DCeres_DIR=$HOME/vins-fusion_ws/ceres/lib/cmake/Ceres
echo "BUILD_EXIT $?"; date +"BUILD_END %s"

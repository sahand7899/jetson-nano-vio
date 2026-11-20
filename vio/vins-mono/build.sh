#!/bin/bash
# Builds VINS-Mono's two VIO programs (feature_tracker, vins_estimator) and what they need
# (camera_model, config_pkg). The loop-closure program pose_graph, ar_demo and
# benchmark_publisher are NOT built (project rule: no loop closure).
cd ~/vins-mono_ws
source /opt/ros/humble/setup.bash
date +"BUILD_START %s"
MAKEFLAGS=-j${JOBS:-2} colcon build --executor sequential \
  --packages-up-to config_pkg feature_tracker vins_estimator \
  --event-handlers console_direct+ \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DCeres_DIR=$HOME/vins-mono_ws/ceres/lib/cmake/Ceres
echo "BUILD_EXIT $?"; date +"BUILD_END %s"

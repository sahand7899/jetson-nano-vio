#!/bin/bash
# Build the sensor drivers on the Jetson (no apt packages needed; uses ROS 2 Humble already installed).
# usage (on the Jetson): ~/sensors_ws/build.sh      -> run: ros2 run icm20948_imu icm20948_node
set -eo pipefail
source /opt/ros/humble/setup.bash
cd ~/sensors_ws
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release 2>&1 | tail -20

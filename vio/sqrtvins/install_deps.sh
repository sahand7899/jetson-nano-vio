#!/bin/bash
# Dependencies for sqrtVINS (stage A). Waits for the automatic updates to release the apt lock.
set -e
LOG=~/sqrtvins_ws/install_deps.log
dpkg-query -W -f="\${Package}\n" | sort > ~/sqrtvins_ws/packages_before.txt
echo "Waiting for automatic updates to finish (apt lock)..."
sudo apt-get -o DPkg::Lock::Timeout=7200 update 2>&1 | tee $LOG
sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=7200 install -y --no-install-recommends \
  libopencv-dev libopencv-contrib-dev \
  libboost-system-dev libboost-filesystem-dev libboost-thread-dev libboost-date-time-dev \
  ros-humble-cv-bridge ros-humble-image-transport \
  ros-humble-ros2bag ros-humble-rosbag2-transport ros-humble-rosbag2-storage-default-plugins 2>&1 | tee -a $LOG
dpkg-query -W -f="\${Package}\n" | sort > ~/sqrtvins_ws/packages_after.txt
comm -13 ~/sqrtvins_ws/packages_before.txt ~/sqrtvins_ws/packages_after.txt > ~/sqrtvins_ws/packages_added.txt
echo "DEPS_DONE: $(wc -l < ~/sqrtvins_ws/packages_added.txt) packages added" | tee -a $LOG

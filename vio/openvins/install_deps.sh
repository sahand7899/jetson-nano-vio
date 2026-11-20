#!/bin/bash
# Dependencies for OpenVINS on the Jetson.
# The packages that sqrtVINS needed (OpenCV, Boost, cv_bridge, rosbag2: list in
# packages_kept_from_sqrtvins.txt) are the same ones OpenVINS needs, so they stayed installed.
# OpenVINS needs one thing more: the Ceres solver (used by its start-up code, ov_init),
# the Ubuntu 22.04 version, exactly as in the authors' own Dockerfile_ros2_22_04.
set -e
WS=~/openvins_ws
LOG=$WS/install_deps.log
dpkg-query -W -f="\${Package}\n" | sort > $WS/packages_before.txt
sudo apt-get -o DPkg::Lock::Timeout=7200 update 2>&1 | tee $LOG
sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=7200 install -y --no-install-recommends \
  libceres-dev libgoogle-glog-dev libgflags-dev libsuitesparse-dev 2>&1 | tee -a $LOG
dpkg-query -W -f="\${Package}\n" | sort > $WS/packages_after.txt
comm -13 $WS/packages_before.txt $WS/packages_after.txt > $WS/packages_added.txt
echo "DEPS_DONE: $(wc -l < $WS/packages_added.txt) packages added" | tee -a $LOG

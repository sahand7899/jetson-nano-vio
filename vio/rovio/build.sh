#!/bin/bash
# Builds ROVIO (package rovio, program rovio_node) and its message package rovio_interfaces.
# The 3D viewer (MAKE_SCENE) stays off, as in the official default. ROVIO's code is very
# heavy to compile (one file needs about 2 GB of memory), so one compile job at a time.
# kindr comes from ~/rovio_ws/kindr (install_deps.sh).
cd ~/rovio_ws
source /opt/ros/humble/setup.bash
date +"BUILD_START %s"
# The port's README installs kindr into the system (/usr/local); here it stays in its own
# folder, so the compiler is told where its headers are. Nothing else changes.
export CPLUS_INCLUDE_PATH=$HOME/rovio_ws/kindr/include${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}
MAKEFLAGS=-j${JOBS:-1} colcon build --executor sequential \
  --packages-up-to rovio \
  --event-handlers console_direct+ \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$HOME/rovio_ws/kindr
echo "BUILD_EXIT $?"; date +"BUILD_END %s"

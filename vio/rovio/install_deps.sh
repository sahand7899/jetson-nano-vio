#!/bin/bash
# Dependencies for ROVIO (ROS 2 port) on the Jetson.
# All ROS 2 packages and yaml-cpp it needs are already installed (checked 18 Nov 2026).
# The one thing missing is kindr, ETH's small header-only library for rotations, which the
# filter library needs. It is taken from its official repository at a fixed commit (the
# newest; the port's README also uses the newest) and installed only inside
# ~/rovio_ws/kindr (not into the system): removing the folder removes it completely.
set -e
WS=~/rovio_ws
KINDR_COMMIT=22a19ddd30ccfeba72bb2c35361e090bca7d16ec
LOG=$WS/install_deps.log
dpkg-query -W -f="\${Package}\n" | sort > $WS/packages_before.txt
rm -rf $WS/kindr-src $WS/kindr
git clone -q https://github.com/ethz-asl/kindr.git $WS/kindr-src 2>&1 | tee $LOG
git -C $WS/kindr-src checkout -q $KINDR_COMMIT
echo "kindr commit: $(git -C $WS/kindr-src rev-parse HEAD)" | tee -a $LOG $WS/kindr_version.txt
mkdir $WS/kindr-src/build && cd $WS/kindr-src/build
cmake .. -DCMAKE_INSTALL_PREFIX=$WS/kindr -DBUILD_TEST=OFF 2>&1 | tee -a $LOG
make install 2>&1 | tail -3 | tee -a $LOG
cd $WS && rm -rf $WS/kindr-src
dpkg-query -W -f="\${Package}\n" | sort > $WS/packages_after.txt
comm -13 $WS/packages_before.txt $WS/packages_after.txt > $WS/packages_added.txt
echo "DEPS_DONE ($(wc -l < $WS/packages_added.txt) Ubuntu packages added)" | tee -a $LOG

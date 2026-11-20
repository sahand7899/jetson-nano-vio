#!/bin/bash
# Dependencies for VINS-Fusion (ROS 2 port) on the Jetson.
# Everything except the Ceres Solver is already installed from the earlier algorithms
# (OpenCV, cv_bridge, Boost, glog, gflags, Eigen). The ROS 2 port asks for Ceres 2.1.0
# (its README); Ubuntu 22.04 only has 2.0.0, and VINS-Mono's 1.14.0 is too old for it.
# So Ceres 2.1.0 is built from its official source and installed only inside
# ~/vins-fusion_ws/ceres (not into the system): removing the folder removes it completely,
# and it cannot mix with the Ceres versions of OpenVINS (2.0, system) or VINS-Mono (1.14).
# Built like VINS-Mono's: without SuiteSparse, CXSparse, LAPACK and CUDA. VINS-Fusion's
# odometry uses only the DENSE_SCHUR solver; its GPU option is off.
set -e
WS=~/vins-fusion_ws
LOG=$WS/install_deps.log
JOBS=${JOBS:-2}
mkdir -p $WS
dpkg-query -W -f="\${Package}\n" | sort > $WS/packages_before.txt
date +"CERES_START %s" | tee $LOG
rm -rf $WS/ceres-src $WS/ceres
git clone --depth 1 --branch 2.1.0 https://github.com/ceres-solver/ceres-solver.git $WS/ceres-src 2>&1 | tee -a $LOG
echo "ceres 2.1.0 commit: $(git -C $WS/ceres-src rev-parse HEAD)" | tee -a $LOG $WS/ceres_version.txt
mkdir $WS/ceres-src/build && cd $WS/ceres-src/build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$WS/ceres \
  -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DBUILD_BENCHMARKS=OFF \
  -DSUITESPARSE=OFF -DCXSPARSE=OFF -DLAPACK=OFF -DUSE_CUDA=OFF 2>&1 | tee -a $LOG
make -j$JOBS 2>&1 | tee -a $LOG
make install 2>&1 | tail -3 | tee -a $LOG
cd $WS && rm -rf $WS/ceres-src
dpkg-query -W -f="\${Package}\n" | sort > $WS/packages_after.txt
comm -13 $WS/packages_before.txt $WS/packages_after.txt > $WS/packages_added.txt
date +"CERES_END %s" | tee -a $LOG
echo "CERES_DONE ($(wc -l < $WS/packages_added.txt) Ubuntu packages added)" | tee -a $LOG

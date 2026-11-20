#!/bin/bash
# Dependencies for VINS-Mono (ROS 2 port) on the Jetson.
#  1. One Ubuntu package more than the Jetson already has: the "program_options" part of
#     Boost, which the port's camera_model package asks for. (OpenCV, cv_bridge, glog, gflags,
#     Eigen and the other Boost parts are already installed from the earlier algorithms.)
#  2. Ceres Solver 1.14.0, the version the VINS-Mono authors name in their README, built from
#     its official source. It is installed into ~/vins-mono_ws/ceres only (not into the
#     system), so removing the folder removes it completely.
#     Built without SuiteSparse, CXSparse and LAPACK: the VIO part of VINS-Mono only uses
#     Ceres's DENSE_SCHUR solver with Eigen (estimator.cpp, initial_sfm.cpp); only the
#     loop-closure program (pose_graph, not built) asks for a sparse solver.
set -e
WS=~/vins-mono_ws
LOG=$WS/install_deps.log
JOBS=${JOBS:-2}
dpkg-query -W -f="\${Package}\n" | sort > $WS/packages_before.txt
sudo apt-get -o DPkg::Lock::Timeout=7200 update 2>&1 | tee $LOG
sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=7200 install -y --no-install-recommends \
  libboost-program-options-dev libgoogle-glog-dev libgflags-dev libeigen3-dev 2>&1 | tee -a $LOG
dpkg-query -W -f="\${Package}\n" | sort > $WS/packages_after.txt
comm -13 $WS/packages_before.txt $WS/packages_after.txt > $WS/packages_added.txt
echo "DEPS_DONE: $(wc -l < $WS/packages_added.txt) packages added" | tee -a $LOG

date +"CERES_START %s" | tee -a $LOG
rm -rf $WS/ceres-src $WS/ceres
git clone --depth 1 --branch 1.14.0 https://github.com/ceres-solver/ceres-solver.git $WS/ceres-src 2>&1 | tee -a $LOG
echo "ceres commit: $(git -C $WS/ceres-src rev-parse HEAD)" | tee -a $LOG $WS/ceres_version.txt
mkdir $WS/ceres-src/build && cd $WS/ceres-src/build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$WS/ceres \
  -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DBUILD_BENCHMARKS=OFF \
  -DSUITESPARSE=OFF -DCXSPARSE=OFF -DLAPACK=OFF 2>&1 | tee -a $LOG
make -j$JOBS 2>&1 | tee -a $LOG
make install 2>&1 | tail -3 | tee -a $LOG
cd $WS && rm -rf $WS/ceres-src
date +"CERES_END %s" | tee -a $LOG
echo "CERES_DONE" | tee -a $LOG

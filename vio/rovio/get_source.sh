#!/bin/bash
# Downloads the ROS 2 port of ROVIO at the exact version chosen for the tests
# (JacopoPan/rovio_ros2, commit 54c4947 of 12 Nov 2026, with its filter library
# lightweight_filtering at the official commit 0c8517a) and applies our three small fixes
# (see patches/ and vio/README.md).
# It also downloads ETH's official settings files, only to compare with: every run_info.txt
# lists the differences.
set -e
COMMIT=54c4947bb8e5e28af96e3eb6f87efa73b060cf06
LWF_COMMIT=0c8517a5eb19a00a4f8d36dac4ffdc45dac6a363
WS=~/rovio_ws
mkdir -p $WS/src && cd $WS/src
git clone https://github.com/JacopoPan/rovio_ros2.git
cd rovio_ros2 && git checkout -q $COMMIT && git submodule update -q --init
[ "$(git -C rovio/lightweight_filtering rev-parse HEAD)" = "$LWF_COMMIT" ] || { echo "lightweight_filtering is not at $LWF_COMMIT" >&2; exit 1; }
git apply $WS/patches/fix_arm_compile_flags.patch
git apply $WS/patches/fix_image_queue.patch
git apply $WS/patches/fix_no_system_install.patch
OFFICIAL=https://raw.githubusercontent.com/ethz-asl/rovio/34735c0bfd786d44f6d21d31c0776290f1f91185/cfg
curl -fsSL -o $WS/rovio_official.info $OFFICIAL/rovio.info
curl -fsSL -o $WS/euroc_cam0_official.yaml $OFFICIAL/euroc_cam0.yaml
git rev-parse HEAD; git status --short; echo "lightweight_filtering: $(git -C rovio/lightweight_filtering rev-parse HEAD)"

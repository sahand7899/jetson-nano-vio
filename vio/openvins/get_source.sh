#!/bin/bash
# Downloads the official OpenVINS code at the exact version used for the tests and applies
# the two small changes (see patches/ and vio/README.md).
set -e
COMMIT=69488123ed9362dd44b6f28e7f4680abbff1442b
mkdir -p ~/openvins_ws/src && cd ~/openvins_ws/src
git clone https://github.com/rpng/open_vins.git
cd open_vins && git checkout -q $COMMIT
git apply ~/openvins_ws/patches/fix_imu_queue.patch
git apply ~/openvins_ws/patches/fix_image_queue.patch
git rev-parse HEAD; git status --short

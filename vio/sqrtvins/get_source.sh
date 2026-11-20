#!/bin/bash
# Downloads the official sqrtVINS code at the exact version used for the tests and applies the
# three small changes (see patches/ and vio/README.md), in the
# same order as in the earlier desktop build.
# Written on 18 Nov 2026 for the reinstall; the first install (15 Nov) used the same commands.
set -e
COMMIT=30fafc89d89cfb896d06fdaa68fbda8545e02e9f
mkdir -p ~/sqrtvins_ws/src && cd ~/sqrtvins_ws/src
git clone https://github.com/rpng/sqrtVINS.git
cd sqrtVINS && git checkout -q $COMMIT
git apply ~/sqrtvins_ws/patches/fix_ros2_output_timestamp.patch
git apply ~/sqrtvins_ws/patches/fix_imu_queue.patch
git apply ~/sqrtvins_ws/patches/fix_image_queue.patch
git rev-parse HEAD; git status --short
# must match the five tested runs of 15 Nov (run_info.txt):
# 7dc979b4bfcd0d1f1ffaf72c9a023017edebbb7b91e9d362034d3f37a79fbafb
echo "sha256 of all differences (git diff): $(git diff | sha256sum | cut -d" " -f1)"

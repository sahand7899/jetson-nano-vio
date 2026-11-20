#!/usr/bin/env bash
# Converts EuRoC ROS 1 bags (<SEQ>.bag) into ROS 2 bags that ROS 2 Humble can play.
# The ROS 2 bag is a folder next to the ROS 1 bag:
#   datasets/euroc/<room>/<SEQ>/<SEQ>.bag    ROS 1 bag (from ETH, unchanged)
#   datasets/euroc/<room>/<SEQ>/<SEQ>_ros2/  ROS 2 bag: metadata.yaml + <SEQ>_ros2.db3
#
# The conversion only changes the container format, not the data: every message (images, IMU,
# ground-truth position) keeps its exact timestamp and values. It uses rosbags-convert from the
# "rosbags" Python package (installed together with evo in ~/venvs/evo).
#   --dst-storage sqlite3 : the storage format Humble's "ros2 bag play" reads out of the box
#   --dst-version 8       : the oldest ROS 2 bag format rosbags can write; Humble reads it
#
# usage (PC with Ubuntu 22.04, native or WSL):
#   evaluation/convert_euroc_to_ros2.sh MH_01_easy            # one sequence
#   evaluation/convert_euroc_to_ros2.sh MH_01_easy V1_01_easy # several
#   evaluation/convert_euroc_to_ros2.sh --all                 # every <SEQ>.bag found
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONVERT="$HOME/venvs/evo/bin/rosbags-convert"
[[ $# -gt 0 ]] || { echo "usage: $0 <sequence> [...] | --all" >&2; exit 1; }

if [[ "$1" == "--all" ]]; then
  mapfile -t BAGS < <(find "$ROOT/datasets/euroc" -name '*.bag' | sort)
else
  BAGS=()
  for seq in "$@"; do
    bag="$(find "$ROOT/datasets/euroc" -name "$seq.bag" -print -quit)"
    [[ -n "$bag" ]] || { echo "Could not find $seq.bag under datasets/euroc/" >&2; exit 1; }
    BAGS+=("$bag")
  done
fi

for bag in "${BAGS[@]}"; do
  dst="${bag%.bag}_ros2"
  if [[ -f "$dst/metadata.yaml" ]]; then
    echo "skip $(basename "$bag") ($(basename "$dst") already exists)"
    continue
  fi
  rm -rf "$dst"   # a half-written folder from an interrupted run
  echo "Converting $(basename "$bag") ..."
  "$CONVERT" --src "$bag" --dst "$dst" --dst-storage sqlite3 --dst-version 8
done
echo "Done."

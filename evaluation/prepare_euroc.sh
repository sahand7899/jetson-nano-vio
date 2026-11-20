#!/usr/bin/env bash
# Extracts the EuRoC room zips downloaded from the ETH Research Collection
# (machine_hall.zip, vicon_room1.zip, vicon_room2.zip in datasets/euroc/).
#
# Each room zip holds, per sequence, a ROS 1 bag and an "ASL" zip (same data as image
# files + ground truth). Result per sequence:
#   datasets/euroc/<room>/<SEQ>/<SEQ>.bag   ROS bag, used by all algorithms
#   datasets/euroc/<room>/<SEQ>/<SEQ>.zip   ASL zip (kept, only small files extracted)
#   datasets/euroc/<room>/<SEQ>/mav0/...     ground truth + sensor calibration files
#   datasets/euroc/groundtruth/<SEQ>.tum     ground truth in TUM format for evo
#
# Bags that already exist are skipped, so the room zips may also be extracted by other means first.
#
# usage (PC with Ubuntu 22.04, native or WSL):
#   evaluation/prepare_euroc.sh                       # extract everything
#   evaluation/prepare_euroc.sh --ground-truth-only   # room zips already extracted
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E="$ROOT/datasets/euroc"
ROOMS=(machine_hall vicon_room1 vicon_room2)
[[ "${1:-}" == "--ground-truth-only" ]] && ROOMS=()

for room in "${ROOMS[@]}"; do
  if [[ ! -f "$E/$room.zip" ]]; then
    echo "skip $room (no $room.zip)"
    continue
  fi
  echo "Extracting $room.zip ..."
  # -n: never overwrite (safe to re-run); macOS metadata files are left out
  unzip -n -q "$E/$room.zip" -x '*.DS_Store' '*/._*' -d "$E"
done

mkdir -p "$E/groundtruth"
for asl in "$E"/*/*/*.zip; do
  seq_dir="$(dirname "$asl")"
  seq="$(basename "$asl" .zip)"
  # Only ground truth and calibration text files; the images are already in the bag
  unzip -n -q "$asl" '*state_groundtruth_estimate0/*' '*sensor.yaml' '*body.yaml' -x '*.DS_Store' '__MACOSX/*' -d "$seq_dir"
  gt_csv="$(find "$seq_dir" -path '*state_groundtruth_estimate0/data.csv' -print -quit)"
  python3 "$ROOT/evaluation/euroc_csv_to_tum.py" "$gt_csv" "$E/groundtruth/$seq.tum"
done

echo
echo "Bags:"
find "$E" -name '*.bag' -printf '  %P  (%s bytes)\n' | sort

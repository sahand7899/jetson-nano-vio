#!/usr/bin/env bash
# Compares an estimated trajectory (TUM format) with the EuRoC ground truth using evo.
#
#   ATE - Absolute Trajectory Error: the estimate is aligned to the ground truth once
#         (rotation + translation, no scale, because the IMU makes scale observable), then
#         the distance between estimated and true position is measured at every timestamp.
#         Reported as RMSE in metres -> "how far off is the whole path?"
#   RPE - Relative Pose Error over 1 m pieces of the path -> "how fast does it drift?"
#
# usage: evaluation/evaluate_euroc.sh <sequence, e.g. MH_01_easy> <estimate.tum> [label]
# Writes ate.txt, rpe.txt, ate.zip, rpe.zip and ate_plot*.pdf next to the estimate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEQ="$1"
EST="$2"
LABEL="${3:-$(basename "$EST" .tum)}"
OUTDIR="$(dirname "$EST")"
export PATH="$HOME/venvs/evo/bin:$PATH"
export MPLBACKEND=Agg   # save plots to files instead of opening windows

# Ground truth: EuRoC ASL folder (mav0/state_groundtruth_estimate0/data.csv), converted once
GT_TUM="$ROOT/datasets/euroc/groundtruth/$SEQ.tum"
if [[ ! -s "$GT_TUM" ]]; then
  GT_CSV="$(find "$ROOT/datasets/euroc" -path "*$SEQ*/state_groundtruth_estimate0/data.csv" -print -quit)"
  if [[ -z "$GT_CSV" ]]; then
    echo "No ground truth found for $SEQ (expected .../$SEQ/mav0/state_groundtruth_estimate0/data.csv)" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$GT_TUM")"
  python3 "$ROOT/evaluation/euroc_csv_to_tum.py" "$GT_CSV" "$GT_TUM"
fi

evo_ape tum "$GT_TUM" "$EST" --align --pose_relation trans_part --no_warnings \
  --save_results "$OUTDIR/${LABEL}_ate.zip" --save_plot "$OUTDIR/${LABEL}_ate_plot.pdf" \
  | tee "$OUTDIR/${LABEL}_ate.txt"

evo_rpe tum "$GT_TUM" "$EST" --align --pose_relation trans_part --delta 1 --delta_unit m \
  --no_warnings --save_results "$OUTDIR/${LABEL}_rpe.zip" \
  | tee "$OUTDIR/${LABEL}_rpe.txt"

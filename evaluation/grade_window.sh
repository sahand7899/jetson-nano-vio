#!/usr/bin/env bash
# Grades a finished run again, but only over one part of the flight ("time window").
# Nothing is run again: the saved path (vio.tum) is cut to the window and compared with the
# ground truth exactly as in the normal evaluation (evaluation/evaluate_euroc.sh).
#
# Why: algorithms start producing a path at different moments. To compare them fairly, all
# are graded over the same window, in addition to the grade over each one's own full path.
#
# Times are seconds counted from the first message of the recording, the same clock that
# "--start" of the run scripts uses.
#
# usage (PC with Ubuntu 22.04, native or WSL):
#   evaluation/grade_window.sh <run folder> <from s> <to s | end> [label]
#   evaluation/grade_window.sh results/jetson_euroc/openvins/V1_02_medium/20261116_041145 30 end
# Writes vio_<label>.tum, vio_<label>_ate.txt, vio_<label>_rpe.txt and vio_<label>_window.txt
# into the run folder (label = "common" unless given).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="${1:?usage: $0 <run folder> <from s> <to s | end> [label]}"
FROM="${2:?from which second of the recording?}"
TO="${3:-end}"
LABEL="${4:-common}"
RUN="$(cd "$RUN" && pwd)"
SEQ="$(basename "$(dirname "$RUN")")"

META="$(find "$ROOT/datasets/euroc" -path "*/${SEQ}_ros2/metadata.yaml" -print -quit)"
[[ -n "$META" ]] || { echo "No ROS 2 bag found for $SEQ (needed for the recording's start time)" >&2; exit 1; }

python3 - "$META" "$RUN/vio.tum" "$RUN/vio_${LABEL}.tum" "$FROM" "$TO" "$RUN/vio_${LABEL}_window.txt" <<'EOF'
import re, sys
meta, src, dst, t_from, t_to, note = sys.argv[1:7]
t0 = int(re.search(r"nanoseconds_since_epoch:\s*(\d+)", open(meta).read()).group(1)) / 1e9
lo = t0 + float(t_from)
hi = float("inf") if t_to == "end" else t0 + float(t_to)
rows = [l for l in open(src) if l.strip() and not l.startswith("#")]
kept = [l for l in rows if lo <= float(l.split()[0]) <= hi]
if len(kept) < 10:
    sys.exit(f"only {len(kept)} poses inside the window; nothing to grade")
open(dst, "w").writelines(kept)
first, last = float(kept[0].split()[0]) - t0, float(kept[-1].split()[0]) - t0
text = (f"window asked for:   {t_from} s to {t_to} (seconds from the start of the recording)\n"
        f"recording start:    {t0:.9f} (first message in the ROS 2 bag)\n"
        f"poses in the run:   {len(rows)}\n"
        f"poses in window:    {len(kept)}  (from {first:.2f} s to {last:.2f} s)\n")
open(note, "w").write(text)
print(text, end="")
EOF

"$ROOT/evaluation/evaluate_euroc.sh" "$SEQ" "$RUN/vio_${LABEL}.tum"

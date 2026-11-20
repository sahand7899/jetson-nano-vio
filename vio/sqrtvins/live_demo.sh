#!/usr/bin/env bash
# Shows one sqrtVINS run on the Jetson live, in a terminal window split into four parts.
# This is a run for WATCHING: the viewer tools use processor time, so its numbers do not go
# into the results (run_info.txt of the run says so).
#
#   +---------------------------+---------------------------+
#   | 1 estimator messages      | 2 position x, y, z [m]    |
#   |   (start-up, warnings)    |   ros2 topic echo         |
#   +---------------------------+---------------------------+
#   | 3 poses per second        | 4 processor load          |
#   |   ros2 topic hz           |   top                     |
#   +---------------------------+---------------------------+
#
# usage, from the laptop (Windows Terminal or PowerShell; make the window large first):
#   ssh -t jetson ./sqrtvins_ws/live_demo.sh V1_02_medium
#   ssh -t jetson ./sqrtvins_ws/live_demo.sh MH_03_medium 17.5 0.5   # start 17.5 s in, half speed
#   ssh -t jetson ./sqrtvins_ws/live_demo.sh V1_02_medium --3d       # also feed the graphical viewer
#
# --3d starts the "Foxglove bridge" in a second tmux window (Ctrl+B, then 1 shows it; Ctrl+B,
# then 0 goes back). It offers all ROS 2 topics on network port 8765, so the Lichtblick viewer
# on the laptop can draw the path and the camera picture. On the laptop open
#   http://localhost:8080/?ds=foxglove-websocket&ds.url=ws://<address of the Jetson>:8765
#
# Leave the view:  Ctrl+B, then D   (the run continues; come back with: ssh -t jetson tmux attach -t vio)
# Close it:        Ctrl+B, then :   type  kill-session  and press Enter
set -eo pipefail

VIEW3D=0
ARGS=()
for a in "$@"; do if [[ "$a" == "--3d" ]]; then VIEW3D=1; else ARGS+=("$a"); fi; done
SEQ="${ARGS[0]:?usage: $0 <recording, e.g. V1_02_medium> [start: authors | seconds] [playback rate] [--3d]}"
START="${ARGS[1]:-authors}"
RATE="${ARGS[2]:-1.0}"
BAG="$HOME/datasets/${SEQ}_ros2"
[[ -f "$BAG/metadata.yaml" ]] || { echo "Recording not found on the Jetson: $BAG" >&2; exit 1; }

S=vio
TOPIC=/ov_srvins/poseimu
ROS="source /opt/ros/humble/setup.bash"
# wait until the estimator offers its pose topic
WAIT="$ROS; echo 'waiting for the estimator ...'; until ros2 topic list 2>/dev/null | grep -q $TOPIC; do sleep 1; done; clear"

RUN="LIVE=1 ~/sqrtvins_ws/run_sqrtvins_euroc.sh $BAG $START $RATE; tmux send-keys -t $S:0.2 C-c; tmux send-keys -t $S:0.1 C-c; echo; echo 'Run finished. Leave with Ctrl+B then D.'; sleep 100000"
ECHO="$WAIT; ros2 topic echo $TOPIC geometry_msgs/msg/PoseWithCovarianceStamped --field pose.pose.position; sleep 100000"
HZ="$WAIT; ros2 topic hz $TOPIC; sleep 100000"
LOAD="top -d 2 -o %CPU"

tmux kill-session -t "$S" 2>/dev/null || true
# One window, four panes, each running one tool and carrying a title on its top border
tmux new-session -d -s "$S" -x 180 -y 48 "bash -c \"$RUN\""
tmux set-option -t "$S" pane-border-status top
tmux set-option -t "$S" pane-border-format " #{pane_title} "
tmux split-window -h -t "$S:0.0" "bash -c \"$ECHO\""
tmux split-window -v -t "$S:0.0" "bash -c \"$HZ\""
tmux split-window -v -t "$S:0.2" "$LOAD"
# panes now: 0 top-left, 1 bottom-left, 2 top-right, 3 bottom-right
tmux select-pane -t "$S:0.0" -T "1 estimator messages"
tmux select-pane -t "$S:0.2" -T "2 position x, y, z in metres (ros2 topic echo)"
tmux select-pane -t "$S:0.1" -T "3 poses per second, about 20 expected (ros2 topic hz)"
tmux select-pane -t "$S:0.3" -T "4 processor load (top), 100 % = one of 4 cores"
tmux select-pane -t "$S:0.0"
if [[ "$VIEW3D" == "1" ]]; then
  tmux new-window -d -t "$S" -n bridge "bash -c \"$ROS; ros2 launch foxglove_bridge foxglove_bridge_launch.xml port:=8765; sleep 100000\""
fi

# Show it right away when started from a terminal; otherwise just leave it running
if [[ -t 1 ]]; then tmux attach -t "$S"; else echo "Started. Watch with: ssh -t jetson tmux attach -t $S"; fi

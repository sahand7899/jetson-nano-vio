#!/bin/bash
# Live picture of the Jetson's camera on the laptop. Nothing is recorded, nothing is installed.
#
# It starts two programs on the Jetson, in the tmux session "camera":
#   window 0: the camera driver (gscam, the same program and settings the robot software
#             uses; read from ~/foxy_ws, which is not changed) -> 640x480 JPEG pictures, 30 per second
#   window 1: the bridge that the Lichtblick viewer on the laptop connects to (port 8765)
#
# usage (from the laptop):  ssh -t jetson ./sensors_ws/camera_view.sh [0|1]     0 / 1 = which of the two lenses
# stop:                     ssh jetson tmux kill-session -t camera
set -e
SENSOR=${1:-0}
source /opt/ros/humble/setup.bash
source ~/foxy_ws/install/setup.bash

# The robot software uses the same camera; both cannot have it at once.
if systemctl is-active --quiet foxy-bringup; then sudo systemctl stop foxy-bringup; fi
tmux kill-session -t camera 2>/dev/null || true

PIPE="nvarguscamerasrc sensor-id=$SENSOR sensor-mode=3 ! video/x-raw(memory:NVMM),width=(int)1640,height=(int)1232,format=(string)NV12,framerate=(fraction)30/1 ! nvvidconv ! video/x-raw,width=(int)640,height=(int)480,format=(string)I420,framerate=(fraction)30/1 ! nvjpegenc"

tmux new-session -d -s camera -x 160 -y 40 \
  "ros2 run gscam gscam_node --ros-args -p gscam_config:='$PIPE' -p image_encoding:=jpeg -p sync_sink:=false -p use_sensor_data_qos:=false -p frame_id:=camera; sleep 100000"
tmux new-window -t camera \
  "ros2 launch foxglove_bridge foxglove_bridge_launch.xml port:=8765; sleep 100000"
tmux select-window -t camera:0

echo "Camera is starting. On the laptop open:"
echo "  http://localhost:8080/?ds=foxglove-websocket&ds.url=ws://<jetson address>:8765"
echo "and choose the topic /camera/image_raw/compressed in an Image panel."
[ -t 1 ] && exec tmux attach -t camera

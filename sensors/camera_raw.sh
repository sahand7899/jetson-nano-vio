#!/bin/bash
# Raw grey camera images for calibration and VIO: ROS 2 topic /camera/image_raw (mono8, uncompressed).
# Uses the camera program (gscam 2.0.4) that the robot software (foxy image) already contains in
# ~/foxy_ws (read only, nothing installed). Runs in the tmux session "camera" (stop it before an
# algorithm test, so the test has the processor to itself).
#
# usage (on the Jetson):   ~/sensors_ws/camera_raw.sh            stop:  tmux kill-session -t camera
# settings (environment variables, defaults in brackets):
#   SENSOR      which of the two lenses (0 or 1)                     [0]  (keep the same one for everything)
#   EXPOSURE_MS fixed exposure time in milliseconds                  [10] (short = less blur; 10 ms = one
#               flicker period of 50 Hz mains lamps, so no stripes; 5 ms was too dark indoors, 20 Nov 2026)
#   GAIN_MAX    highest analog gain the camera may choose (1..10.625) [10.625] (only the gain adapts to the light)
#   WIDTH/HEIGHT output size; sensor mode 3 (1640x1232, full view)   [640x480]
#   FPS         images per second                                     [30]
#   STAMPS      gst = time stamp from inside the camera pipeline       [gst]
#               arrival = moment the image reaches gscam
#               Tested 20 Nov 2026 (60 s recordings): idle both are even (gap spread 0.35 / 0.25 ms);
#               with 3 of 4 cores busy, arrival stamps spread 1.1 ms (gaps 23..46 ms) but gst stamps
#               stay at 0.27 ms (31..35 ms). Neither is the exposure moment; that constant delay is
#               estimated by the camera-IMU calibration.
set -eo pipefail
SENSOR=${SENSOR:-0}; EXPOSURE_MS=${EXPOSURE_MS:-10}; GAIN_MAX=${GAIN_MAX:-10.625}
WIDTH=${WIDTH:-640}; HEIGHT=${HEIGHT:-480}; FPS=${FPS:-30}; STAMPS=${STAMPS:-gst}
EXP_NS=$(python3 -c "print(int(round(float('$EXPOSURE_MS')*1e6)))")
[ "$STAMPS" = gst ] && USE_GST=true || USE_GST=false

# The robot software uses the same camera; both cannot have it at once.
if systemctl is-active --quiet foxy-bringup; then sudo systemctl stop foxy-bringup; fi
tmux kill-session -t camera 2>/dev/null || true

# tnr-mode=0: no temporal noise reduction (it blends images over time); ee-mode=0: no artificial edge
# sharpening; ispdigitalgainrange 1: no digital gain; exposure fixed, only the analog gain adapts.
# Scaling is done in a first nvvidconv step (GPU memory, NV12): a direct NV12 -> GRAY8 step ignored the
# requested size and delivered 1640x1232 (tested 20 Nov 2026).
PIPE="nvarguscamerasrc sensor-id=$SENSOR sensor-mode=3 exposuretimerange=\"$EXP_NS $EXP_NS\" gainrange=\"1 $GAIN_MAX\" ispdigitalgainrange=\"1 1\" tnr-mode=0 ee-mode=0 ! video/x-raw(memory:NVMM),width=(int)1640,height=(int)1232,format=(string)NV12,framerate=(fraction)$FPS/1 ! nvvidconv ! video/x-raw(memory:NVMM),width=(int)$WIDTH,height=(int)$HEIGHT,format=(string)NV12 ! nvvidconv ! video/x-raw,format=(string)GRAY8"

PARAMS=/tmp/camera_raw_params.yaml
cat > $PARAMS <<YAML
/**:
  ros__parameters:
    gscam_config: '$PIPE'
    image_encoding: mono8
    use_gst_timestamps: $USE_GST
    sync_sink: false
    use_sensor_data_qos: false
    frame_id: camera
    camera_name: camera
YAML
{
  echo "camera_raw.sh  $(date -Is)"
  echo "SENSOR=$SENSOR EXPOSURE_MS=$EXPOSURE_MS GAIN_MAX=$GAIN_MAX WIDTH=$WIDTH HEIGHT=$HEIGHT FPS=$FPS STAMPS=$STAMPS"
  echo "pipeline: $PIPE"
} > /tmp/camera_raw_settings.txt

tmux new-session -d -s camera -x 160 -y 40 \
  "source /opt/ros/humble/setup.bash; source ~/foxy_ws/install/setup.bash; ros2 run gscam gscam_node --ros-args --params-file $PARAMS; sleep 100000"
echo "Camera started (tmux session 'camera'): /camera/image_raw, mono8 ${WIDTH}x${HEIGHT} @ ${FPS} Hz, exposure ${EXPOSURE_MS} ms, stamps: $STAMPS"
echo "Settings written to /tmp/camera_raw_settings.txt"

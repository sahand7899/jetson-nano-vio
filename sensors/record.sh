#!/bin/bash
# Record the Jetson's own camera + IMU into a ROS 2 bag, with a file describing exactly how it was made.
#
# usage (from the laptop):  ssh -t jetson ~/sensors_ws/record.sh <name> [seconds] [--imu-only] [--keep]
#   <name>      short label, e.g. allan_static, cam_imu_calib_1, test
#   seconds     stop after this many seconds (without it: press Ctrl-C to stop)
#   --imu-only  no camera (e.g. the 3-hour still recording for the IMU noise)
#   --keep      leave the sensors running afterwards (default: stop them)
# result:  ~/recordings/<date_time>_<name>/  with  bag/ (the rosbag)  and  recording_info.txt
# Camera settings come from camera_raw.sh (environment variables EXPOSURE_MS, GAIN_MAX, ... pass through).
# To run it in the background inside tmux, stop the robot software FIRST (sudo systemctl stop foxy-bringup):
# right after a boot, that service owns the tmux server, and stopping it from inside record.sh kills every
# tmux session, including the one record.sh runs in (seen 20 Nov 2026). Over 'ssh -t' this does not matter.
set -eo pipefail
NAME=${1:?usage: record.sh <name> [seconds] [--imu-only] [--keep]}; shift
DURATION=""; IMU_ONLY=0; KEEP=0
for a in "$@"; do
  case $a in
    --imu-only) IMU_ONLY=1 ;;
    --keep) KEEP=1 ;;
    ''|*[!0-9]*) echo "unknown option: $a"; exit 1 ;;
    *) DURATION=$a ;;
  esac
done
source /opt/ros/humble/setup.bash
source ~/sensors_ws/install/setup.bash
HERE=~/sensors_ws

if pgrep -fa '[_]ws/install/' | grep -v -e foxy_ws -e sensors_ws >/dev/null || pgrep -f '[r]os2 bag play' >/dev/null; then
  echo "An algorithm or a bag playback is running - stop it first."; exit 1
fi
if systemctl is-active --quiet foxy-bringup; then sudo systemctl stop foxy-bringup; fi
# The ROS 2 command-line helper (daemon) on this Jetson sometimes ends up broken (ros2 CLI errors
# "!rclpy.ok()", seen 20 Nov 2026). Start it fresh every time.
ros2 daemon stop >/dev/null 2>&1 || true
ros2 daemon start >/dev/null 2>&1 || true

# --- sensors ---
if ! tmux has-session -t imu 2>/dev/null; then
  tmux new-session -d -s imu "source /opt/ros/humble/setup.bash; source ~/sensors_ws/install/setup.bash; ros2 run icm20948_imu icm20948_node 2>&1 | tee /tmp/imu_driver.log; sleep 100000"
fi
if [ $IMU_ONLY = 0 ] && ! tmux has-session -t camera 2>/dev/null; then
  $HERE/camera_raw.sh >/dev/null
fi
TOPICS="/imu/data_raw /imu/temperature"
[ $IMU_ONLY = 0 ] && TOPICS="$TOPICS /camera/image_raw"

# wait until every topic delivers (the IMU driver publishes after a 2 s warm-up)
echo "waiting for: $TOPICS"
python3 $HERE/wait_topics.py 60 $TOPICS

# --- recording ---
OUT=~/recordings/$(date +%Y%m%d_%H%M%S)_$NAME
mkdir -p $OUT
INFO=$OUT/recording_info.txt
{
  echo "recording   $NAME"
  echo "started     $(date -Is)"
  echo "duration    ${DURATION:-until Ctrl-C} s;  topics: $TOPICS"
  echo "host        $(hostname), $(uname -r), $(head -1 /etc/nv_tegra_release 2>/dev/null | cut -c1-40)"
  echo "cpu         online $(cat /sys/devices/system/cpu/online), max $(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq) / 1000 )) MHz, governor $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
  echo "temperature $(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 )) C (CPU zone) at start"
  echo "free disk   $(df -h ~ | awk 'NR==2{print $4}')"
  echo "fan         pwm $(cat /sys/devices/pwm-fan/cur_pwm 2>/dev/null || echo unknown) of 255 at start (0 = off; a running fan shakes the IMU)"
  echo "--- IMU driver"
  echo "source sha256 $(sha256sum $HERE/src/icm20948_imu/src/icm20948_node.cpp | cut -c1-16)"
  grep -m1 "ICM-20948 on" /tmp/imu_driver.log 2>/dev/null | sed 's/^.*\]: //'
  if [ $IMU_ONLY = 0 ]; then
    echo "--- camera (camera_raw.sh sha256 $(sha256sum $HERE/camera_raw.sh | cut -c1-16))"
    cat /tmp/camera_raw_settings.txt
  fi
} > $INFO

echo "recording to $OUT  (${DURATION:+$DURATION s, }Ctrl-C stops)"
set +e
if [ -n "$DURATION" ]; then
  # stdin from /dev/null: under "timeout" inside tmux the recorder otherwise tries to read the keyboard
  # from a background process group and is frozen by the system (state T, nothing written; 20 Nov 2026)
  timeout -s INT "$DURATION" ros2 bag record -o $OUT/bag $TOPICS > $OUT/record.log 2>&1 < /dev/null
else
  trap '' INT   # Ctrl-C reaches ros2 bag record, which then closes the bag cleanly
  ros2 bag record -o $OUT/bag $TOPICS > $OUT/record.log 2>&1
  trap - INT
fi
set -e
sleep 1
if [ ! -f $OUT/bag/metadata.yaml ]; then echo "RECORDING FAILED: no bag written (see $OUT/record.log)"; exit 1; fi

{
  echo "--- end"
  echo "stopped     $(date -Is)"
  echo "temperature $(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 )) C (CPU zone) at end"
  echo "fan         pwm $(cat /sys/devices/pwm-fan/cur_pwm 2>/dev/null || echo unknown) of 255 at end"
  echo "IMU driver status lines during the recording:"
  grep "published" /tmp/imu_driver.log | tail -3 | sed 's/^.*\]: /  /'
  echo "--- ros2 bag info"
  ros2 bag info $OUT/bag 2>/dev/null | grep -E "Duration|Messages|Topic:|Bag size"
} >> $INFO

if [ $KEEP = 0 ]; then
  tmux kill-session -t camera 2>/dev/null || true
  tmux kill-session -t imu 2>/dev/null || true
fi
echo; tail -n +1 $INFO | tail -12
echo "saved: $OUT"

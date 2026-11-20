#!/usr/bin/env bash
# Runs VINS-Fusion (ROS 2 port, one camera + IMU, no loop closure, native build in
# ~/vins-fusion_ws) on one EuRoC ROS 2 bag on the Jetson Nano.
#
# VINS-Fusion is one program (vins_node). Inside it, one thread follows points from camera
# image to camera image (every image, 20 per second) and a second thread computes the
# position from every second image (the authors' "multiple_thread: 1"), so 10 answers per
# second. The loop-closure program (loop_fusion) is not built and not started.
#
# Output folder ~/results/vins-fusion/<sequence>/<date_time>/ :
#   poses/                   ROS 2 bag with the estimated pose per answer (/odometry), with
#                            the arrival time of each message
#   vio.csv                  the path as VINS-Fusion writes it itself (same poses as in poses/)
#   config/                  the settings folder this run used
#   vins.log                 the program's messages, including the authors' own
#                            "process time" of every answer (in ms)
#   load.csv                 every second: CPU % of the program (100 = one core), its memory,
#                            CPU % of the whole Jetson, free memory, CPU temperature
#   run_info.txt             exactly what was run: code version, settings, state of the Jetson
#
# usage: run_vins-fusion_euroc.sh <bag-folder> [start: "authors" or seconds] [playback rate]
#
# A test with settings that DIFFER from the authors' (a "variant") is started like this:
#   VARIANT=cnt100 OVERRIDES="max_cnt=100" run_vins-fusion_euroc.sh <bag-folder>
# Results then go to ~/results/vins-fusion-<variant>/ and run_info.txt lists every changed line.
set -eo pipefail

BAG="${1:?usage: $0 <bag-folder> [start: authors | seconds] [playback rate]}"
START="${2:-authors}"
RATE="${3:-1.0}"
PLAYER_DELAY=1
SEQ="$(basename "$BAG" _ros2)"
WS=~/vins-fusion_ws
SRC=$WS/src/VINS-Fusion-ROS2

# The authors play every EuRoC recording from its first second (README, section 3.1)
START_SOURCE="set by hand"
if [[ "$START" == "authors" ]]; then
  START_SOURCE="authors: the whole recording"
  START=0
fi

source /opt/ros/humble/setup.bash
source $WS/install/setup.bash
PROGRAM="$(ros2 pkg prefix vins)/lib/vins/vins_node"
CONFIG_SRC="$SRC/config/euroc"                          # the port's copy = HKUST's files
OFFICIAL_CONFIG=$WS/euroc_mono_imu_config_official.yaml # HKUST's file, from get_source.sh

VARIANT="${VARIANT:-}"
OVERRIDES="${OVERRIDES:-}"
[[ -n "$VARIANT" && -z "$OVERRIDES" ]] && { echo "VARIANT needs OVERRIDES" >&2; exit 1; }
[[ -z "$VARIANT" && -n "$OVERRIDES" ]] && { echo "OVERRIDES needs a VARIANT name" >&2; exit 1; }
NAME="vins-fusion${VARIANT:+-$VARIANT}"
OUT=~/results/$NAME/"$SEQ"/"$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"
echo "Output: $OUT"

# The settings file names the folder VINS-Fusion writes its result into, and the camera file
# is found next to it, so every run gets its own copy of the whole settings folder with the
# output folder set to the run folder. Nothing else changes (unless a variant).
cp -r "$CONFIG_SRC" "$OUT/config"
CONFIG="$OUT/config/euroc_mono_imu_config.yaml"
sed -i -E "s|^(output_path:) *\"[^\"]*\"|\1 \"$OUT/\"|; s|^(pose_graph_save_path:) *\"[^\"]*\"|\1 \"$OUT/pose_graph/\"|" "$CONFIG"
for kv in $OVERRIDES; do
  key="${kv%%=*}"; val="${kv#*=}"
  [[ "$(grep -c "^$key:" "$CONFIG")" == 1 ]] || { echo "setting $key not found exactly once" >&2; exit 1; }
  sed -i -E "s|^($key:) *[^ #]+|\1 $val|" "$CONFIG"
done

# run_info.txt: everything needed to say later exactly what was run
{
  echo "algorithm:       vins-fusion (ROS 2 port, vins_node, one camera + IMU, no loop_fusion)"
  echo "recording:       $SEQ"
  if [[ -n "$VARIANT" ]]; then
    echo "settings:        VARIANT \"$VARIANT\": differs from the authors' euroc_mono_imu_config.yaml in these lines (< authors, > this run):"
  else
    echo "settings:        the authors' euroc_mono_imu_config.yaml; only these lines differ (< authors, > this run):"
  fi
  { diff "$OFFICIAL_CONFIG" "$CONFIG" || true; } | grep '^[<>]' | sed "s/^/    /"
  echo "authors' file:   sha256 $(sha256sum "$OFFICIAL_CONFIG" | cut -d" " -f1) (HKUST-Aerial-Robotics/VINS-Fusion, commit be55a93, config/euroc/euroc_mono_imu_config.yaml)"
  echo "camera file:     $(cmp -s $WS/cam0_mei_official.yaml "$OUT/config/cam0_mei.yaml" && echo "cam0_mei.yaml identical to the authors'" || echo "cam0_mei.yaml DIFFERS from the authors'")"
  echo "date:            $(date -Iseconds)"
  echo "machine:         Jetson Nano, $(. /etc/os-release; echo "$PRETTY_NAME"), kernel $(uname -r)"
  echo "nvidia drivers:  $(head -1 /etc/nv_tegra_release 2>/dev/null || echo unknown)"
  echo "playback:        speed ${RATE}x, starting ${START} s into the recording ($START_SOURCE)"
  echo "player delay:    ${PLAYER_DELAY} s wait before the first message (so that none is lost)"
  if [[ "${LIVE:-0}" == "1" ]]; then
    echo "live viewer:     ON (live_demo.sh)  -> a run for watching, not for measurements"
  else
    echo "live viewer:     off"
  fi
  echo "recording file:  $(du -sb "$BAG" | cut -f1) bytes, $BAG"
  echo "robot software:  foxy-bringup is $(systemctl is-active foxy-bringup 2>/dev/null) (must be inactive during a test)"
  echo "memory:          $(awk '/MemAvailable/{printf "%.0f MiB available", $2/1024}' /proc/meminfo), swap: $(swapon --show=NAME --noheadings | tr '\n' ' ')"
  echo "cpu clock:       $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null) governor, max $(awk '{print $1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null) MHz, cores online: $(cat /sys/devices/system/cpu/online)"
  echo "temperature:     $(awk '{print $1/1000}' /sys/devices/virtual/thermal/thermal_zone1/temp 2>/dev/null) C at start"
  echo
  echo "--- source code ---"
  echo "repository:      $(git -C "$SRC" remote get-url origin)"
  echo "commit:          $(git -C "$SRC" rev-parse HEAD)"
  echo "files that differ from that commit (our fixes, see ~/vins-fusion_ws/patches):"
  git -C "$SRC" status --short | sed "s/^/    /"
  echo "sha256 of all differences (git diff): $(git -C "$SRC" diff | sha256sum | cut -d" " -f1)"
  echo "ceres solver:    2.1.0, $(cat $WS/ceres_version.txt 2>/dev/null), built in ~/vins-fusion_ws/ceres"
} > "$OUT/run_info.txt"

stop() {
  kill -INT "$@" 2>/dev/null || true
  for _ in $(seq 1 20); do
    local alive=0
    for p in "$@"; do kill -0 "$p" 2>/dev/null && alive=1; done
    [[ "$alive" == 0 ]] && return 0
    sleep 0.5
  done
  echo "forcing $* to stop" >&2
  kill -KILL "$@" 2>/dev/null || true
}

# Load monitor: reads the kernel's counters once per second
monitor() {
  local pid="$1" out="$2" hz tck_prev tot_prev idle_prev
  hz="$(getconf CLK_TCK)"
  echo "wall_time_s,est_cpu_percent,est_mem_MiB,system_cpu_percent,mem_available_MiB,cpu_temp_C" > "$out"
  read_proc() { awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null; }
  read_sys()  { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat; }
  tck_prev="$(read_proc)"; read -r tot_prev idle_prev <<< "$(read_sys)"
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    local tck tot idle rss avail temp
    tck="$(read_proc)" || break; [[ -z "$tck" ]] && break
    read -r tot idle <<< "$(read_sys)"
    rss="$(awk '/VmRSS/{print $2/1024}' "/proc/$pid/status" 2>/dev/null)"
    avail="$(awk '/MemAvailable/{print $2/1024}' /proc/meminfo)"
    temp="$(awk '{print $1/1000}' /sys/devices/virtual/thermal/thermal_zone1/temp 2>/dev/null)"
    awk -v t="$(date +%s.%N)" -v a="$tck" -v b="$tck_prev" -v hz="$hz" -v rss="$rss" \
        -v tot="$tot" -v totp="$tot_prev" -v idle="$idle" -v idlep="$idle_prev" \
        -v n="$(nproc)" -v avail="$avail" -v temp="$temp" \
        'BEGIN { dt=(tot-totp)/hz/n; if (dt<=0) dt=1;
                 printf "%s,%.1f,%.1f,%.1f,%.0f,%s\n", t, (a-b)/hz/dt*100, rss,
                        (1-(idle-idlep)/(tot-totp))*100*n, avail, temp }' >> "$out"
    tck_prev="$tck"; tot_prev="$tot"; idle_prev="$idle"
  done
}

# Started directly, as the authors do ("rosrun vins vins_node <config file>"); the program
# takes exactly one argument, the settings file. Its node is called vins_estimator, and its
# pose topic is /odometry (the ROS 1 original published it as /vins_estimator/odometry).
if [[ "${LIVE:-0}" == "1" ]]; then
  "$PROGRAM" "$CONFIG" > >(tee "$OUT/vins.log") 2>&1 &
else
  "$PROGRAM" "$CONFIG" > "$OUT/vins.log" 2>&1 &
fi
EST_PID=$!
monitor "$EST_PID" "$OUT/load.csv" &
ros2 bag record -o "$OUT/poses" /odometry > "$OUT/bag_record.log" 2>&1 &
REC_PID=$!
sleep 8   # let the nodes start and subscribe before the data arrives

echo "Playing $BAG at ${RATE}x from ${START} s ..."
# --delay: the player waits before the first message, so none is sent before the program
# is connected (applied to every algorithm; OpenVINS's authors do the same)
ros2 bag play "$BAG" --rate "$RATE" --start-offset "$START" --delay "$PLAYER_DELAY" > "$OUT/bag_play.log" 2>&1
sleep 3

stop "$EST_PID" "$REC_PID"
wait 2>/dev/null || true
echo "RUN_DONE $OUT"

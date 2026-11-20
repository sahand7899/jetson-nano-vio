#!/usr/bin/env bash
# Runs VINS-Mono (ROS 2 Humble port, monocular, no loop closure, native build in
# ~/vins-mono_ws) on one EuRoC ROS 2 bag on the Jetson Nano.
#
# VINS-Mono is two programs that work one after the other:
#   feature_tracker  follows points from camera image to camera image (every image, 20 per
#                    second) and passes the points on 10 times per second (authors' "freq: 10")
#   vins_estimator   computes the position from those points and the IMU (10 answers per second)
# The authors' third program, pose_graph (loop closure), is not built and not started.
#
# Output folder ~/results/vins-mono/<sequence>/<date_time>/ :
#   poses/                   ROS 2 bag with the estimated pose per processed image
#                            (/vins_estimator/odometry) and the tracker's output
#                            (/feature_tracker/feature), both with their arrival times
#   vins_result_no_loop.csv  the path as VINS-Mono writes it itself (same poses as in poses/)
#   config/euroc_config.yaml the settings file this run used
#   vins.log, feature_tracker.log   the programs' messages
#   load.csv                 every second: CPU % of both programs together (100 = one core)
#                            and each alone, their memory, CPU % of the whole Jetson, free
#                            memory, CPU temperature
#   run_info.txt             exactly what was run: code version, settings, state of the Jetson
#
# usage: run_vins-mono_euroc.sh <bag-folder> [start: "authors" or seconds] [playback rate]
#
# A test with settings that DIFFER from the authors' (a "variant") is started like this:
#   VARIANT=cnt100 OVERRIDES="max_cnt=100" run_vins-mono_euroc.sh <bag-folder>
# Results then go to ~/results/vins-mono-<variant>/ and run_info.txt lists every changed line.
#
# TIMING=1 run_vins-mono_euroc.sh <bag-folder>   switches on VINS-Mono's own "debug" messages,
# which contain the time each step took. Writing them costs processor time, so such a run is
# marked in run_info.txt and stored under ~/results/vins-mono-timing/: not a measured run.
set -eo pipefail

BAG="${1:?usage: $0 <bag-folder> [start: authors | seconds] [playback rate]}"
START="${2:-authors}"
RATE="${3:-1.0}"
PLAYER_DELAY=1
SEQ="$(basename "$BAG" _ros2)"
WS=~/vins-mono_ws
SRC=$WS/src/VINS-MONO-ROS2

# The authors play every EuRoC recording from its first second (README, section 3.1)
START_SOURCE="set by hand"
if [[ "$START" == "authors" ]]; then
  START_SOURCE="authors: the whole recording"
  START=0
fi

source /opt/ros/humble/setup.bash
source $WS/install/setup.bash
CONFIG_DIR="$(ros2 pkg prefix config_pkg)/share/config_pkg"
INSTALLED_CONFIG="$CONFIG_DIR/config/euroc/euroc_config.yaml"
OFFICIAL_CONFIG=$WS/euroc_config_official.yaml   # HKUST's file, downloaded by get_source.sh

VARIANT="${VARIANT:-}"
OVERRIDES="${OVERRIDES:-}"
TIMING="${TIMING:-0}"
[[ -n "$VARIANT" && -z "$OVERRIDES" ]] && { echo "VARIANT needs OVERRIDES" >&2; exit 1; }
[[ -z "$VARIANT" && -n "$OVERRIDES" ]] && { echo "OVERRIDES needs a VARIANT name" >&2; exit 1; }
NAME="vins-mono${VARIANT:+-$VARIANT}"
[[ "$TIMING" == "1" ]] && NAME="$NAME-timing"
OUT=~/results/$NAME/"$SEQ"/"$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT/config"
echo "Output: $OUT"

# The settings file names the folder VINS-Mono writes its result into, so every run gets its
# own copy with that folder set to the run folder. Nothing else changes (unless a variant).
CONFIG="$OUT/config/euroc_config.yaml"
cp "$INSTALLED_CONFIG" "$CONFIG"
sed -i -E "s|^(output_path:) *\"[^\"]*\"|\1 \"$OUT/\"|; s|^(pose_graph_save_path:) *\"[^\"]*\"|\1 \"$OUT/pose_graph/\"|" "$CONFIG"
for kv in $OVERRIDES; do
  key="${kv%%=*}"; val="${kv#*=}"
  [[ "$(grep -c "^$key:" "$CONFIG")" == 1 ]] || { echo "setting $key not found exactly once" >&2; exit 1; }
  sed -i -E "s|^($key:) *[^ #]+|\1 $val|" "$CONFIG"
done

# run_info.txt: everything needed to say later exactly what was run
{
  echo "algorithm:       vins-mono (ROS 2 port, feature_tracker + vins_estimator, no pose_graph)"
  echo "recording:       $SEQ"
  if [[ -n "$VARIANT" ]]; then
    echo "settings:        VARIANT \"$VARIANT\": differs from the authors' euroc_config.yaml in these lines (< authors, > this run):"
  else
    echo "settings:        the authors' euroc_config.yaml; only these lines differ (< authors, > this run):"
  fi
  { diff "$OFFICIAL_CONFIG" "$CONFIG" || true; } | grep '^[<>]' | sed "s/^/    /"
  echo "authors' file:   sha256 $(sha256sum "$OFFICIAL_CONFIG" | cut -d" " -f1) (HKUST-Aerial-Robotics/VINS-Mono, commit 90dabb5, config/euroc/euroc_config.yaml)"
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
  if [[ "$TIMING" == "1" ]]; then
    echo "debug messages:  ON (TIMING=1)  -> a run for reading the time per step, not a measured run"
  else
    echo "debug messages:  off"
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
  echo "files that differ from that commit (our fixes and the authors' settings file, see ~/vins-mono_ws/patches):"
  git -C "$SRC" status --short | sed "s/^/    /"
  echo "sha256 of all differences (git diff): $(git -C "$SRC" diff | sha256sum | cut -d" " -f1)"
  echo "ceres solver:    1.14.0, $(cat $WS/ceres_version.txt 2>/dev/null), built in ~/vins-mono_ws/ceres"
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

# Load monitor: reads the kernel's counters once per second, for both programs
monitor() {
  local ft="$1" est="$2" out="$3" hz
  hz="$(getconf CLK_TCK)"
  echo "wall_time_s,est_cpu_percent,est_mem_MiB,system_cpu_percent,mem_available_MiB,cpu_temp_C,tracker_cpu_percent,tracker_mem_MiB,estimator_cpu_percent,estimator_mem_MiB" > "$out"
  ticks() { awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null; }
  rss()   { awk '/VmRSS/{print $2/1024}' "/proc/$1/status" 2>/dev/null; }
  read_sys() { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6}' /proc/stat; }
  local ft_prev est_prev tot_prev idle_prev
  ft_prev="$(ticks "$ft")"; est_prev="$(ticks "$est")"; read -r tot_prev idle_prev <<< "$(read_sys)"
  while kill -0 "$est" 2>/dev/null && kill -0 "$ft" 2>/dev/null; do
    sleep 1
    local ft_now est_now tot idle
    ft_now="$(ticks "$ft")"; est_now="$(ticks "$est")"
    [[ -z "$ft_now" || -z "$est_now" ]] && break
    read -r tot idle <<< "$(read_sys)"
    awk -v t="$(date +%s.%N)" -v f="$ft_now" -v fp="$ft_prev" -v e="$est_now" -v ep="$est_prev" \
        -v hz="$hz" -v frss="$(rss "$ft")" -v erss="$(rss "$est")" \
        -v tot="$tot" -v totp="$tot_prev" -v idle="$idle" -v idlep="$idle_prev" -v n="$(nproc)" \
        -v avail="$(awk '/MemAvailable/{print $2/1024}' /proc/meminfo)" \
        -v temp="$(awk '{print $1/1000}' /sys/devices/virtual/thermal/thermal_zone1/temp 2>/dev/null)" \
        'BEGIN { dt=(tot-totp)/hz/n; if (dt<=0) dt=1;
                 fc=(f-fp)/hz/dt*100; ec=(e-ep)/hz/dt*100;
                 printf "%s,%.1f,%.1f,%.1f,%.0f,%s,%.1f,%.1f,%.1f,%.1f\n", t, fc+ec, frss+erss,
                        (1-(idle-idlep)/(tot-totp))*100*n, avail, temp, fc, frss, ec, erss }' >> "$out"
    ft_prev="$ft_now"; est_prev="$est_now"; tot_prev="$tot"; idle_prev="$idle"
  done
}

# Same node names and topics as the authors' ROS 1 launch file (euroc.launch):
# /feature_tracker/feature and /vins_estimator/odometry. vins_folder is where the tracker
# would look for a fisheye mask (not used for EuRoC). The programs are started directly
# rather than through "ros2 launch", which does not pass the stop signal on.
LOGLEVEL=()
[[ "$TIMING" == "1" ]] && LOGLEVEL=(--log-level debug)
FT=("$(ros2 pkg prefix feature_tracker)/lib/feature_tracker/feature_tracker" --ros-args -r __ns:=/feature_tracker
  -p config_file:="$CONFIG" -p vins_folder:="$CONFIG_DIR/config/../" "${LOGLEVEL[@]}")
EST=("$(ros2 pkg prefix vins_estimator)/lib/vins_estimator/vins_estimator" --ros-args -r __ns:=/vins_estimator
  -p config_file:="$CONFIG" -p vins_folder:="$CONFIG_DIR/config/../" "${LOGLEVEL[@]}")
"${FT[@]}" > "$OUT/feature_tracker.log" 2>&1 &
FT_PID=$!
if [[ "${LIVE:-0}" == "1" ]]; then
  # a run for watching (started by live_demo.sh): the messages also appear on the screen
  "${EST[@]}" > >(tee "$OUT/vins.log") 2>&1 &
else
  "${EST[@]}" > "$OUT/vins.log" 2>&1 &
fi
EST_PID=$!
monitor "$FT_PID" "$EST_PID" "$OUT/load.csv" &
ros2 bag record -o "$OUT/poses" /vins_estimator/odometry /feature_tracker/feature > "$OUT/bag_record.log" 2>&1 &
REC_PID=$!
sleep 8   # let the nodes start and subscribe before the data arrives

echo "Playing $BAG at ${RATE}x from ${START} s ..."
# --delay: the player waits before the first message, so none is sent before the programs
# are connected (applied to every algorithm; OpenVINS's authors do the same)
ros2 bag play "$BAG" --rate "$RATE" --start-offset "$START" --delay "$PLAYER_DELAY" > "$OUT/bag_play.log" 2>&1
sleep 3

stop "$EST_PID" "$FT_PID" "$REC_PID"
wait 2>/dev/null || true
echo "RUN_DONE $OUT"

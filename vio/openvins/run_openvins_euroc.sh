#!/usr/bin/env bash
# Runs OpenVINS (ROS 2 Humble, monocular, native build in ~/openvins_ws) on one EuRoC ROS 2 bag
# on the Jetson Nano. Same estimator command line as the one
# used in earlier desktop tests; only the paths and the load monitor differ.
#
# Output folder ~/results/openvins/<sequence>/<date_time>/ :
#   poses/           ROS 2 bag with the estimated IMU pose per camera frame (/ov_msckf/poseimu)
#   traj_timing.txt  processing time of every frame, split into the filter's steps
#   openvins.log     the estimator's messages
#   load.csv         every second: CPU % of the estimator alone (100 = one core), its memory,
#                    CPU % of the whole Jetson, free memory, CPU temperature
#
#   run_info.txt     exactly what was run: code version, start time, state of the Jetson
#
# usage: run_openvins_euroc.sh <bag-folder> [start: "authors" or seconds] [playback rate]
#
# A test with settings that DIFFER from the authors' (a "variant") is started like this:
#   VARIANT=slam25 OVERRIDES="max_slam=25" run_openvins_euroc.sh <bag-folder>
#   VARIANT=slam25-pts150 OVERRIDES="max_slam=25 num_pts=150" run_openvins_euroc.sh <bag-folder>
# The authors' settings folder is then copied into the run folder (config/), only the named
# lines are changed there, and run_info.txt lists every changed line. Results go to
# ~/results/openvins-<variant>/ so they can never be mixed up with the authors' settings.
#   run_openvins_euroc.sh ~/datasets/MH_03_medium_ros2        # the authors' way: starts 17.5 s in
#   run_openvins_euroc.sh ~/datasets/MH_03_medium_ros2 0      # start the playback somewhere else
set -eo pipefail

BAG="${1:?usage: $0 <bag-folder> [start: authors | seconds] [playback rate]}"
START="${2:-authors}"
RATE="${3:-1.0}"
PKG=ov_msckf
PLAYER_DELAY=1
SEQ="$(basename "$BAG" _ros2)"

# Start time the authors suggest per recording: comment in ov_msckf/launch/serial.launch,
# line 11: "v1-2: 0, mh1: 40, mh2: 35, mh3: 17.5, mh4-5: 15"
START_SOURCE="set by hand"
if [[ "$START" == "authors" ]]; then
  START_SOURCE="authors' suggestion"
  case "$SEQ" in
    MH_01_easy) START=40 ;;
    MH_02_easy) START=35 ;;
    MH_03_medium) START=17.5 ;;
    MH_04_difficult|MH_05_difficult) START=15 ;;
    *) START=0 ;;
  esac
fi

source /opt/ros/humble/setup.bash
source ~/openvins_ws/install/setup.bash
PREFIX="$(ros2 pkg prefix "$PKG")"
SHARE="$PREFIX/share/$PKG"

VARIANT="${VARIANT:-}"
OVERRIDES="${OVERRIDES:-}"
[[ -n "$VARIANT" && -z "$OVERRIDES" ]] && { echo "VARIANT needs OVERRIDES" >&2; exit 1; }
[[ -z "$VARIANT" && -n "$OVERRIDES" ]] && { echo "OVERRIDES needs a VARIANT name" >&2; exit 1; }
OUT=~/results/openvins${VARIANT:+-$VARIANT}/"$SEQ"/"$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"
echo "Output: $OUT"

CONFIG="$SHARE/config/euroc_mav/estimator_config.yaml"
if [[ -n "$VARIANT" ]]; then
  cp -r "$SHARE/config/euroc_mav" "$OUT/config"
  CONFIG="$OUT/config/estimator_config.yaml"
  for kv in $OVERRIDES; do
    key="${kv%%=*}"; val="${kv#*=}"
    [[ "$(grep -c "^$key:" "$CONFIG")" == 1 ]] || { echo "setting $key not found exactly once" >&2; exit 1; }
    sed -i -E "s|^($key:) *[^ #]+|\1 $val|" "$CONFIG"
  done
fi

# run_info.txt: everything needed to say later exactly what was run
{
  SRC=~/openvins_ws/src/open_vins
  echo "algorithm:       openvins"
  echo "recording:       $SEQ"
  if [[ -n "$VARIANT" ]]; then
    echo "settings:        VARIANT \"$VARIANT\": differs from the authors' estimator_config.yaml in these lines (< authors, > this run):"
    { diff "$SHARE/config/euroc_mav/estimator_config.yaml" "$CONFIG" || true; } | grep '^[<>]' | sed "s/^/    /"
  else
    echo "settings:        the authors' estimator_config.yaml, unchanged"
  fi
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
  echo "files that differ from that commit (our fixes, see ~/openvins_ws/patches):"
  git -C "$SRC" status --short | sed "s/^/    /"
  echo "sha256 of all differences (git diff): $(git -C "$SRC" diff | sha256sum | cut -d" " -f1)"
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

ESTIMATOR=("$PREFIX/lib/$PKG/run_subscribe_msckf" --ros-args -r __ns:="/$PKG"
  -p verbosity:=INFO -p use_stereo:=false -p max_cameras:=1 -p save_total_state:=false
  -p config_path:="$CONFIG"
  -p record_timing_information:=true -p record_timing_filepath:="$OUT/traj_timing.txt")
if [[ "${LIVE:-0}" == "1" ]]; then
  # a run for watching (started by live_demo.sh): the messages also appear on the screen
  "${ESTIMATOR[@]}" > >(tee "$OUT/openvins.log") 2>&1 &
else
  "${ESTIMATOR[@]}" > "$OUT/openvins.log" 2>&1 &
fi
EST_PID=$!
monitor "$EST_PID" "$OUT/load.csv" &
ros2 bag record -o "$OUT/poses" "/$PKG/poseimu" > "$OUT/bag_record.log" 2>&1 &
REC_PID=$!
sleep 8   # let the nodes start and subscribe before the data arrives

echo "Playing $BAG at ${RATE}x from ${START} s ..."
# --delay: the player waits before the first message, so none is sent before the estimator
# is connected (the authors' launch file does the same: "rosbag play -d 1")
ros2 bag play "$BAG" --rate "$RATE" --start-offset "$START" --delay "$PLAYER_DELAY" > "$OUT/bag_play.log" 2>&1
sleep 3

stop "$EST_PID" "$REC_PID"
wait 2>/dev/null || true
echo "RUN_DONE $OUT"

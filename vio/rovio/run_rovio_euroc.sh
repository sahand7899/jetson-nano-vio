#!/usr/bin/env bash
# Runs ROVIO (ROS 2 port, one camera + IMU, native build in ~/rovio_ws) on one EuRoC ROS 2
# bag on the Jetson Nano. ROVIO has no loop closure at all.
#
# ROVIO is one program (rovio_node). It is a filter: every IMU message moves the estimate
# forward, and every camera image (20 per second) corrects it, so it gives 20 answers per
# second.
#
# Output folder ~/results/rovio/<sequence>/<date_time>/ :
#   poses/       ROS 2 bag with the estimated pose per camera image (/rovio/odometry), with
#                the arrival time of each message
#   config/      the two settings files this run used (rovio.info, euroc_cam0.yaml)
#   rovio.log    the program's messages
#   load.csv     every second: CPU % of the program (100 = one core), its memory, CPU % of
#                the whole Jetson, free memory, CPU temperature
#   run_info.txt exactly what was run: code version, settings, state of the Jetson
#
# usage: run_rovio_euroc.sh <bag-folder> [start: "authors" or seconds] [playback rate]
#
# A test with settings that DIFFER from the authors' (a "variant") is started like this:
#   VARIANT=name OVERRIDES="settingName=value" run_rovio_euroc.sh <bag-folder>
# (a line "settingName value" in rovio.info that exists exactly once). Results then go to
# ~/results/rovio-<variant>/ and run_info.txt lists every changed line.
set -eo pipefail

BAG="${1:?usage: $0 <bag-folder> [start: authors | seconds] [playback rate]}"
START="${2:-authors}"
RATE="${3:-1.0}"
PLAYER_DELAY=1
SEQ="$(basename "$BAG" _ros2)"
WS=~/rovio_ws
SRC=$WS/src/rovio_ros2

# The authors' README: rovio_node.launch "loads parameters such that ROVIO runs properly on
# the Euroc datasets"; no start time is given, so the whole recording is played
START_SOURCE="set by hand"
if [[ "$START" == "authors" ]]; then
  START_SOURCE="authors: the whole recording"
  START=0
fi

source /opt/ros/humble/setup.bash
source $WS/install/setup.bash
PROGRAM="$(ros2 pkg prefix rovio)/lib/rovio/rovio_node"
CFG_SRC="$(ros2 pkg prefix rovio)/share/rovio/cfg"

VARIANT="${VARIANT:-}"
OVERRIDES="${OVERRIDES:-}"
[[ -n "$VARIANT" && -z "$OVERRIDES" ]] && { echo "VARIANT needs OVERRIDES" >&2; exit 1; }
[[ -z "$VARIANT" && -n "$OVERRIDES" ]] && { echo "OVERRIDES needs a VARIANT name" >&2; exit 1; }
NAME="rovio${VARIANT:+-$VARIANT}"
OUT=~/results/$NAME/"$SEQ"/"$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT/config"
echo "Output: $OUT"

cp "$CFG_SRC/rovio.info" "$CFG_SRC/euroc_cam0.yaml" "$OUT/config/"
CONFIG="$OUT/config/rovio.info"
CAMERA="$OUT/config/euroc_cam0.yaml"
# The authors' rovio.info opens a picture window for every image (doFrameVisualisation true,
# line 78). A measured run has no viewer (project rule), and the Jetson has no screen, so the
# window is switched off in every run; this line therefore always appears in run_info.txt.
[[ "$(grep -c -E '^\s*doFrameVisualisation\s+true;' "$CONFIG")" == 1 ]] || { echo "doFrameVisualisation line not found" >&2; exit 1; }
sed -i -E 's|^(\s*doFrameVisualisation\s+)true;|\1false;|' "$CONFIG"
for kv in $OVERRIDES; do
  key="${kv%%=*}"; val="${kv#*=}"
  [[ "$(grep -c -E "^\s*$key\s" "$CONFIG")" == 1 ]] || { echo "setting $key not found exactly once" >&2; exit 1; }
  sed -i -E "s|^(\s*$key\s+)[^ ;]+|\1$val|" "$CONFIG"
done

# run_info.txt: everything needed to say later exactly what was run
{
  echo "algorithm:       rovio (ROS 2 port, rovio_node, one camera + IMU)"
  echo "recording:       $SEQ"
  if [[ -n "$VARIANT" ]]; then
    echo "settings:        VARIANT \"$VARIANT\": differs from the authors' rovio.info in these lines (< authors, > this run):"
  else
    echo "settings:        the authors' rovio.info and euroc_cam0.yaml; lines that differ (< authors, > this run):"
  fi
  { diff $WS/rovio_official.info "$CONFIG" || true; } | { grep '^[<>]' || true; } | sed "s/^/    /"
  { diff $WS/euroc_cam0_official.yaml "$CAMERA" || true; } | { grep '^[<>]' || true; } | sed "s/^/    /"
  echo "authors' files:  sha256 rovio.info $(sha256sum $WS/rovio_official.info | cut -c1-16)..., euroc_cam0.yaml $(sha256sum $WS/euroc_cam0_official.yaml | cut -c1-16)... (ethz-asl/rovio, commit 34735c0, cfg/)"
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
  echo "filter library:  lightweight_filtering $(git -C "$SRC/rovio/lightweight_filtering" rev-parse HEAD) (official ROVIO uses 0c8517a5eb19a00a4f8d36dac4ffdc45dac6a363)"
  echo "files that differ from that commit (our fixes, see ~/rovio_ws/patches):"
  git -C "$SRC" status --short | sed "s/^/    /"
  echo "sha256 of all differences (git diff): $(git -C "$SRC" diff | sha256sum | cut -d" " -f1)"
  echo "kindr:           $(cat $WS/kindr_version.txt 2>/dev/null), in ~/rovio_ws/kindr"
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

# Started directly with the same parameters as the port's launch file rovio_node.launch.py
# (node name rovio, the two settings files). It listens to /imu0 and /cam0/image_raw, the
# EuRoC topic names, and publishes its pose on /rovio/odometry, as the ROS 1 original does.
ARGS=(--ros-args -r __node:=rovio -p filter_config:="$CONFIG" -p camera0_config:="$CAMERA")
if [[ "${LIVE:-0}" == "1" ]]; then
  "$PROGRAM" "${ARGS[@]}" > >(tee "$OUT/rovio.log") 2>&1 &
else
  "$PROGRAM" "${ARGS[@]}" > "$OUT/rovio.log" 2>&1 &
fi
EST_PID=$!
monitor "$EST_PID" "$OUT/load.csv" &
ros2 bag record -o "$OUT/poses" /rovio/odometry > "$OUT/bag_record.log" 2>&1 &
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

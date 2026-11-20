#!/usr/bin/env bash
# Installs the trajectory evaluation tool "evo" (https://github.com/MichaelGrupp/evo)
# into a Python virtual environment in the home folder (Ubuntu 22.04, native or WSL). Run as the normal user:
#   bash evaluation/install_evo.sh
set -euo pipefail

VENV="$HOME/venvs/evo"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip
"$VENV/bin/pip" install "evo==1.38.0"
"$VENV/bin/pip" install "rosbags==0.11.9"   # reads ROS 2 bags (pose topics, IMU recordings)

# Draw plots into files (PDF/PNG) instead of windows. evo's default (TkAgg) needs tkinter
# and a display; it ignores MPLBACKEND, so it is set in evo's own settings.
"$VENV/bin/evo_config" set plot_backend Agg

# Make the evo_* commands available in every new shell
grep -q 'venvs/evo/bin' "$HOME/.bashrc" || echo 'export PATH="$HOME/venvs/evo/bin:$PATH"' >> "$HOME/.bashrc"

"$VENV/bin/evo" pkg --version

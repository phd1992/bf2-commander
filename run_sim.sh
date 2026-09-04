#!/usr/bin/env sh
# Headless AI vs AI batch. Example:  ./run_sim.sh --matches 10 --seed 1
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --script res://sim/run_headless.gd -- "$@"

#!/usr/bin/env sh
# Runs the plain test runner. Imports the project first so class_name lookups
# resolve in headless mode. Extra arguments are passed through, e.g.
#   ./run_tests.sh --filter=los
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --script res://tests/run_tests.gd -- "$@"

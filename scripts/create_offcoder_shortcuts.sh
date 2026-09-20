#!/bin/sh
# Installs the standalone Offcoder deck on the Desktop.
# One icon, one app: the bundle boots its backing services itself.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "[offcoder] Building standalone Offcoder.app..."
"$ROOT/scripts/build_offcoder_app.sh"

echo "[offcoder] Desktop shortcut ready: $HOME/Desktop/Offcoder.app"

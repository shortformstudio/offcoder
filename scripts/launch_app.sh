#!/bin/sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$HOME/.offcoder/logs"
mkdir -p "$LOG_DIR"

# 1. Start Dispatcher if not already running on 8000
if ! lsof -i :8000 >/dev/null 2>&1; then
    echo "[offcoder] Starting Local Dispatcher on port 8000..."
    (
        cd "$ROOT/dispatcher"
        exec python3 -m uvicorn src.main:app --port 8000 > "$LOG_DIR/dispatcher.log" 2>&1
    ) &
    sleep 0.5
else
    echo "[offcoder] Dispatcher already running on port 8000."
fi

# 2. Start Daemon if not already running on 7171
if ! lsof -i :7171 >/dev/null 2>&1; then
    echo "[offcoder] Starting Orchestrator Daemon on port 7171..."
    (
        cd "$ROOT/daemon"
        if [ -f "dist/index.mjs" ]; then
            exec node dist/index.mjs > "$LOG_DIR/daemon.log" 2>&1
        else
            exec npm run dev > "$LOG_DIR/daemon.log" 2>&1
        fi
    ) &
    sleep 0.5
else
    echo "[offcoder] Daemon already running on port 7171."
fi

# 3. Choose the Offcoder Cockpit executable
COCKPIT_BIN="$ROOT/cockpit/.build/release/OrchestratorCockpit"
if [ ! -f "$COCKPIT_BIN" ]; then
    COCKPIT_BIN="$ROOT/cockpit/.build/debug/OrchestratorCockpit"
fi

if [ ! -f "$COCKPIT_BIN" ]; then
    echo "[offcoder] Building Offcoder Cockpit binary..."
    (cd "$ROOT/cockpit" && swift build)
    COCKPIT_BIN="$ROOT/cockpit/.build/debug/OrchestratorCockpit"
fi

echo "[offcoder] Launching Offcoder Supreme Coding Cockpit..."
exec "$COCKPIT_BIN"

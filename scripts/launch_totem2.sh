#!/bin/sh
# Totem 2 — Indigo agent on port 9090.
# Serves an OpenAI-compatible endpoint whose governing system prompt is the
# Indigo directive, pre-appended with the user's preloaded memory/mission context.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$HOME/.offcoder/logs"
mkdir -p "$LOG_DIR"

LISTEN_PORT="${TOTEM2_PORT:-9090}"
UPSTREAM="${TOTEM2_UPSTREAM:-http://lockfort.local:8080}"
PROMPT_FILE="$ROOT/prompts/indigo.system.xml"
CONTEXT_FILE="$HOME/.offcoder/preload/context.md"

if lsof -i :"$LISTEN_PORT" >/dev/null 2>&1; then
    echo "[totem2] Port $LISTEN_PORT already active."
    exit 0
fi

if [ ! -f "$CONTEXT_FILE" ]; then
    python3 "$ROOT/scripts/build_preload_context.py" --totem-port "$LISTEN_PORT" >/dev/null 2>&1 || true
fi

echo "[totem2] Starting Indigo agent: listen $LISTEN_PORT -> $UPSTREAM"
exec python3 "$ROOT/scripts/totem_port_listener.py" \
    --listen-port "$LISTEN_PORT" \
    --target-port 8080 \
    --totem-port "$LISTEN_PORT" \
    --target-host "$UPSTREAM" \
    --filter atlas \
    --system-prompt-file "$PROMPT_FILE" \
    --context-file "$CONTEXT_FILE" >> "$LOG_DIR/totem-$LISTEN_PORT.log" 2>&1

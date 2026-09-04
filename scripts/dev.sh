#!/bin/sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
(
  cd "$ROOT/dispatcher"
  .venv/bin/uvicorn src.main:app --port 8000
) &
DISPATCHER_PID=$!
(
  cd "$ROOT/daemon"
  npm run dev
) &
DAEMON_PID=$!
trap 'kill 0' INT TERM EXIT
wait

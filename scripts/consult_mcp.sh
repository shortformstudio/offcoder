#!/bin/sh
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec node "$ROOT/mcp-server/consult/index.js" "$@"

#!/bin/sh
set -e

PLIST_NAME="com.shortformstudio.orchestrator.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/.local_orchestrator/logs"

mkdir -p "$TARGET_DIR"
mkdir -p "$LOG_DIR"

cp "$SCRIPT_DIR/$PLIST_NAME" "$TARGET_DIR/$PLIST_NAME"
launchctl unload "$TARGET_DIR/$PLIST_NAME" 2>/dev/null || true
launchctl load "$TARGET_DIR/$PLIST_NAME"

echo "Successfully installed and loaded $PLIST_NAME into launchd."
echo "Logs located at: $LOG_DIR"

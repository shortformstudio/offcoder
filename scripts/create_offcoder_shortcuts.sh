#!/bin/sh
set -e

APP_NAME="Offcoder"
DESKTOP="$HOME/Desktop"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$ROOT/scripts/launch_app.sh"

echo "[offcoder] Creating Desktop shortcuts for Offcoder..."

# 1. Executable .command shortcut
COMMAND_FILE="$DESKTOP/$APP_NAME.command"
cat << SCRIPT > "$COMMAND_FILE"
#!/bin/sh
exec "$LAUNCHER"
SCRIPT
chmod +x "$COMMAND_FILE"
echo "  -> Created $COMMAND_FILE"

# 2. Native macOS .app bundle via AppleScript osacompile
APP_DIR="$DESKTOP/$APP_NAME.app"
rm -rf "$APP_DIR"

osacompile -o "$APP_DIR" << APPLESCRIPT
do shell script quoted form of "$LAUNCHER" & " > /dev/null 2>&1 &"
APPLESCRIPT

echo "  -> Created $APP_DIR"
echo "[offcoder] Desktop shortcuts ready!"

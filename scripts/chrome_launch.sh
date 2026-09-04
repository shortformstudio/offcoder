#!/bin/sh
PROFILE="${HOME}/.chrome_automation_profile"
mkdir -p "$PROFILE"
open -na "Google Chrome" --args \
  --remote-debugging-port=9222 \
  --user-data-dir="$PROFILE" \
  --no-first-run \
  --no-default-browser-check
echo "chrome cdp on 9222, profile $PROFILE"

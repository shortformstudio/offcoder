#!/bin/sh
# Offcoder browser mirror chrome instance.
# Dedicated profile + dedicated CDP port (9224). Launches OFFSCREEN so it
# never appears over the operator's windows; the mirror reflects it and the
# login button raises it on demand.
PROFILE="${HOME}/.offcoder/chrome-profile"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p "$PROFILE"

# Only start if not already on 9224
if curl -s --max-time 2 http://127.0.0.1:9224/json/version >/dev/null 2>&1; then
  echo "offcoder chrome already on 9224"
  exit 0
fi

nohup "$CHROME" \
  --remote-debugging-port=9224 \
  --user-data-dir="$PROFILE" \
  --no-first-run \
  --no-default-browser-check \
  --disable-infobars \
  --hide-crash-restore-bubble \
  --window-size=1440,900 \
  --window-position=-32000,-32000 \
  --new-window \
  about:blank >/dev/null 2>&1 &

sleep 3
if curl -s --max-time 2 http://127.0.0.1:9224/json/version >/dev/null 2>&1; then
  echo "offcoder chrome on 9224 (hidden/offscreen)"
else
  echo "WARNING: chrome did not come up on 9224"
fi

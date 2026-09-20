#!/bin/sh
# Builds the standalone Offcoder.app — one icon, one deck.
# The cockpit binary is the app executable; it boots dispatcher, daemon, and the
# Indigo totem (9090) itself, so no Terminal and no second app appear.
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Offcoder.app"
BINARY="$ROOT/cockpit/.build/release/OrchestratorCockpit"
ICNS="$DIST/Offcoder.icns"

echo "[offcoder] Building release cockpit..."
(cd "$ROOT/cockpit" && swift build -c release)

if [ ! -f "$ICNS" ]; then
    python3 "$ROOT/scripts/make_offcoder_icon.py" "$DIST"
fi

echo "[offcoder] Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/Offcoder"
chmod +x "$APP/Contents/MacOS/Offcoder"
cp "$ICNS" "$APP/Contents/Resources/Offcoder.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Offcoder</string>
	<key>CFBundleExecutable</key>
	<string>Offcoder</string>
	<key>CFBundleIconFile</key>
	<string>Offcoder</string>
	<key>CFBundleIconName</key>
	<string>Offcoder</string>
	<key>CFBundleIdentifier</key>
	<string>com.shortformstudio.offcoder</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Offcoder</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0</string>
	<key>CFBundleVersion</key>
	<string>2</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.developer-tools</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Offcoder connects to your local inference host and automation daemon.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
</dict>
</plist>
PLIST

echo "[offcoder] Ad-hoc signing..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# Install to the Desktop, preserving the legacy applet and Terminal shortcut.
DESKTOP="$HOME/Desktop"
LEGACY="$DIST/legacy"
mkdir -p "$LEGACY"

if [ -d "$DESKTOP/Offcoder.app" ] && [ ! -f "$DESKTOP/Offcoder.app/Contents/MacOS/Offcoder" ]; then
    rm -rf "$LEGACY/Offcoder.applet"
    mv "$DESKTOP/Offcoder.app" "$LEGACY/Offcoder.applet"
fi
if [ -f "$DESKTOP/Offcoder.command" ]; then
    mv "$DESKTOP/Offcoder.command" "$LEGACY/Offcoder.command"
fi

rm -rf "$DESKTOP/Offcoder.app"
ditto "$APP" "$DESKTOP/Offcoder.app"
touch "$DESKTOP/Offcoder.app"

echo "[offcoder] Installed $DESKTOP/Offcoder.app"
echo "[offcoder] Legacy launchers preserved in $LEGACY"

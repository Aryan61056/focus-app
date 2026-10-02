#!/bin/bash
# Builds mac/.build/Focus.app from the SwiftPM release build: a local, ad-hoc-signed development bundle.
# Not for distribution (signing, notarization and the bundle id are owner decisions still open).
set -euo pipefail
cd "$(dirname "$0")/../mac"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"; unset SDKROOT
swift build -c release --product focus-app 2>&1 | tail -1
APP=".build/Focus.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/focus-app" "$APP/Contents/MacOS/focus-app"
T="$(mktemp -d)"
swiftc -o "$T/make_icon" ../tools/make_icon.swift 2>/dev/null && "$T/make_icon" "$T/AppIcon.iconset" && iconutil -c icns "$T/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns" || echo "icon skipped"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Focus</string>
  <key>CFBundleDisplayName</key><string>Focus</string>
  <key>CFBundleIdentifier</key><string>com.example.focus-app.dev</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>focus-app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Focus shows you a small picture of the window it is reading. The picture stays in memory and is never saved.</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
# A requirement that names the bundle id, not the build's hash: with the default ad-hoc requirement (a cdhash) every rebuild is a
# "new app" to macOS and silently loses the Accessibility and Screen Recording grants, even though Settings still shows them on.
codesign --force --sign - -r='designated => identifier "com.example.focus-app.dev"' "$APP" 2>&1 | tail -1
codesign --verify --verbose=1 "$APP" 2>&1 | tail -1
echo "built $(pwd)/$APP"

#!/bin/bash
# Builds mac/.build/Focus.app from the SwiftPM release build: a local, ad-hoc-signed development bundle.
# Pass --install to also copy it to ~/Applications, where Spotlight finds it (no sudo).
# Not for distribution (signing, notarization and the bundle id are owner decisions still open).
#
# Friends over iCloud (docs/SOCIAL.md) need a signed build. With no variables set you get the ad-hoc build, where Friends says
# "not set up for it yet". To try iCloud, set all of:
#   FOCUS_SIGN_IDENTITY       e.g. "Apple Development: Name (TEAMID)"  (security find-identity -v -p codesigning)
#   FOCUS_TEAM_ID             the 10-character team id
#   FOCUS_PROVISIONING_PROFILE path to a macOS profile for FOCUS_BUNDLE_ID with iCloud (CloudKit) and Push enabled
# and optionally FOCUS_BUNDLE_ID (default com.example.focus-app.dev) and FOCUS_CLOUD_CONTAINER (default iCloud.<bundle id>).
set -euo pipefail
BUNDLE_ID="${FOCUS_BUNDLE_ID:-com.example.focus-app.dev}"
CLOUD_CONTAINER="${FOCUS_CLOUD_CONTAINER:-iCloud.$BUNDLE_ID}"
SIGNED=0
if [ -n "${FOCUS_SIGN_IDENTITY:-}" ]; then
  : "${FOCUS_TEAM_ID:?set FOCUS_TEAM_ID with FOCUS_SIGN_IDENTITY}" "${FOCUS_PROVISIONING_PROFILE:?set FOCUS_PROVISIONING_PROFILE with FOCUS_SIGN_IDENTITY}"
  [ -f "$FOCUS_PROVISIONING_PROFILE" ] || { echo "no provisioning profile at $FOCUS_PROVISIONING_PROFILE" >&2; exit 1; }
  SIGNED=1
fi
cd "$(dirname "$0")/../mac"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"; unset SDKROOT
swift build -c release --product focus-app 2>&1 | tail -1
APP=".build/Focus.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/focus-app" "$APP/Contents/MacOS/focus-app"
# SwiftPM records SDK 14 (the deployment target) in the binary, and macOS then draws the app in its old-design compatibility mode:
# no Liquid Glass toolbar, sidebar or controls. Stamp the SDK it was really built with.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
vtool -set-build-version macos 14.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/focus-app" "$APP/Contents/MacOS/focus-app"
T="$(mktemp -d)"
# The icon: Resources/AppIcon.icon (an Icon Composer document: the ring on deep green, Liquid Glass with the system's dark and tinted
# looks) compiled to Assets.car for macOS 26 and later, plus AppIcon.icns, pre-rendered for older systems. If this Xcode cannot
# compile it, fall back to the flat icon drawn by tools/make_icon.swift.
ICON_NAME=""
# actool runs as a separate server process, so every path must be absolute.
if xcrun actool "$(pwd)/Resources/AppIcon.icon" --compile "$T" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
     --output-partial-info-plist "$T/icon.plist" >/dev/null 2>&1 && [ -f "$T/Assets.car" ]; then
  cp "$T/Assets.car" "$T/AppIcon.icns" "$APP/Contents/Resources/"; ICON_NAME="AppIcon"
else
  swiftc -o "$T/make_icon" ../tools/make_icon.swift 2>/dev/null && "$T/make_icon" "$T/AppIcon.iconset" && iconutil -c icns "$T/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns" || echo "icon skipped"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Focus</string>
  <key>CFBundleDisplayName</key><string>Focus</string>
  <key>CFBundleIdentifier</key><string>__BUNDLE_ID__</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>focus-app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CKSharingSupported</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Focus can switch your browser to the tab you were working in, or close the tab you were warned about, when you turn that on. It sends nothing anywhere.</string>
  <key>NSLocalNetworkUsageDescription</key><string>Focus talks to your iPhone on your Wi-Fi so the phone can show and control your session. It only listens after you turn on Session, iPhone.</string>
  <key>NSBonjourServices</key><array><string>_focuslink._tcp</string></array>
  <key>NSScreenCaptureUsageDescription</key><string>Focus shows you a small picture of the window it is reading. The picture stays in memory and is never saved.</string>
</dict></plist>
PLIST
sed -i '' "s|__BUNDLE_ID__|$BUNDLE_ID|" "$APP/Contents/Info.plist"
# The signed build names its container, so the code looks for the right one (see CloudKitFriends.containerID).
if [ "$SIGNED" = 1 ]; then /usr/libexec/PlistBuddy -c "Add :FocusCloudContainer string $CLOUD_CONTAINER" "$APP/Contents/Info.plist"; fi
# Which build this is, and where it came from: an installed copy watches that folder for a newer build (see Updater.swift). Local only.
BUILD_ID="$(date -u +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
/usr/libexec/PlistBuddy -c "Add :FocusBuildID string $BUILD_ID" -c "Add :FocusBuildSource string $(pwd)/$APP" "$APP/Contents/Info.plist"
# Assets.car holds the layered icon; the system finds it by name.
if [ -n "$ICON_NAME" ]; then /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $ICON_NAME" "$APP/Contents/Info.plist"; fi
plutil -lint "$APP/Contents/Info.plist" >/dev/null
if [ "$SIGNED" = 1 ]; then
  # Signed for iCloud: the profile travels inside the bundle and the entitlements must be allowed by it.
  cp "$FOCUS_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  sed -e "s|__TEAM__|$FOCUS_TEAM_ID|g" -e "s|__BUNDLE__|$BUNDLE_ID|g" -e "s|__CONTAINER__|$CLOUD_CONTAINER|g" Resources/Focus.entitlements > "$T/Focus.entitlements"
  codesign --force --sign "$FOCUS_SIGN_IDENTITY" --entitlements "$T/Focus.entitlements" --options runtime "$APP" 2>&1 | tail -1
else
# A requirement that names the bundle id, not the build's hash: with the default ad-hoc requirement (a cdhash) every rebuild is a
# "new app" to macOS and silently loses the Accessibility and Screen Recording grants, even though Settings still shows them on.
codesign --force --sign - -r="designated => identifier \"$BUNDLE_ID\"" "$APP" 2>&1 | tail -1
fi
codesign --verify --verbose=1 "$APP" 2>&1 | tail -1
echo "built $(pwd)/$APP"
if [ "${1:-}" = "--install" ]; then
  DEST="$HOME/Applications/Focus.app"
  mkdir -p "$HOME/Applications"
  # Quit a running copy first so the replaced bundle is the one that opens next.
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  rm -rf "$DEST"; ditto "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
  mdimport "$DEST" >/dev/null 2>&1 || true
  echo "installed $DEST"
fi

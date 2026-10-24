#!/bin/bash
# Builds the Hushd iPhone app for a real phone into companion/.build/"Hushd for iPhone.app". tools/build_app.sh then carries it inside
# Hushd.app, and Session > iPhone... installs it on a plugged-in iPhone (docs/COMPANION.md, "Install from the Mac").
#
# Needs: xcodegen (brew install xcodegen), Xcode signed in to an Apple ID, and your team id (the 10 characters under Xcode > Settings >
# Accounts > your team; a free Personal Team is enough, the Block tab just says Screen Time is unavailable in that build):
#   FOCUS_TEAM_ID=ABCDE12345 ./tools/build_iphone.sh
# Not run in CI and not run by the agent that wrote it: there was no signing team, no phone and no xcodegen on that Mac.
set -euo pipefail
: "${FOCUS_TEAM_ID:?set FOCUS_TEAM_ID to your 10-character Apple team id}"
command -v xcodegen >/dev/null || { echo "xcodegen is missing: brew install xcodegen" >&2; exit 1; }
cd "$(dirname "$0")/../companion"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"; unset SDKROOT
xcodegen generate >/dev/null
OUT="$(pwd)/.build"
rm -rf "$OUT/DerivedData" "$OUT/Hushd for iPhone.app"; mkdir -p "$OUT"
xcodebuild -project FocusCompanion.xcodeproj -scheme FocusCompanion -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$OUT/DerivedData" -allowProvisioningUpdates DEVELOPMENT_TEAM="$FOCUS_TEAM_ID" build 2>&1 | tail -5
APP="$OUT/DerivedData/Build/Products/Debug-iphoneos/FocusCompanion.app"
[ -d "$APP" ] || { echo "the build did not produce $APP" >&2; exit 1; }
ditto "$APP" "$OUT/Hushd for iPhone.app"
codesign --verify --verbose=1 "$OUT/Hushd for iPhone.app" 2>&1 | tail -1
echo "built $OUT/Hushd for iPhone.app"
echo "now run ./tools/build_app.sh to carry it inside Hushd.app"

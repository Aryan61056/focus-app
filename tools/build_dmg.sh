#!/bin/bash
# Packs Focus.app into a disk image people install from: mac/.build/Focus-<version>.dmg, holding the app and an Applications shortcut,
# with a SHA-256 file beside it. Nothing is uploaded or published.
#
#   ./tools/build_dmg.sh              builds the app for handing out (tools/build_app.sh, FOCUS_DISTRIBUTION=1), then packs it
#   ./tools/build_dmg.sh --no-build   packs the Focus.app already in mac/.build (as long as it was built with FOCUS_DISTRIBUTION=1)
#
# What people get depends on how the app is signed (the variables are described in tools/build_app.sh):
#   no variables        Ad-hoc signed. It opens on another Mac only after the person approves it once in System Settings (Privacy &
#                       Security, Open Anyway), because macOS has no developer to trust. The image then carries a short "How to open"
#                       note. No iCloud features (Friends, iPhone sync) in this build.
#   FOCUS_SIGN_IDENTITY a "Developer ID Application" identity, with the iCloud variables, signs the app for handing out. Add
#                       FOCUS_NOTARY_PROFILE (a profile made with `xcrun notarytool store-credentials`) and the image is signed,
#                       notarized and stapled, which is what lets it open without the warning. THAT PATH HAS NOT BEEN RUN: it needs
#                       the owner's Apple Developer account. Signing and notarization are the owner's decision (CLAUDE.md).
# The bundle id is still the working placeholder (FOCUS_BUNDLE_ID); the product name and bundle id are the owner's to choose.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/mac/.build"
APP="$BUILD/Focus.app"

if [ "${1:-}" != "--no-build" ]; then
  FOCUS_DISTRIBUTION=1 "$ROOT/tools/build_app.sh"
fi
[ -d "$APP" ] || { echo "no $APP; run without --no-build" >&2; exit 1; }
if /usr/libexec/PlistBuddy -c "Print :FocusBuildSource" "$APP/Contents/Info.plist" >/dev/null 2>&1; then
  echo "this Focus.app was built for local use (it names the folder it was built in); rebuild without --no-build" >&2; exit 1
fi
codesign --verify --deep --strict "$APP" 2>&1 || { echo "the app's signature does not verify" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
# A beta build is named for its number, so two betas of one version never overwrite each other.
CHANNEL="$(/usr/libexec/PlistBuddy -c "Print :FocusChannel" "$APP/Contents/Info.plist" 2>/dev/null || echo dev)"
if [ "$CHANNEL" = beta ]; then VERSION="$VERSION-beta.$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")"; fi
DMG="$BUILD/Focus-$VERSION.dmg"
WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
trap 'hdiutil detach "$MOUNT" -quiet -force >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

DEVELOPER_ID=0
if codesign -dvv "$APP" 2>&1 | grep -q "^Authority=Developer ID Application"; then DEVELOPER_ID=1; fi

# What goes on the disk: the app (copied with its signature and extended attributes), a shortcut to Applications, and, for a build macOS
# will not vouch for, the one-time steps. ditto keeps the bundle byte-for-byte; cp -R can lose the signature's resource forks.
STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Focus.app"
ln -s /Applications "$STAGE/Applications"
if [ "$DEVELOPER_ID" = 0 ]; then
  cat > "$STAGE/How to open.txt" <<'TEXT'
Focus

1. Drag Focus onto Applications.
2. Open Focus from Applications. macOS says it cannot check the app, because this copy has no Apple developer signature yet.
   Choose Done, then open System Settings, Privacy & Security, scroll to the message about Focus and choose Open Anyway.
   You only do this once.
3. Focus asks for Accessibility the first time it needs to see which window you are in. Screen Recording is asked for only if you
   turn on screen reading.

Focus reads your screen with Apple's on-device model, so it needs a Mac with Apple silicon and Apple Intelligence turned on.
TEXT
fi

if [ "$CHANNEL" = beta ]; then
  cat > "$STAGE/For testers.txt" <<'TEXT'
Thank you for testing Focus.

Send feedback from your profile at the bottom left of the Focus window, or from Help, Send Feedback. You see the whole report
before you save it, and Focus itself sends nothing. Reports never hold task or project names, window titles, addresses, screen
words or pictures.

This beta has an end date. After it, Focus keeps working and says a newer build is waiting.
TEXT
fi

rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "Focus" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

if [ "$DEVELOPER_ID" = 1 ] && [ -n "${FOCUS_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$FOCUS_SIGN_IDENTITY" "$DMG"
  if [ -n "${FOCUS_NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$FOCUS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  else
    echo "signed with Developer ID but not notarized: set FOCUS_NOTARY_PROFILE to notarize"
  fi
fi

# Check what was built, not what was meant: the image is sound, mounts read-only, holds the app with an intact signature that is the very
# same program, and the Applications shortcut points where it should.
hdiutil verify "$DMG" >/dev/null
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -readonly -nobrowse -noverify -mountpoint "$MOUNT" >/dev/null
[ -d "$MOUNT/Focus.app" ] || { echo "Focus.app is missing from the image" >&2; exit 1; }
[ "$(readlink "$MOUNT/Applications")" = "/Applications" ] || { echo "the Applications shortcut is wrong" >&2; exit 1; }
codesign --verify --deep --strict "$MOUNT/Focus.app" 2>&1 || { echo "the app's signature broke inside the image" >&2; exit 1; }
SAME_A="$(shasum -a 256 "$APP/Contents/MacOS/focus-app" | cut -d' ' -f1)"
SAME_B="$(shasum -a 256 "$MOUNT/Focus.app/Contents/MacOS/focus-app" | cut -d' ' -f1)"
[ "$SAME_A" = "$SAME_B" ] || { echo "the program in the image differs from the one built" >&2; exit 1; }
ARCHS="$(lipo -archs "$MOUNT/Focus.app/Contents/MacOS/focus-app")"
GATEKEEPER="$(spctl -a -t exec -vv "$MOUNT/Focus.app" 2>&1 | head -1 || true)"
hdiutil detach "$MOUNT" -quiet

( cd "$BUILD" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )
echo "built $DMG ($(du -h "$DMG" | cut -f1)), version $VERSION, architectures: $ARCHS"
echo "sha256 $(cut -d' ' -f1 "$DMG.sha256")"
echo "Gatekeeper on this Mac says: $GATEKEEPER"
if [ "$DEVELOPER_ID" = 0 ]; then echo "ad-hoc signed: other Macs will ask for Open Anyway once (see the note on the disk). Not notarized."; fi

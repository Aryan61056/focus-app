#!/bin/bash
# Cuts a release for installed copies to update to: builds the image (tools/build_dmg.sh, channel "release"), puts it in dist/updates/ next
# to the other versions, and signs the feed (dist/updates/appcast.xml) with Hushd's update key. It publishes NOTHING: it prints what to
# upload, so you read it first. The feed and the image can live anywhere over https; the address is baked into the app at build time
# (FOCUS_FEED_URL, default https://hushd.store/updates/appcast.xml) and is the owner's to choose (docs/UPDATES.md).
#
#   tools/release.sh 0.2.0
#   FOCUS_FEED_URL=https://example.org/hushd/appcast.xml FOCUS_DOWNLOAD_PREFIX=https://example.org/hushd/ tools/release.sh 0.2.0
#
# The build number is the UTC time (YYYYMMDDHHMM), so every release is higher than the one before it, and higher than any beta number.
# Sparkle compares build numbers, never version names. Needs the update key in the login Keychain (generate_keys --account hushd).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: tools/release.sh <version>   e.g. 0.2.0}"
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "version must look like 0.2.0" >&2; exit 2; }
BUILD="$(date -u +%Y%m%d%H%M)"
FEED="${FOCUS_FEED_URL:-https://hushd.store/updates/appcast.xml}"
PREFIX="${FOCUS_DOWNLOAD_PREFIX:-${FEED%/*}/}"
SPARKLE_BIN="$ROOT/mac/.build/artifacts/sparkle/Sparkle/bin"
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "no Sparkle tools; run: (cd mac && swift package resolve)" >&2; exit 1; }

# The key in the Keychain must be the one the app trusts, or no installed copy would accept this release.
PUB="$(tr -d '[:space:]' < "$ROOT/tools/update/public-key.txt")"
KEYCHAIN_PUB="$("$SPARKLE_BIN/generate_keys" --account hushd -p 2>/dev/null || true)"
[ "$KEYCHAIN_PUB" = "$PUB" ] || { echo "the update key in your Keychain ($KEYCHAIN_PUB) is not the one in tools/update/public-key.txt ($PUB)" >&2; exit 1; }

if [ -n "$(git -C "$ROOT" status --porcelain -- mac core tools 2>/dev/null)" ]; then
  echo "Commit your changes first, so the release matches a commit." >&2; exit 1
fi

FOCUS_CHANNEL=release FOCUS_VERSION="$VERSION" FOCUS_BUILD_NUMBER="$BUILD" FOCUS_FEED_URL="$FEED" "$ROOT/tools/build_dmg.sh"
UPDATES="$ROOT/dist/updates"; mkdir -p "$UPDATES"
cp "$ROOT/mac/.build/Hushd-$VERSION.dmg" "$ROOT/mac/.build/Hushd-$VERSION.dmg.sha256" "$UPDATES/"
"$SPARKLE_BIN/generate_appcast" --account hushd --download-url-prefix "$PREFIX" "$UPDATES"
cp "$ROOT/mac/.build/Hushd-$VERSION.dmg" "$ROOT/dist/Hushd.dmg"

cat <<DONE

Built $VERSION (build $BUILD). Nothing is published. To publish, put these where the app looks:
  $FEED       <-  $UPDATES/appcast.xml
  ${PREFIX}Hushd-$VERSION.dmg   <-  $UPDATES/Hushd-$VERSION.dmg
  (and dist/Hushd.dmg is the same image, for the website's Download button)
Installed copies pick it up within a day, or from Settings > General > Check for updates.
DONE

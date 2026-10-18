#!/bin/bash
# Makes the next beta: bumps the beta number, builds a signed-as-configured DMG with the beta's end date, notes and feedback address
# stamped in, and writes beta/releases/<version>-beta.<n>/ with the image, its checksum, a manifest and an invite to paste.
# Nothing is uploaded, published or sent. Handing the image to testers is the owner's step (docs/BETA.md).
#
#   tools/beta/release.sh                         notes from beta/notes/next.md, 30 days, no feedback address
#   tools/beta/release.sh --days 21 --email beta@example.org --notes beta/notes/next.md
#   tools/beta/release.sh --dry-run               shows what it would do, builds nothing, bumps nothing
#
# Signing follows tools/build_app.sh and tools/build_dmg.sh (FOCUS_SIGN_IDENTITY, FOCUS_NOTARY_PROFILE, ...). Without them testers
# need Open Anyway once; the image says how.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COUNTER="$ROOT/beta/BUILD"
NOTES="$ROOT/beta/notes/next.md"
DAYS=30
EMAIL="${FOCUS_FEEDBACK_EMAIL:-}"
VERSION="${FOCUS_VERSION:-0.1.0}"
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2;;
    --days) DAYS="$2"; shift 2;;
    --email) EMAIL="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    -h|--help) sed -n '2,13p' "$0"; exit 0;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done
case "$DAYS" in ''|*[!0-9]*) echo "--days takes a whole number" >&2; exit 2;; esac
if [ -n "$EMAIL" ] && ! printf '%s' "$EMAIL" | grep -Eq '^[^@ ]+@[^@ ]+\.[^@ ]+$'; then echo "--email does not look like an address" >&2; exit 2; fi
[ -f "$NOTES" ] || { echo "no release notes at $NOTES (one change per line, '- ' bullets are fine)" >&2; exit 1; }
[ "$(grep -cv '^\s*\(#.*\)\?$' "$NOTES")" -gt 0 ] || { echo "$NOTES has no lines" >&2; exit 1; }
if [ -n "$(git -C "$ROOT" status --porcelain -- mac core tools 2>/dev/null)" ]; then
  echo "warning: uncommitted changes in mac/, core/ or tools/; this beta will not match any commit" >&2
fi

LAST="$(cat "$COUNTER" 2>/dev/null || echo 0)"
N=$((LAST + 1))
NAME="$VERSION-beta.$N"
EXPIRES="$(date -v+"${DAYS}"d +%Y-%m-%d)"
OUT="$ROOT/beta/releases/$NAME"
echo "beta $NAME: ends $EXPIRES, notes $(basename "$NOTES"), feedback ${EMAIL:-saved as a file only}"
if [ "$DRY" = 1 ]; then echo "dry run: nothing built"; exit 0; fi
[ -e "$OUT" ] && { echo "$OUT already exists" >&2; exit 1; }

FOCUS_CHANNEL=beta FOCUS_BUILD_NUMBER="$N" FOCUS_VERSION="$VERSION" FOCUS_BETA_EXPIRES="$EXPIRES" \
FOCUS_FEEDBACK_EMAIL="$EMAIL" FOCUS_RELEASE_NOTES_FILE="$NOTES" "$ROOT/tools/build_dmg.sh"

DMG="$ROOT/mac/.build/Focus-$NAME.dmg"
[ -f "$DMG" ] || { echo "expected $DMG" >&2; exit 1; }
PLIST="$ROOT/mac/.build/Focus.app/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c "Print :FocusChannel" "$PLIST")" = beta ] || { echo "the built app is not marked beta" >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")" = "$N" ] || { echo "the built app has the wrong build number" >&2; exit 1; }

mkdir -p "$OUT"
cp "$DMG" "$DMG.sha256" "$OUT/"
cp "$NOTES" "$OUT/notes.md"
BUILD_ID="$(/usr/libexec/PlistBuddy -c "Print :FocusBuildID" "$PLIST")"
SHA="$(cut -d' ' -f1 "$DMG.sha256")"
SIGNED="ad-hoc"; codesign -dvv "$ROOT/mac/.build/Focus.app" 2>&1 | grep -q "^Authority=Developer ID Application" && SIGNED="developer-id"
python3 - "$OUT/release.json" "$NAME" "$VERSION" "$N" "$BUILD_ID" "$EXPIRES" "$SHA" "$SIGNED" "${EMAIL:+yes}" "$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)" "$NOTES" <<'PY'
import json, sys, datetime
out, name, version, n, build_id, expires, sha, signed, email, commit, notes = sys.argv[1:]
lines = [l.strip()[2:] if l.strip()[:2] in ("- ", "* ") else l.strip() for l in open(notes) if l.strip() and not l.strip().startswith("#")]
json.dump({"name": name, "version": version, "build": int(n), "buildID": build_id, "made": datetime.date.today().isoformat(),
           "expires": expires, "sha256": sha, "signing": signed, "feedbackEmail": bool(email), "commit": commit,
           "dmg": f"Focus-{name}.dmg", "notes": lines}, open(out, "w"), indent=2)
PY
cat > "$OUT/invite.txt" <<TEXT
Focus $NAME is ready to try.

1. Open Focus-$NAME.dmg and drag Focus onto Applications.
2. Open it from Applications.$( [ "$SIGNED" = ad-hoc ] && printf '%s' " macOS will say it cannot check the app: choose Done, then System Settings, Privacy & Security, Open Anyway. Once only." )
3. Work as you normally would for a week. Focus needs Apple silicon and Apple Intelligence turned on.

When something breaks, feels wrong or gives you an idea: click your name at the bottom left of the Focus window, then Send feedback.
You see the whole report before you save it. Focus sends nothing on its own, and reports never hold your task names, window titles,
addresses or anything from your screen.

This build stops being current on $EXPIRES. It keeps working after that.
Checksum (SHA-256): $SHA
TEXT
echo "$N" > "$COUNTER"
echo "release folder: $OUT"
echo "next: hand $OUT/Focus-$NAME.dmg and invite.txt to testers yourself; log who got it with tools/beta/testers.py sent <name> $NAME"

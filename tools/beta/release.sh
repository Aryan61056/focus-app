#!/bin/bash
# Makes the next beta: bumps the beta number, builds a signed-as-configured DMG with the beta's end date, notes, known issues, GitHub
# project and feedback address stamped in, and writes beta/releases/<version>-beta.<n>/ with the image, its checksum, a manifest, an
# invite to paste and the GitHub release text. Nothing is uploaded, published or sent: tools/beta/publish.sh puts a finished folder on
# GitHub as a pre-release, and handing the image out by hand still works (docs/BETA.md).
#
#   tools/beta/release.sh                         notes from beta/notes/next.md, known issues from beta/notes/known.md, 30 days,
#                                                 GitHub project from the origin remote, no feedback address
#   tools/beta/release.sh --days 21 --email beta@example.org --repo https://github.com/owner/repo
#   tools/beta/release.sh --no-repo               no GitHub project: reports are files only, no "Get the newest build" link
#   tools/beta/release.sh --dry-run               shows what it would do, builds nothing, bumps nothing
#
# Signing follows tools/build_app.sh and tools/build_dmg.sh (FOCUS_SIGN_IDENTITY, FOCUS_NOTARY_PROFILE, ...). Without them testers
# need Open Anyway once; the image says how.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COUNTER="$ROOT/beta/BUILD"
NOTES="$ROOT/beta/notes/next.md"
KNOWN="$ROOT/beta/notes/known.md"
DAYS=30
EMAIL="${FOCUS_FEEDBACK_EMAIL:-}"
VERSION="${FOCUS_VERSION:-0.1.0}"
# The origin remote's GitHub project as https://github.com/<owner>/<repo>, when it is one.
REPO="${FOCUS_FEEDBACK_REPO-$(python3 "$ROOT/tools/beta/release_text.py" --origin-repo "$ROOT")}"
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2;;
    --known) KNOWN="$2"; shift 2;;
    --days) DAYS="$2"; shift 2;;
    --email) EMAIL="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --no-repo) REPO=""; shift;;
    --version) VERSION="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    -h|--help) sed -n '2,15p' "$0"; exit 0;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done
case "$DAYS" in ''|*[!0-9]*) echo "--days takes a whole number" >&2; exit 2;; esac
if [ -n "$EMAIL" ] && ! printf '%s' "$EMAIL" | grep -Eq '^[^@ ]+@[^@ ]+\.[^@ ]+$'; then echo "--email does not look like an address" >&2; exit 2; fi
if [ -n "$REPO" ] && ! printf '%s' "$REPO" | grep -Eq '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then echo "--repo must be https://github.com/<owner>/<repo>" >&2; exit 2; fi
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
KNOWN_COUNT=0; if [ -f "$KNOWN" ]; then KNOWN_COUNT="$(grep -cv '^\s*\(#.*\)\?$' "$KNOWN" || true)"; fi
echo "beta $NAME: ends $EXPIRES, notes $(basename "$NOTES"), $KNOWN_COUNT known issue(s), feedback as a file${EMAIL:+ or mail to $EMAIL}${REPO:+ or GitHub issues at $REPO}"
if [ "$DRY" = 1 ]; then echo "dry run: nothing built"; exit 0; fi
[ -e "$OUT" ] && { echo "$OUT already exists" >&2; exit 1; }

FOCUS_CHANNEL=beta FOCUS_BUILD_NUMBER="$N" FOCUS_VERSION="$VERSION" FOCUS_BETA_EXPIRES="$EXPIRES" \
FOCUS_FEEDBACK_EMAIL="$EMAIL" FOCUS_FEEDBACK_REPO="$REPO" FOCUS_RELEASE_NOTES_FILE="$NOTES" FOCUS_KNOWN_ISSUES_FILE="$KNOWN" \
"$ROOT/tools/build_dmg.sh"

DMG="$ROOT/mac/.build/Hushd-$NAME.dmg"
[ -f "$DMG" ] || { echo "expected $DMG" >&2; exit 1; }
PLIST="$ROOT/mac/.build/Hushd.app/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c "Print :FocusChannel" "$PLIST")" = beta ] || { echo "the built app is not marked beta" >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")" = "$N" ] || { echo "the built app has the wrong build number" >&2; exit 1; }
if [ -n "$REPO" ]; then
  [ "$(/usr/libexec/PlistBuddy -c "Print :FocusFeedbackRepo" "$PLIST")" = "$REPO" ] || { echo "the built app does not name $REPO" >&2; exit 1; }
fi

mkdir -p "$OUT"
cp "$DMG" "$DMG.sha256" "$OUT/"
cp "$NOTES" "$OUT/notes.md"
if [ -f "$KNOWN" ]; then cp "$KNOWN" "$OUT/known.md"; else : > "$OUT/known.md"; fi
BUILD_ID="$(/usr/libexec/PlistBuddy -c "Print :FocusBuildID" "$PLIST")"
SHA="$(cut -d' ' -f1 "$DMG.sha256")"
SIGNED="ad-hoc"; codesign -dvv "$ROOT/mac/.build/Hushd.app" 2>&1 | grep -q "^Authority=Developer ID Application" && SIGNED="developer-id"
python3 "$ROOT/tools/beta/release_text.py" --manifest "$OUT/release.json" --name "$NAME" --version "$VERSION" --build "$N" \
  --build-id "$BUILD_ID" --expires "$EXPIRES" --sha "$SHA" --signing "$SIGNED" ${EMAIL:+--email} \
  --commit "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo nogit)" --notes "$OUT/notes.md" --known "$OUT/known.md" ${REPO:+--repo "$REPO"}
python3 "$ROOT/tools/beta/release_text.py" --invite "$OUT/release.json" > "$OUT/invite.txt"
python3 "$ROOT/tools/beta/release_text.py" --github "$OUT/release.json" > "$OUT/github-release.md"
echo "$N" > "$COUNTER"
echo "release folder: $OUT"
echo "next: tools/beta/publish.sh $NAME puts it on GitHub as a pre-release, or hand $OUT/Hushd-$NAME.dmg and invite.txt"
echo "      to testers yourself; log who got it with tools/beta/testers.py sent <name> $NAME"

#!/bin/bash
# Puts a finished beta (beta/releases/<name>/, made by tools/beta/release.sh) on GitHub as a pre-release: tag v<name> at the commit it
# was built from, the text from github-release.md, and the image with its checksum attached. This PUBLISHES: anyone who can see the
# repository can download the build. It asks before doing it unless --yes is given.
#
#   tools/beta/publish.sh 0.1.0-beta.2 --dry-run   checks everything and prints the release text; publishes nothing
#   tools/beta/publish.sh 0.1.0-beta.2             asks, then publishes
#   tools/beta/publish.sh 0.1.0-beta.2 --yes       publishes without asking (the owner's go-ahead was given some other way)
#
# Undo: gh release delete v<name> --cleanup-tag --repo <owner>/<repo>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NAME="${1:-}"; shift || true
DRY=0; YES=0
while [ $# -gt 0 ]; do
  case "$1" in --dry-run) DRY=1; shift;; --yes) YES=1; shift;; *) echo "unknown option $1" >&2; exit 2;; esac
done
[ -n "$NAME" ] || { sed -n '2,10p' "$0"; exit 2; }
DIR="$ROOT/beta/releases/$NAME"
[ -f "$DIR/release.json" ] || { echo "no release at $DIR (run tools/beta/release.sh first)" >&2; exit 1; }
command -v gh >/dev/null || { echo "needs the GitHub CLI (gh)" >&2; exit 1; }

field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print("" if v is None else v)' "$DIR/release.json" "$1"; }
REPO_URL="$(field repo)"; TAG="$(field tag)"; COMMIT="$(field commit)"; DMG="$DIR/$(field dmg)"; SHA="$(field sha256)"
VERSION="$(field version)"; BUILD="$(field build)"
[ -n "$REPO_URL" ] || { echo "this beta was built without a GitHub project (--no-repo); rebuild it with one" >&2; exit 1; }
REPO="${REPO_URL#https://github.com/}"
[ -f "$DMG" ] || { echo "missing $DMG" >&2; exit 1; }
[ "$(shasum -a 256 "$DMG" | cut -d' ' -f1)" = "$SHA" ] || { echo "the image does not match its recorded checksum" >&2; exit 1; }
[ -f "$DIR/github-release.md" ] || python3 "$ROOT/tools/beta/release_text.py" --github "$DIR/release.json" > "$DIR/github-release.md"

gh auth status >/dev/null 2>&1 || { echo "gh is not signed in (gh auth login)" >&2; exit 1; }
git -C "$ROOT" fetch -q origin
# The tag must point at code anyone can read: the commit has to be on the remote already.
if ! git -C "$ROOT" branch -r --contains "$COMMIT" 2>/dev/null | grep -q .; then
  echo "commit $COMMIT is not on origin yet; push it first so the tag points at code testers can see" >&2; exit 1
fi
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then echo "$TAG is already published on $REPO" >&2; exit 1; fi

echo "publish Focus $VERSION beta $BUILD to $REPO_URL as pre-release $TAG at ${COMMIT:0:12}, with $(basename "$DMG") ($(du -h "$DMG" | cut -f1))"
if [ "$DRY" = 1 ]; then echo "----- release text"; cat "$DIR/github-release.md"; echo "-----"; echo "dry run: nothing published"; exit 0; fi
if [ "$YES" != 1 ]; then
  read -r -p "This makes the build public on GitHub. Type 'publish' to go on: " answer
  [ "$answer" = publish ] || { echo "nothing published"; exit 1; }
fi
gh release create "$TAG" "$DMG" "$DMG.sha256" --repo "$REPO" --target "$COMMIT" --prerelease \
  --title "Focus $VERSION beta $BUILD" --notes-file "$DIR/github-release.md"
python3 - "$DIR/release.json" <<'PYEND'
import json, sys, datetime
p = sys.argv[1]; m = json.load(open(p)); m["published"] = datetime.date.today().isoformat(); json.dump(m, open(p, "w"), indent=2)
PYEND
echo "published: $REPO_URL/releases/tag/$TAG"

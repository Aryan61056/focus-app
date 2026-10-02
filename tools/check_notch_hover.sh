#!/bin/bash
# Regression check for the notch/pill: launches the demo build (scripted session, in-memory data), moves the real pointer onto the panel and away
# three times, and fails if the app died (the 2026-10-01 hover crash) or the panel never grew (hover not delivered while Focus is in the background).
# Moves your pointer for about 15 seconds. Needs a built mac/.build/Focus.app (tools/build_app.sh) and a logged-in desktop. Not part of `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"; unset SDKROOT
T=$(mktemp -d); swiftc -o "$T/hover" tools/hover_pointer.swift; swiftc -o "$T/frames" tools/panel_frames.swift
pkill -x focus-app 2>/dev/null || true; sleep 1
open -n --env FOCUS_DEMO=1 mac/.build/Focus.app
sleep 6
"$T/frames" > "$T/frames.txt" &
"$T/hover" 3 >/dev/null; cp "$T/frames.txt" /tmp/frames-last.txt 2>/dev/null || true
sleep 2
if ! pgrep -x focus-app >/dev/null; then echo "FAIL: app died while hovering (see ~/Library/Logs/DiagnosticReports)"; exit 1; fi
pkill -x focus-app || true
rest=$(awk '{print $5}' "$T/frames.txt" | sort -n | head -1); open=$(awk '{print $5}' "$T/frames.txt" | sort -n | tail -1)
if [ -z "$open" ] || [ "$(printf '%.0f' "$open")" -le "$(printf '%.0f' "$rest")" ]; then echo "FAIL: the panel never grew (rest ${rest:-?}, max ${open:-?})"; exit 1; fi
echo "ok: app survived and the panel grew from $rest to $open points"

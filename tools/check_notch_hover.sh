#!/bin/bash
# Regression check for the notch/pill: launches the demo build (scripted session, in-memory data), moves the real pointer onto the panel and away
# three times, and fails if the app died (the 2026-10-01 hover crash) or its notch panel was not on screen.
# Since 2026-10-15 the notch window is a fixed size (437 by 132 pt on a 185 pt notch since 2026-10-16) for the whole session (the shape inside it grows), so window frames can no
# longer show whether hover arrived; that needs eyes on the real notch. Only the dev build is started, watched and stopped: an installed
# copy of Hushd that is running a session is left alone.
# Moves your pointer for about 15 seconds. Needs a built mac/.build/Hushd.app (tools/build_app.sh) and a logged-in desktop. Not part of `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"; unset SDKROOT
DEV="mac/.build/Hushd.app/Contents/MacOS/focus-app"
T=$(mktemp -d); swiftc -o "$T/hover" tools/hover_pointer.swift; swiftc -o "$T/frames" tools/panel_frames.swift
pkill -f "$DEV" 2>/dev/null || true; sleep 1
open -n --env FOCUS_DEMO=1 mac/.build/Hushd.app --args -ApplePersistenceIgnoreState YES
sleep 6
PID=$(pgrep -f "$DEV" | head -1)
"$T/frames" "$PID" > "$T/frames.txt" &
"$T/hover" 3 >/dev/null; cp "$T/frames.txt" /tmp/frames-last.txt 2>/dev/null || true
sleep 2
if ! pgrep -f "$DEV" >/dev/null; then echo "FAIL: app died while hovering (see ~/Library/Logs/DiagnosticReports)"; exit 1; fi
pkill -f "$DEV" || true; wait
n=$(wc -l < "$T/frames.txt" | tr -d ' ')
if [ "$n" -eq 0 ]; then echo "FAIL: no notch panel from the demo build was on screen"; exit 1; fi
echo "ok: app survived three hovers; its notch panel was on screen in $n of 26 samples ($(awk '{print $4 "x" $5}' "$T/frames.txt" | sort -u | tr '\n' ' '))"

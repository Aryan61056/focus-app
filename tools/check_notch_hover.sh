#!/bin/bash
# Regression check for the 2026-10-01 hover crash: launches the demo build (scripted session, in-memory data), moves the real pointer onto the
# top-centre of the main screen and away three times, and fails if the app died. Moves your pointer for about 10 seconds.
# Needs a built mac/.build/Focus.app (tools/build_app.sh) and a logged-in desktop. Not part of `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"; unset SDKROOT
T=$(mktemp -d); swiftc -o "$T/hover" tools/hover_pointer.swift
pkill -x focus-app 2>/dev/null || true; sleep 1
(FOCUS_DEMO=1 mac/.build/Focus.app/Contents/MacOS/focus-app >/dev/null 2>&1 &)
sleep 5
"$T/hover" >/dev/null
sleep 2
if pgrep -x focus-app >/dev/null; then echo "ok: app survived hovering the notch"; pkill -x focus-app; else echo "FAIL: app died while hovering (see ~/Library/Logs/DiagnosticReports)"; exit 1; fi

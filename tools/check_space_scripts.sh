#!/bin/bash
# Runs the AppleScript Focus generates for Arc and Dia (space-aware Back to task and the tab ladder) against stand-in apps that follow
# their scripting dictionaries. Opens a windowless background app for a moment; asks for no permission and touches nothing of yours.
# Proves the scripts' logic, not the real browsers: see tools/check_space_scripts/run.py and tools/check_space_browsers.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"; unset SDKROOT
(cd mac && swift build --product script-dump 2>&1 | tail -1)
python3 tools/check_space_scripts/run.py

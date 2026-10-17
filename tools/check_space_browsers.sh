#!/bin/bash
# Owner-run check of the Arc and Dia scripts behind space-aware Back to task (docs/NUDGE-IDEAS.md, "Spaces in one window").
# Read-only: it asks each running browser for its front window's space (Arc) or profile (Dia), and whether the front tab has an address.
# It prints no address and no title. The first run makes macOS ask whether your terminal may control the browser (Automation);
# that is your call, and an agent cannot grant it. Nothing is clicked, switched or changed.
set -u

check() {
  local app="$1" script="$2"
  if ! pgrep -xq "$app"; then echo "$app: not running, skipped"; return; fi
  local out
  if ! out=$(osascript -e "$script" 2>&1); then echo "$app: FAILED: $out"; return; fi
  echo "$app: ok. Space or profile: ${out:-<none returned>}"
}

check "Arc" 'tell application "Arc"
  if (count of windows) is 0 then return "no window"
  set sp to (id of active space of front window) as text
  set hasURL to ((URL of active tab of front window) is not "")
  return sp & " (front tab has an address: " & hasURL & ", spaces in this window: " & (count of spaces of front window) & ")"
end tell'

check "Dia" 'tell application "Dia"
  if (count of windows) is 0 then return "no window"
  return (name of active profile of front window) as text & " (profiles in this window: " & (count of profiles of front window) & ")"
end tell'

echo "Compare against what you see in each browser. If a line says FAILED with -1743, Automation was refused: Settings, Privacy & Security, Automation."

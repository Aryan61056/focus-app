#!/bin/bash
# Owner-run check of the Arc and Dia scripts behind space-aware Back to task (docs/NUDGE-IDEAS.md, "Spaces in one window").
# Read-only by default: nothing is clicked, switched, focused or closed. It prints no address and no title, only counts and times.
# The first run makes macOS ask whether your terminal may control the browser (Automation); that is your call, and an agent cannot grant it.
#
#   ./tools/check_space_browsers.sh          the front window's space (Arc) or profile (Dia), and whether the front tab has an address
#   ./tools/check_space_browsers.sh --tabs   also walks every window, space or profile and tab the way the real script does (reading each tab's
#                                            address and counting those that have one), and says how long that took. The app's script gives up
#                                            after 3 seconds, so a window with very many tabs could be too slow; this tells you.
#   ./tools/check_space_browsers.sh --act    the one mode that does something: sends the same `focus` and `select` commands the app sends, but to
#                                            the space or profile and the tab you are already in, so nothing should change on screen (the
#                                            browser may come to the front for a moment). Nothing is closed or opened.
set -u

now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }

check() {
  local app="$1" script="$2"
  if ! pgrep -xq "$app"; then echo "$app: not running, skipped"; return; fi
  local out
  if ! out=$(osascript -e "$script" 2>&1); then echo "$app: FAILED: $out"; return; fi
  echo "$app: ok. Space or profile: ${out:-<none returned>}"
}

walk() {
  local app="$1" script="$2"
  if ! pgrep -xq "$app"; then return; fi
  local start out end
  start=$(now)
  if ! out=$(osascript -e "$script" 2>&1); then echo "$app tabs: FAILED: $out"; return; fi
  end=$(now)
  local secs; secs=$(perl -e "printf '%.2f', $end - $start")
  local note=""; perl -e "exit(($secs) > 2.5 ? 0 : 1)" && note=" (close to the app's 3 second limit: tab switching in this browser may time out)"
  echo "$app tabs: $out, walked in ${secs}s$note"
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

if [ "${1:-}" = "--tabs" ]; then
  # Private windows are skipped in Arc (its dictionary says which they are). Dia's does not, so its count includes whatever windows are open.
  walk "Arc" 'with timeout of 30 seconds
tell application "Arc"
  set nWin to 0
  set nSpaces to 0
  set nTabs to 0
  set nAddr to 0
  repeat with w in windows
    if (mode of w) is not "incognito" then
      set nWin to nWin + 1
      repeat with s in spaces of w
        set nSpaces to nSpaces + 1
        repeat with t in tabs of s
          set nTabs to nTabs + 1
          try
            if ((URL of t) starts with "http") then set nAddr to nAddr + 1
          end try
        end repeat
      end repeat
    end if
  end repeat
  return (nWin as text) & " windows, " & nSpaces & " spaces, " & nTabs & " tabs, " & nAddr & " with an address"
end tell
end timeout'
  walk "Dia" 'with timeout of 30 seconds
tell application "Dia"
  set nWin to 0
  set nProfiles to 0
  set nTabs to 0
  set nAddr to 0
  repeat with w in windows
    set nWin to nWin + 1
    repeat with p in profiles of w
      set nProfiles to nProfiles + 1
      repeat with t in tabs of p
        set nTabs to nTabs + 1
        try
          if ((URL of t) starts with "http") then set nAddr to nAddr + 1
        end try
      end repeat
    end repeat
  end repeat
  return (nWin as text) & " windows, " & nProfiles & " profiles, " & nTabs & " tabs, " & nAddr & " with an address"
end tell
end timeout'
fi

if [ "${1:-}" = "--act" ]; then
  if pgrep -xq "Arc"; then
    out=$(osascript -e 'tell application "Arc"
  if (count of windows) is 0 then return "no window"
  set w to front window
  if (mode of w) is "incognito" then return "skipped, the front window is private"
  set s to active space of w
  tell s to focus
  set t to active tab of w
  tell t to select
  return "focus and select accepted, still in the same space: " & (((id of active space of w) as text) is ((id of s) as text))
end tell' 2>&1) && echo "Arc act: $out" || echo "Arc act: FAILED: $out"
  fi
  if pgrep -xq "Dia"; then
    out=$(osascript -e 'tell application "Dia"
  if (count of windows) is 0 then return "no window"
  set w to front window
  set p to active profile of w
  focus p
  set t to active tab of w
  focus t
  return "focus accepted, still in the same profile: " & (((name of active profile of w) as text) is ((name of p) as text))
end tell' 2>&1) && echo "Dia act: $out" || echo "Dia act: FAILED: $out"
  fi
fi

echo "Compare against what you see in each browser. If a line says FAILED with -1743, Automation was refused: Settings, Privacy & Security, Automation."

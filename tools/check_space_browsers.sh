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
#   ./tools/check_space_browsers.sh --switch the real thing: switches to a tab in a DIFFERENT space (Arc) or profile (Dia) of the front window
#                                            with the app's own script, checks it got there, then switches back the same way and checks that.
#                                            You will see the browser change space and change back. Needs the script dumper built first:
#                                            (cd mac && swift build --product script-dump). Prints only yes or no, never an address.
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

if [ "${1:-}" = "--switch" ]; then
  DUMP="$(cd "$(dirname "$0")/.." && pwd)/mac/.build/debug/script-dump"
  [ -x "$DUMP" ] || { echo "build the script dumper first: (cd mac && swift build --product script-dump)"; exit 1; }
  TAB=$'\t'
  # How the app really goes back: Arc by the page's address, Dia by the tab's title (Dia's addresses are never read, so a Dia place has none).
  # $1 app, $2 reads "where<TAB>what" of the front tab, $3 finds "where<TAB>what" of a tab in another space or profile, $4 reads "where"
  # afterwards, $5 restores "where" if the way back fails, $6 the word for it, $7 how to switch (switchTo or switchToTitle)
  switch_test() {
    local app="$1" cur_script="$2" find_script="$3" where_script="$4" restore_script="$5" word="$6" how="$7" cur target here_sp here_what tsp twhat
    pgrep -xq "$app" || return
    cur=$(osascript -e "$cur_script" 2>&1) || { echo "$app switch: could not read where you are: $cur"; return; }
    [ -n "$cur" ] || { echo "$app switch: skipped (no window, or a private one)"; return; }
    here_sp="${cur%%$TAB*}"; here_what="${cur#*$TAB}"
    target=$(osascript -e "$find_script" 2>&1) || { echo "$app switch: could not look for another $word: $target"; return; }
    [ -n "$target" ] || { echo "$app switch: skipped (nothing to switch to in another $word of the front window)"; return; }
    tsp="${target%%$TAB*}"; twhat="${target#*$TAB}"
    local r1 r2="not tried" now1 now2 fwd=no back=no fallback=no
    r1=$("$DUMP" "$how" "$app" "$twhat" "$tsp" | osascript 2>&1); now1=$(osascript -e "$where_script" 2>&1)
    [ "$r1" = "ok" ] && [ "$now1" = "$tsp" ] && fwd=yes
    if [ -n "$here_what" ]; then r2=$("$DUMP" "$how" "$app" "$here_what" "$here_sp" | osascript 2>&1); fi
    now2=$(osascript -e "$where_script" 2>&1)
    [ "$r2" = "ok" ] && [ "$now2" = "$here_sp" ] && back=yes
    if [ "$now2" != "$here_sp" ]; then osascript -e "$restore_script" "$here_sp" >/dev/null 2>&1 && fallback=yes; fi
    echo "$app switch ($how): to the other $word: script said '$r1', landed there: $fwd; back: script said '$r2', landed in your $word: $back (had to put your $word back separately: $fallback)"
  }
  switch_test "Arc" 'tell application "Arc"
  if (count of windows) is 0 then return ""
  if (mode of front window) is "incognito" then return ""
  return ((id of active space of front window) as text) & (character id 9) & (URL of active tab of front window)
end tell' 'tell application "Arc"
  if (count of windows) is 0 then return ""
  if (mode of front window) is "incognito" then return ""
  set frontId to (id of front window) as text
  set curSpace to (id of active space of front window) as text
  repeat with w in windows
    if ((id of w) as text) is frontId then
      repeat with s in spaces of w
        if ((id of s) as text) is not curSpace then
          repeat with t in tabs of s
            try
              set u to URL of t
              if u starts with "http" then return ((id of s) as text) & (character id 9) & u
            end try
          end repeat
        end if
      end repeat
    end if
  end repeat
  return ""
end tell' 'tell application "Arc" to return (id of active space of front window) as text' 'on run argv
  set want to item 1 of argv
  tell application "Arc"
    repeat with w in windows
      repeat with s in spaces of w
        if ((id of s) as text) is want then
          tell s to focus
          return "ok"
        end if
      end repeat
    end repeat
  end tell
  return "not found"
end run' "space" switchTo
  switch_test "Dia" 'tell application "Dia"
  if (count of windows) is 0 then return ""
  return ((name of active profile of front window) as text) & (character id 9) & (title of active tab of front window)
end tell' 'tell application "Dia"
  if (count of windows) is 0 then return ""
  set frontId to (id of front window) as text
  set curProfile to (name of active profile of front window) as text
  repeat with w in windows
    if ((id of w) as text) is frontId then
      repeat with p in profiles of w
        if ((name of p) as text) is not curProfile then
          repeat with t in tabs of p
            try
              set u to title of t
              if (length of u) >= 6 then return ((name of p) as text) & (character id 9) & u
            end try
          end repeat
        end if
      end repeat
    end if
  end repeat
  return ""
end tell' 'tell application "Dia" to return (name of active profile of front window) as text' 'on run argv
  set want to item 1 of argv
  tell application "Dia"
    repeat with w in windows
      repeat with p in profiles of w
        if ((name of p) as text) is want then
          focus p
          return "ok"
        end if
      end repeat
    end repeat
  end tell
  return "not found"
end run' "profile" switchToTitle
fi

echo "Compare against what you see in each browser. If a line says FAILED with -1743, Automation was refused: Settings, Privacy & Security, Automation."

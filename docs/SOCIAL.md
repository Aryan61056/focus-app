# Friends (social side), design note

Owner, 2026-10-16, in chat: "Yea build it." Built from the brainstorm the same day. The owner's words are marked as theirs;
everything else is Claude's call and can be reversed.

## What it is for (owner)
A small circle of friends who keep each other accountable and motivated. Light and fun: "its not like their job depends
on it". Replies acknowledge each other's ups and downs.

## What friends see
- A weekly scoreboard (owner) ranked on how focused people were, with slips counted too (owner: "just include").
- Per person, per day: focused minutes, slips (confirmed drifts), sessions. Plus the current focus-day streak.
- Never: task or project names, app or site names, window titles, screen text, pictures, reasons, Review answers.
  The existing rule holds: Focus never names a distraction unless you ask, and friends cannot ask.
- Practice sessions are left out: they do not classify, so they would only add unearned minutes.

## Look (owner, 2026-10-16: "a lot more fun than analytical", then "a bit less big", "not for kids", "not too much text")
Fun but grown-up: a low podium for the top three with small gold, silver and bronze rank badges, everyone else on a race
track, emoji avatars (a fixed list of twelve, so nothing typed travels) on a soft color per friend, one Cheer button per
friend, cheers as speech bubbles. Explanations, including "Focus can be wrong", sit behind info buttons (hover or click),
not on the page. Amber still marks only slips; Reduce Motion drops the motion.

## How you respond (owner)
An emoji or a pre-written line, picked from a fixed list. Nothing typed, so no free text ever leaves the Mac and there is
nothing to moderate. At most three per friend per day (Claude's call: enough to cheer, not enough to spam).

## Scoreboard (Claude's calls)
- Resets each calendar week, so one bad week never follows anyone.
- Two boards: **Most focused** (focused time, highest first) and **Fewest slips** (slips per focused hour, lowest
  first; you need an hour of focus that week to be ranked, so not using Focus does not win).
- No points, levels or percentages. Times in monospaced digits, a seven-day bar strip per person.

## Privacy and the earlier decisions
This reverses part of "on-device only, no accounts, no network" (CLAUDE.md) for this one feature, by the owner's choice.
What still holds:
- Off by default. Nothing is sent until you turn sharing on, and turning it off deletes what you shared.
- No accounts of our own and no server of ours: friends connect through iCloud (CloudKit sharing). Apple's sharing sheet
  sends the invite; only people you invite can read your numbers.
- The engine stays offline. All CloudKit code lives in the `FocusSocial` module; `FocusUI` only sees a protocol, so
  `tools/check_privacy.py` still covers the engine and the Friends views.
- The claims ban in CLAUDE.md still applies, and now also needs rewording for good: once sharing is on, "nothing leaves
  this Mac" is false. Copy says exactly what is sent instead.
- PRODUCT.md principle 6 says "no accounts" and the Rewards code says "no points or levels". The scoreboard is the owner's
  call and overrides both for this feature only. Streak copy still never warns about losing a streak.

## How it connects (Claude's calls)
- Your private iCloud database holds one zone, `Friends`, with your card (numbers above) and a zone-wide share.
- Inviting a friend opens Apple's iCloud sharing sheet for that share. A friend who accepts sees your card in their
  shared database. Each person invites the other; a friend who shares with you but cannot see yours shows "Invite back".
  (An automatic two-way link was dropped: it needed participants to write into each other's zones.)
- Cheers you send are records in your own zone, addressed to a friend; they read them from your zone. Nobody writes into
  anyone else's zone, and a reader trusts only records the zone's owner created. Card fields and cheers use CloudKit's
  encrypted values.
- Refresh: when the Friends page opens, after each session is saved, and on request. No background polling.

## Not verified and not decided
- CloudKit needs a paid Apple developer team, an iCloud container and a provisioned, signed build. The local ad-hoc build
  has none, so the app detects the missing entitlement and shows "not available in this build" instead of crashing.
  Nothing here has run against real iCloud. The demo build uses a fake transport with synthetic friends.
- The container name (`iCloud.com.example.focus-app`) is a placeholder: it follows the bundle ID, which waits on the
  owner's Mac distribution decision.
- Windows has no CloudKit; a Windows friends feature needs its own transport and is not designed.

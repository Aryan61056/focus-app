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
  shared database. If they share too, their app leaves a reply in your zone with their own share link, and your app
  accepts it on the next refresh, so one invite links both ways.
- Cheers are small records a friend writes into your zone (participants can write). Your app trusts only records whose
  creator matches: your card must be yours, a cheer's sender is its creator.
- Refresh: when the Friends page opens, after each session is saved, and on request. No background polling.

## Not verified and not decided
- CloudKit needs a paid Apple developer team, an iCloud container and a provisioned, signed build. The local ad-hoc build
  has none, so the app detects the missing entitlement and shows "not available in this build" instead of crashing.
  Nothing here has run against real iCloud. The demo build uses a fake transport with synthetic friends.
- The container name (`iCloud.com.example.focus-app`) is a placeholder: it follows the bundle ID, which waits on the
  owner's Mac distribution decision.
- Windows has no CloudKit; a Windows friends feature needs its own transport and is not designed.

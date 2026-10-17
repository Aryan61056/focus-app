# iCloud sync between the Mac and the iPhone

Owner, 2026-10-16, in chat: "I want you to implement iCloud sync between the mobile and desktop app." Everything below the
request is Claude's design and can be reversed.

## What syncs, and what does not
- **Syncs, Mac to phone:** the numbers behind the phone's Insights tab (`Insights` in `core/link`): today's focused time,
  the week, streak, goal, best stretch, return time, and the last eight sessions with the task names the user typed.
  Practice sessions are left out. Nothing else: no window titles, app or site names, screen text, pictures or reasons.
- **Does not sync:** live session state and control (start, pause, end, break). Those stay on the local link (`COMPANION.md`),
  which is direct, instant and works without the internet. iCloud would add delay and a server round trip for no gain.
- **Why one way:** the phone holds no data of its own to send. Sessions are recorded on the Mac. If the phone ever gets
  its own saved data (for example a phone-only session), that needs a design of its own.

## How it works
- The person's **private** iCloud database holds one zone, `Sync`, with one record, `insights`. The snapshot is stored as a
  CloudKit encrypted value, so iCloud holds it but cannot read it. Only the person's own devices can.
- **Mac** (`mac/Sources/FocusLink/PhoneSync.swift`): off until the switch "Keep Insights in iCloud" in the iPhone window is
  turned on (it asks iCloud first). It writes when saved sessions, the daily goal or the progress switch change, and once at
  launch. An unchanged snapshot is not written again. A failed write is retried once after two minutes, or sooner on the next
  change. Turning the switch off deletes the zone, and with it the snapshot.
- **iPhone** (`companion/Sources/Model/CloudInsights.swift`): reads when the app opens and comes forward, and when iCloud pushes
  (a zone subscription). It keeps a copy on the phone so the tab opens offline. If the Mac turned sync off, the copy is
  deleted. The Insights tab shows the Mac's live numbers while connected, otherwise the newer of the last live numbers and
  iCloud's, with a line "From your Mac, <when>" so a quiet Mac is not mistaken for a quiet day. Numbers from an earlier day
  never claim time for today.
- Shared code: `core/link/Sources/FocusLinkCloud` (`InsightsCloud`, `CloudSnapshot`, `InsightsSyncing`). The local link
  (`FocusLinkNet`) never imports CloudKit.

## Privacy and the earlier decisions
This is the second part of the app that uses iCloud (the first is Friends, `SOCIAL.md`), and it reverses "no cloud, nothing
leaves this Mac" for this feature, by the owner's request. What still holds:
- Off by default on the Mac; off deletes it. The engine modules (`FocusBrain`, `FocusJudge`, `FocusUI`, `FocusSense`) stay offline
  and `tools/check_privacy.py` still passes. CloudKit lives only in `FocusLinkCloud`.
- No accounts of ours and no server of ours. Same Apple ID on both devices; nobody else can read it.
- The words on the switch say what is stored. Do not write "nothing leaves your Mac" anywhere once it is on.
- The claims ban in CLAUDE.md is unchanged.

## Trying it for real (needs the owner's paid Apple developer team)
1. One iCloud container for both apps, e.g. `iCloud.com.yourteam.focus`. Both app IDs need iCloud (CloudKit) and Push
   Notifications; the Mac build uses the same container as Friends.
2. Mac: `tools/build_app.sh` with `FOCUS_SIGN_IDENTITY`, `FOCUS_TEAM_ID`, `FOCUS_PROVISIONING_PROFILE` and
   `FOCUS_CLOUD_CONTAINER=iCloud.com.yourteam.focus` (see the script header and `SOCIAL.md`).
3. iPhone: in `companion/project.yml` set `FOCUS_CLOUD_CONTAINER` to the same container, and point the device entitlements
   at `App/ICloud.entitlements` (or `App/ScreenTimeICloud.entitlements` when Block is also used). A free Personal Team
   cannot have the iCloud capability; leave the container empty and the app builds and runs without iCloud.
4. Both devices on one Apple ID. Turn the switch on in the Mac's iPhone window; open the phone's Insights tab.
5. In the development environment CloudKit makes the `FocusInsights` record type on the first save. Deploy the schema to
   production in the CloudKit Dashboard before shipping.

## Verified and not
- Verified: record mapping and day roll (`InsightsCloudTests`, 5 tests in `core/link`); the Mac's behavior against a stand-in
  iCloud (`PhoneSyncTests`, 7 tests: nothing before it is on, writes on change, no repeat writes, no account, off deletes,
  failed write, no practice sessions); the full Mac suite; `FocusLinkCloud` builds for macOS and the iOS simulator; the iPhone
  sources type-check against the iOS simulator SDK.
- **Not verified:** any call to real iCloud, either device signed with the entitlement, push delivery, the phone tests
  (`CloudInsightsTests` type-check but were not run: `xcodegen` is not installed here, so no Xcode project was generated),
  and how the new screens look.
- Found on the way: the week's day dates carried the time they were worked out, so two identical snapshots never compared
  equal. `PhoneSync` snaps them to midnight. The local link still sends them as they were.

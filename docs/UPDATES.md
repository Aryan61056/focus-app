# Licensing, updates and the installer (2026-11-08)

Owner's request, 2026-11-08: add licensing to the app, a well-animated Liquid Glass setup flow, a customized drag-to-Applications
window, and updates that download without fetching the DMG again. The website's Download button is left alone for now.

## License
- The server rules (key lookup, two Macs per key, revoke, expiry) are on hushd.store (`focus-site`, `/api/license/{activate,validate,deactivate}`).
  The app keeps what it said: `FocusUI/Licensing/LicenseCenter.swift` (state, 14-day offline grace, daily re-check; tests in `LicenseTests`).
- The only network code is `focus-app/LicenseClient.swift`: one JSON POST with the key, a SHA-256 of the Mac's hardware UUID (never the raw
  UUID) and the app version. Never a task, window or session. `tools/check_privacy.py` still passes: no networking in the engine modules.
- The key lives in `~/Library/Application Support/Focus/license.json` (mode 0600), not the Keychain: ad-hoc builds change identity on update
  and the Keychain would ask for the login password again.
- Required for beta and release builds; a dev build opens without one unless `FOCUS_REQUIRE_LICENSE=1`. Never interrupts a running session.
  Settings > License shows the key's tail, Macs used and days left; "Deactivate this Mac" frees the place.
- Test against a local server: `FOCUS_LICENSE_URL=http://127.0.0.1:8788/`.
- Privacy copy: the welcome says "One key, no account" and "Only your key and a code for this Mac go to hushd.store. Never your work."
  The website's privacy FAQ still needs a matching line (not changed here).

## Updates (Sparkle 2.10.1)
- `focus-app/SparkleUpdater.swift` is Sparkle's user driver: no Sparkle windows. Once a day it checks the feed, downloads quietly, verifies
  the EdDSA signature, and offers "Restart to update" on Today, in the menu bar and in Settings > General, never during a session.
- Only builds made for handing out (`FOCUS_DISTRIBUTION=1`, so `tools/build_dmg.sh` and `tools/release.sh`) carry `SUFeedURL` and
  `SUPublicEDKey`. A dev build keeps updating from its own build folder (`Updater.swift`).
- Hushd's own key: `generate_keys --account hushd` (private half in the login Keychain; the owner must back it up themselves with
  `generate_keys --account hushd -x <file>`). The public half is `tools/update/public-key.txt`. Lose the private key and no installed copy
  will accept an update again.
- Feed address: `FOCUS_FEED_URL`, default `https://hushd.store/updates/appcast.xml` **(a placeholder, the owner's to choose: hushd.store,
  GitHub Releases, anywhere https)**. `tools/release.sh <version>` builds, signs and prints what to upload; it publishes nothing.
- Build numbers: releases use the UTC time (YYYYMMDDHHMM); beta builds use `beta/BUILD`. Sparkle compares build numbers only.
- Verified 2026-11-08 on this Mac with a local feed: build 100 found 101, downloaded and verified it, "Restart to update" replaced the app in
  place, the signature verified and the designated requirement (`identifier "<bundle id>"`, what macOS keys the Accessibility grant on) was
  unchanged. A DMG changed after signing was downloaded and rejected: nothing installed. Not exercised: a real Accessibility grant
  surviving an update (inferred from the unchanged requirement), a real https feed.
- The bundle id is still the placeholder `com.example.focus-app.dev`. Settings, the Accessibility grant and updates all follow the bundle id,
  so decide it before the first release that carries the updater.
- Gotcha: after "Restart to update", macOS relaunches the app without the environment it was started with, so a test copy launched with
  `FOCUS_TEST_STORE` comes back on the real data folder. Don't leave an update test running.

## Installer window
`tools/build_dmg.sh` lays out the image through Finder (AppleScript; the first run needs "allow Terminal to control Finder") with the
background from `tools/dmg-background.swift`: Hushd's green, glass tiles, a dotted arrow. If Finder can't be driven, it builds a plain image
and says so (`FOCUS_DMG_PLAIN=1` skips on purpose). Still ad hoc signed and not notarized until the owner has a Developer ID.

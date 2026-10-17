# Focus for iPhone (companion)

Shows the Mac app's session on your phone, lets you start, pause and end it from there, and keeps the task on your lock
screen. It talks to the Mac directly over your Wi-Fi (`../core/link`): no account and no server.

```bash
brew install xcodegen          # once
cd companion && xcodegen generate
open FocusCompanion.xcodeproj  # run on an iPhone simulator, or set your Team under Signing to run on a phone
(cd ../core/link && swift test)                      # link tests, including real loopback sockets
xcodebuild -project FocusCompanion.xcodeproj -scheme FocusCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test CODE_SIGNING_ALLOWED=NO
```

**App icon:** PNGs are gitignored in this repo, so draw them once after cloning (the Focus ring on deep green, with dark and tinted variants):
`SDKROOT= swiftc -o /tmp/make_ios_icon tools/make_ios_icon.swift && /tmp/make_ios_icon companion/App/Assets.xcassets/AppIcon.appiconset`

**Block tab:** pick the apps that distract you and Focus covers them during a session (Screen Time). Needs a paid team and a real iPhone; see `../docs/COMPANION.md`.

No Mac handy? **Mac tab > Demo mode** runs a pretend Mac. Launch flags for screenshots: `-demo`, `-demo-session`, `-tab insights|mac`.

Layout: `Sources/Design` (palette, motion, ring, halftone art, banner, reveal), `Sources/Model` (state, clock, Keychain, demo Mac), `Sources/Views`,
`LiveActivity/` (lock screen and Dynamic Island), `Monitor/` and `Shield/` (Screen Time extensions), `Shared/` (attributes used by both).

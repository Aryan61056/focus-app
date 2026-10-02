# focus-app (working name)

A Mac focus app: you say what you are working on, an on-device AI compares the window in front with it, and nudges you gently when you drift. Everything runs on this Mac. Windows comes later.

- **What changed and what is unverified:** [docs/STATUS.md](docs/STATUS.md) (read this first)
- **Plan:** [docs/PLAN.md](docs/PLAN.md). **Working rules and decisions:** [CLAUDE.md](CLAUDE.md). **Design context:** [PRODUCT.md](PRODUCT.md)

## Run it
```bash
./tools/build_app.sh        # builds mac/.build/Focus.app (local, ad-hoc signed, dev only)
open mac/.build/Focus.app
```
First time: Settings, "What Focus looks at", press "Check in 5 seconds" and switch to another window to see what Focus can read. Allow Accessibility (window titles) in System Settings, Privacy & Security; Screen Recording only if you turn on screen reading. If you rebuild and permissions seem lost, remove Focus from the list and add it again once.

Shortcut: Control-Option-F starts a session (or pauses and resumes one).

## Check it
```bash
(cd mac && swift test)                 # Swift tests (brain, judge, app logic)
python3 -m unittest discover -s eval/tests
python3 tools/check_privacy.py
./tools/check_notch_hover.sh           # moves your pointer onto the notch panel; needs the bundle built
FOCUS_E2E=1 swift test --filter RealModelE2ETests   # from mac/: real Apple model, scripted windows
```

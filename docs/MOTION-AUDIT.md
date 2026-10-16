# Motion audit (2026-10-15)

A sweep of the Mac app for moments that should move, gated the way `find-animation-opportunities` asks: frequency, purpose, speed budget, and whether motion helps or hinders. Most candidates were rejected. The app already had a solid base: notch springs measured from Droppy, a sliding sidebar selection, a page entrance done with keyframes, `LiveRing` shape morphs, and numeric clocks. This pass fills the gaps and brings the website's halftone motion into the app.

## Built

| # | Where | Before | Purpose | Frequency | Motion |
|---|---|---|---|---|---|
| 1 | `HeroBanner.swift` `HeroArtwork` | Static halftone | Delight; state indication | Rare (ripple), occasional (wave) | Website's halftone behaviour, natively. Dots ripple out from the notch pill on the first show after launch (wave 1.1 s; each dot grows over 0.7 s, cubic ease-out); stars fade in after. The pointer swells nearby dots (×1.75 at the centre, σ 70 pt), trailing it through a frame-rate-independent exponential spring. A soft wave runs out from the pill whenever the ring changes shape (1.5 s, fading). Drawn in 6 brightness batches, so a frame is a few fills. The frame clock runs only while something moves: **0.1% CPU at rest**, measured. Reduce Motion draws it still. |
| 2 | `HeroBanner.swift` pills | Flat black capsule | Craft (material) | Always visible | A 1 pt top-lit edge gradient and a tight contact shadow, so the pill sits on the art. The task name morphs (`.interpolate`) when a session starts or ends. |
| 3 | `TodayLive.swift` verdict | Whole card cross-faded 0.2 s on every reading | State indication | Tens per day | A new call morphs the ring (`LiveRing`), label (`.interpolate`) and tint with `Motion.notchSettle`. A same-call refresh only cross-fades the words. |
| 4 | `RootView.swift` entrance | Session start/end on Today swapped most of the page in place | Preventing a jarring change | A few per day | Starting or ending a session on Today replays the existing page entrance (same keyframes, no identity change, so no scroll jump). |
| 5 | `TodayView.swift` notice row | Appeared and vanished instantly | Preventing a jarring change | Occasional | `.rise`: 6 pt rise and fade in 0.26 s, out in 0.14 s. |
| 6 | `TodayIdle.swift` session finished | Static title | Delight (completion) | A few per day | SF Symbols draw-on of a check beside "Session finished" (macOS 26+; earlier systems show it still). |
| 7 | `TodayIdle.swift` first-run steps | Three cards at once | Delight (first run) | Once | Arrive in reading order, 60 ms apart, 8 pt rise, ease-out 0.42 s. |
| 8 | `ReviewView.swift` | Answered moment vanished | Spatial consistency | Occasional | The row fades and settles out (scale 0.98 from top); the rows below close up with `Motion.notchSettle`. |

## Second pass: the halftone everywhere it earns a place (2026-10-15)

`Halftone.swift` turns the hero's dot field into one native component with patterns: `hills` (hero), `nudge`, `rings`, `bloom`. Each ripples out from its origin when it arrives, can swell under the pointer, and redraws only while moving.

| # | Where | Before | Purpose | Frequency | Motion |
|---|---|---|---|---|---|
| 9 | `NotchView.swift` nudge | 100 pt-tall glass card, mostly empty, muddy grey over busy windows, ring and time stranded in the ears | State indication; spatial consistency | A few per day | Redesigned: 72 pt solid black, one row (ring in a lit well, the question plus "M:SS into this session", the green pill). The band empties as it does for the open card. Green halftone light rises from the foot and ripples out of the hardware notch as it opens (0.55 s across, dots grow 0.7 s). |
| 10 | `Components.swift` `EmptyState` | Flat card | Delight (empty state, rare) | Rare | Printed accent rings spread from the symbol as the page arrives, then rest and swell under the pointer. |
| 11 | `TodayIdle.swift` session finished | Flat card | Delight (completion) | A few per day | Accent light blooms in from the card's empty top-right corner, away from the text, and settles faint. |
| 12 | `CuePanels.swift` reminder banner | Glass primary button drawn grey (glass in a never-key panel renders inactive) | Craft | A few per day | Solid green pill, the same `PillStyle` as the notch. |

Rejected in this pass: halftone behind every page header (navigation is tens per day, and functional pages should not shimmer); the ripple on the open notch card (you open it by clicking, often); dots behind reading/verdict cards (information you read).

## Rejected

- **Parking-lot panel open** (`ParkingLot.swift`). Keyboard-initiated (a global hotkey). It stays instant, like Raycast.
- **Staggered card entrances on every page.** Sidebar navigation is tens per day, and the page already has its 0.26 s entrance. More would feel slow.
- **Animated charts** (`DayCharts`, `InsightsView`). Data you read; drawing it in would only delay it.
- **Scroll-linked reveal** (the website's fade-up as sections scroll in). On a working app's pages it moves content you are trying to read.
- **An always-drifting banner.** Constant ambient motion costs CPU all day and is a known vestibular trigger. The banner moves only on arrival, under the pointer, or when the state changes.

## Found while measuring (not changed)

During a demo session the app uses about 23% CPU on other pages and about 45% on Today. With no session it uses 0.1%. Disabling the ring glow did not change this. The likely cause is five clocks (sidebar card, toolbar pill, notch, hero pill, live header) animating their digits for 0.3 s every second, which keeps the window redrawing about a third of the time. Worth a look in Instruments (SwiftUI template) before shipping. One cheaper option: animate the digits only on the clock the user is looking at. The ring glow was redrawn as a gradient rather than a per-frame blur anyway (the profile showed `vSepConvolve`), which is the same look for less work.

## Not verified

- Pointer swell and the session-start wave on a real display. The swell needs a real pointer; I don't move the user's pointer.
- Frame pacing on a ProMotion display.
- Reduce Motion, checked live.
- The macOS 26 draw-on effect on an older system.

Captures: launch ripple, settle, and break-triggered wave, from window-only captures of the demo process (scratchpad, not in Git).

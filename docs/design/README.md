# Visual direction exploration (spike S10, first pass)

Three boards for the Quiet style, built as static HTML so they can be compared in light and dark. They are mockups, not product code.

| File | Direction |
|---|---|
| `index.html` | Side-by-side comparison and recommendation |
| `a-native.html` | A: system accent, hairline ring, standard controls |
| `b-lichen.html` | B: one quiet green, bold progress ring, softer shapes |
| `c-graphite.html` | C: no accent, inversion as emphasis, squircle ring, mono numerals |

Each board shows the ring in all five states, the pill, the color drain, the nudge card, the Strict gate, both start levels, the quick panel (collapsed and with More), the session summary, and a Windows tab (tray flyout and nudge). Toggles for theme, reduced transparency and reduced motion are at the top. `board.css` and `board.js` are board scaffolding; the direction files hold the tokens.

## What is the same in all three

- Behavior and copy from PLAN 4.12. No em dashes, no exclamation marks, the distraction is never named.
- The calm rules: one primary action per surface, at most three visible choices, the rest behind More.
- State is carried by shape first (closed, dashed, gapped, bars, dot), color never alone. The timeline reads in grayscale.
- System fonts. B uses the rounded system face for numerals on Mac, C uses the system mono for times and keys.
- Glass only on floating surfaces; a Reduce transparency switch replaces it with solid fills.

## Checks done

Contrast, computed from the OKLCH tokens (glass composited over a mid-tone wall): primary text 13.6 to 17.1:1, secondary text 6.7 to 8.8:1, text on filled buttons 4.8 to 18.8:1, ring against glass 4.3 to 17.1:1 (3:1 needed for graphics). One failure found and fixed: white on A's dark-theme blue was 3.4:1, so the fill token is now separate from the foreground accent (4.8:1).

Not done: Increase Contrast and Windows high-contrast variants, real device rendering, text scaling to 300%, VoiceOver and Narrator, the cat companion (deliberately out of scope).

## Viewing

Open any file in a normal browser. In the Claude desktop browser pane use the `design-boards` entry in `.claude/launch.json`, because the pane renders bare `file://` pages as static snapshots without their stylesheets. Add `#light` or `#dark` to a URL to force a theme.

## Next once a direction is chosen

Formalize the tokens (color, type scale, spacing, radius, elevation, motion) as one file generated into SwiftUI and XAML resources, run `/impeccable document` to seed DESIGN.md, and build the three core components natively on both OSs (PLAN spike S10).

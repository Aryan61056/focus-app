# UI overhaul prompt for Claude Code

Paste everything below the line into Claude Code, run from the repo root.

---

Overhaul the whole Focus Mac app UI (`mac/Sources/FocusUI`, `FocusSense` views, `focus-app`): every screen, state and window. Work autonomously and do not stop to ask permission. Ask me only for the things CLAUDE.md lists as mine.

## 0. Ground rules (read first, do not reopen)
- Read `CLAUDE.md`, `PRODUCT.md` and `docs/design/b-lichen.*`. Direction is B "Lichen", product register, calm, never overwhelming, sentence-case copy with no exclamation marks, never name the distraction in pushed nudges.
- The notch is aesthetic: ring, task, time, and one "Back to task" control on a nudge. No other controls there.
- Keep every setting and function. Regroup, never delete. Do not touch the brain, judge or privacy behavior.
- Any visual choice that contradicts PRODUCT.md or an owner decision in CLAUDE.md: leave it and list it for me at the end.

## 1. Skills first
1. Run `node .claude/skills/impeccable/scripts/context.mjs` once and follow it. Use the `impeccable` skill for all UI work (`critique`, `audit`, `layout`, `typeset`, `colorize`, `polish`, `clarify`, `harden`, `animate`).
2. Use `find-skills` (`npx skills find swiftui`, `macos design`, `accessibility`, `animation`, `design system`). Only consider skills with 1K+ installs or from official sources (vercel-labs, anthropics, microsoft). Install only what clearly helps, with `-g -y`, and tell me what you installed and why.
3. If the context script says an Impeccable update exists, update it once (`npx impeccable skills update`) and continue.

## 2. Discover what looks bad (before changing anything)
Render every screen and write findings to `scratchpad/overhaul/FINDINGS.md`, ranked P0 to P3, each with screen, problem, evidence (render path) and fix.
- Tooling, no screen capture and no permission needed: `focus-snapshot`, and the demo self-render
  `open -n --env FOCUS_DEMO=1 --env FOCUS_DEMO_ACTIONS=section:<x>,page:<y> --env FOCUS_SELFSHOT=<dir> mac/.build/Focus.app`.
- Cover: Today (idle, live, paused, held, saving failed), start sheet and the similar-project question, Projects, History, Insights, Review, every Settings page, sidebar, menu bar popover, notch (closed, hover, open, nudge, escalation), shield, check-in, heads-up banner, empty and error states.
- Render each in light and dark, at the minimum and a large window size, and at larger text sizes.
- Look for: inconsistent spacing and radii, more than one type scale, weak hierarchy, clipped or truncated text, tiny hit targets (under 24 pt), low contrast, mismatched icon weights, untokenized colors, dense settings pages, empty states that say nothing, jargon, copy that names a distraction, motion without a reduced-motion path, anything that reads as generic AI-made SaaS.
- Also run `python3 tools/check_contrast.py`, `node .claude/skills/impeccable/scripts/detect.mjs` where it applies, and a grep for hard-coded colors, sizes and fonts outside the token files.

## 3. Build one design system, then apply it everywhere
- Consolidate color, type, spacing, radius, elevation, motion and icon tokens in one place (extend what exists, do not fork it). Light and dark both pass `tools/check_contrast.py`.
- Rebuild shared components once (row, section, card, chip, button, toggle row, empty state, notice, sheet) and replace one-off copies.
- Then work screen by screen in the order of the P0 to P3 list. For each screen: fix, rebuild, re-render, compare to the before shot, and keep going until it holds up to a critical look. Do not move on with known P0 or P1 items.
- Hierarchy rule: the AI's decision is the hero on Today and Review. Show its work, never overstate it.
- Motion: purposeful, ease-out, a reduced-motion path for each, nothing that animates forever on screen (CPU budget: idle session stays under about 2 percent of a core).

## 4. Verify, document, commit
- `cd mac && swift test`, `python3 tools/check_privacy.py`, `python3 tools/check_contrast.py`, and the notch hover check must pass. Add tests for any behavior you change, and for hit-target and contrast rules where practical.
- Keep before and after renders in `scratchpad/overhaul/` (never commit screenshots).
- Update `docs/STATUS.md` with what changed, what was verified, and what could not be (glass effects and real pointer behavior do not render offscreen; say so).
- Commit in small steps, messages say why. Do not push. Rebuild with `./tools/build_app.sh --install` at the end.

## 5. Final report
What you found (counts by priority), what you changed, what you installed, what is unverified, and the short list of decisions that are mine.

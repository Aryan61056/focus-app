# Product

## Register

product

## Users

Someone doing focused work on a Mac or a Windows PC who wants help noticing drift without being policed. Their screen often holds material that can't leave the machine, so a tool that never phones home matters to them.

The audience is still the owner's decision (knowledge workers and graduate students are the plan's recommendation, PLAN.md section 12). Don't narrow design choices to one audience until the owner picks.

Context of use: mid-task, glancing at the app for about three seconds, often on a shared or visible screen. The job to be done is "tell the app what I'm working on, then get back on track when I drift."

## Product Purpose

A native focus app. The user states a task, a local AI compares the screen to it, and the app nudges gently and escalates gently if they keep drifting. Projects keep context between sessions. Nothing leaves the device: no cloud inference, no accounts, no telemetry.

Success: a returning user starts in one keypress (under 10 seconds), a first session starts in under 90 seconds, false nudges are rare enough that people trust the ones they get, and nobody says it felt like too much.

## Brand Personality

Calm, precise, discreet.

Speaks like a calm colleague: brief, second person, sentence case, no exclamation marks, never scolding. It never names the distraction. Quiet by default (no sound, no character); loudness follows state, so the better the user is doing, the less they see. Looks and behaves like part of the OS (Liquid Glass on Mac, Fluent on Windows), with the same product underneath.

## Anti-references

- Fomi-style cartoon personas and the tomato. The default style has no mascot. The cat is an optional later pack.
- Anything with a surveillance or stalkerware feel: stealth behavior, employer-dashboard looks, alarming "monitoring" imagery. The app is never invisible while it watches.
- The generic SaaS dashboard: hero-metric tiles, gradient accents, identical card grids, chrome that outweighs content.

## Design Principles

1. **A false alarm costs more than a miss.** Every threshold and every surface leans conservative. Ambiguous means do nothing.
2. **Never overwhelm.** One primary action per surface, at most three visible choices, two sentences of text, a default for everything, questions asked late and one at a time (PLAN.md 4.8).
3. **Discreet by default.** Safe to have on screen next to a colleague: no sound, no character, no named distractions.
4. **Native dialect, shared behavior.** Same loop on both OSs; each platform looks and feels like itself.
5. **Trust through transparency.** Say what changed after any correction, let the user see and delete what the app learned, and keep a visible sign that it's watching.
6. **No dark patterns.** No streak-loss panic, no guilt copy, no data hostage, no accounts.

## Accessibility & Inclusion

Baseline from PLAN.md D13 and 4.11, not yet reviewed against a stated WCAG target (owner to confirm; WCAG 2.2 AA is the working assumption):

- VoiceOver and Narrator labels and announcements; full keyboard operation; visible focus.
- State is never shown by color alone (the ring uses shape: solid, dashed, gapped, paused).
- Respect Reduce Motion, Reduce Transparency, Increase Contrast and Windows high-contrast themes.
- Effects never flash. The color drain ramps over 20 seconds or more.
- A non-visual channel (optional sound or screen-reader announcement) so the app works without seeing the overlay.
- Text scaling from 100% to 300%; plain-language copy with no jargon.

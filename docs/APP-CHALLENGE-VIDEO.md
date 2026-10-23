# Congressional App Challenge: demo video script

Target length **2:45**, so the video stays under the 3-minute limit with some room to spare. The narration below is about 350 words, roughly 2:30 of talking plus pauses for 2:45 at a calm speaking pace. Check the official 2026 rules for the exact length and deadline (reported as October 26, 2026, 12:00 p.m. ET).

Written in first person for whoever presents. Change any line so it sounds like you.

## Before you record

- **Use a clean store** so your own projects and history stay out of the video:
  `open -n --env FOCUS_TEST_STORE="$TMPDIR/focus-demo" mac/.build/Focus.app`
  Do one or two short practice sessions first, so History and Insights have something to show.
- **Record with** ⌘⇧5 (Record Entire Screen). Turn on Do Not Disturb. Hide the Dock and desktop icons, and close anything personal.
- **Set up the drift** before you press record: a work window (for example, a doc called "History essay") and a distraction in another tab (a video site). You will switch to it on camera.
- **Keep the drift going long enough.** A nudge needs several readings that agree, so it doesn't appear the moment you switch. Practice once to learn how long it takes, then cut the wait in editing.
- **Talk calmly.** The app's whole personality is calm, so the narration should match it.

## Script

### 1. The problem (0:00–0:20)

**On screen:** You at the desk, or a quick screen capture: a doc open, then a jump to a video tab, then another tab.

**Say:**
> "You sit down to write an essay. Twenty minutes later you're three videos deep, and you don't remember switching. Most focus apps just block websites, but the same site can be work one minute and a distraction the next. I wanted an app that actually understands what you're working on."

### 2. Meet Focus (0:20–0:40)

**On screen:** The Focus window. Type the task "History essay" and start a session with the slider.

**Say:**
> "This is Focus, a Mac app. You tell it what you're working on in a few words and press start. That's the whole setup. No account, no sign-in."

### 3. Watching the AI work (0:40–1:15)

**On screen:** The Today screen. Point at the "Focus reading" bar, its three checks, and the verdict "On task". Then point at the right panel, "What Focus did".

**Say:**
> "While you work, Focus reads the window in front of you (the app, the title and the address) and asks Apple's on-device AI model one question: does this match your task? Right here it shows what it's reading, how it decided, and its call: on task.
> The AI runs on the Mac itself. Your screen isn't sent to a cloud AI, and Focus doesn't keep window titles after the session."

### 4. The drift and the nudge (1:15–1:50)

**On screen:** Switch to the video tab and stay there (cut the wait). The ring changes shape. The notch opens with "Back to History essay?" Click **Back to task** and land in the essay document.

**Say:**
> "Now I drift. Focus doesn't jump on me right away. It waits until several readings agree. Then it nudges gently: 'Back to History essay?' Notice it never names what I was looking at, so it's safe to have on screen around other people. One click on Back to task takes me to the exact document I was writing, not just the app."

### 5. Designed to be trusted (1:50–2:20)

**On screen:** The line "Focus can be wrong. When it isn't sure, it does nothing." Then the Review page with a flagged moment and its reason, and Insights.

**Say:**
> "The hardest part was deciding when *not* to nudge. A wrong nudge is worse than a missed one, because it teaches you to ignore the app. So when Focus isn't sure, it does nothing. I built a set of 100 test scenarios to measure how often the AI gets it wrong, and I tuned the app to be careful. Afterward, Review shows each moment it flagged and why, and you can tell it whether it was right."

### 6. How it's built and what's next (2:20–2:45)

**On screen:** A few seconds of the code (the Swift package in Xcode, or the test run passing), then back to the app with the ring.

**Say:**
> "Focus is written in Swift and SwiftUI. The logic that decides when to nudge is a small state machine with its own tests. Next, I want to test it with more students, make it more accurate, and bring it to Windows. Focus doesn't block you. It helps you notice and come back. Thanks for watching."

## Notes for honesty

- **Say only what the app really does on your Mac.** If a step doesn't work while recording (for example, screen reading needs Screen Recording permission), leave it out rather than fake it.
- **Don't say** "nothing ever leaves your device", "can't reach the internet" or "0 bytes sent". Those claims wait on privacy tests that haven't passed yet (`docs/SECURITY-REVIEW.md`). "Runs on your Mac with Apple's on-device model, no account, no cloud AI" is accurate.
- **Don't quote an accuracy percentage as a promise.** The measured numbers come from a small test set (`docs/S1-accuracy.md`). "I measured it and tuned it to be careful" is accurate.
- **Check whether the rules ask you to disclose AI help.** Much of this code was written with an AI coding assistant. If they do, say so in the written answers, and the video can mention it too (for example in section 6: "I used an AI coding assistant to help build it, and I...").

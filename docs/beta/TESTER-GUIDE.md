# Testing Hushd

Thank you for trying Hushd before anyone else. This page is everything you need; it takes two minutes to read.

## What Hushd is

You tell Hushd what you are working on. While a session runs, Apple's on-device model compares the window in front with your task, and when you drift for a while Hushd nudges you back. The judging runs on your Mac. Hushd can be wrong, and when it is not sure it does nothing.

You need a Mac with Apple silicon and Apple Intelligence turned on (System Settings, Apple Intelligence & Siri). The beta is built and tested on macOS 27.

## Install

1. Download the `.dmg` from the newest release: <https://github.com/Aryan61056/focus-app/releases>. Beta builds are marked *Pre-release*. If someone handed you the file directly, that works the same.
2. Open the `.dmg` and drag Hushd onto Applications.
3. Open Hushd from Applications. macOS says it cannot check the app, because this beta has no Apple developer signature yet: choose **Done**, then open **System Settings, Privacy & Security**, and choose **Open Anyway** next to Hushd. You do this once per build.
4. Hushd asks for Accessibility the first time it needs to see which window you are in. Screen Recording is asked for only if you turn on screen reading.

If you want to check the download, the release lists its SHA-256 checksum: `shasum -a 256 Focus-*.dmg` in Terminal prints the same value.

A newer beta installs the same way, over the old one. Your sessions and settings stay.

## The Beta page

Click your name at the bottom left of the Hushd window, then **Beta page**. It shows:

- **Days left** in this build, as a ring.
- **Ready to test**: three checks for this Mac (Apple's model, window titles, the beta log). Anything that needs you has a **Fix** button beside it.
- **Try these**: seven things worth trying. They tick themselves from what you do; none needs typing.

## What we ask

Use Hushd for real work, on at least three days, over about a week. Once a week, between sessions, Today asks how Hushd is working for you: one click on five dots. Skip is fine.

## Sending feedback

Click your name at the bottom left, then **Send feedback**. Or Help, Send Feedback (Option-Command-F).

1. Pick what it is: something broke, a wrong call, an idea, or anything else.
2. Write what happened in your own words. For a wrong call, describe the *kind* of window ("a PDF of my lecture notes") rather than what was in it.
3. Leave the checkboxes on unless you would rather not share that part. **See the whole file** shows exactly what will be saved.
4. Press **Post on GitHub**. Hushd saves the report and shows it as a file; press **Open the form**, drag the file into the form, read it, and submit. GitHub issues are public, so anyone can read what you post.

No GitHub account? Press **Save file** instead and send the file to whoever gave you the build. If your build has an email address in it, **Email report** opens a draft in your mail app with the file attached, and you press Send.

If Hushd closed unexpectedly, Today offers to write a report the next time you open it. That one helps most.

Before reporting, glance at **What's new** in your profile: it lists the problems already known in your build, so you can skip those.

## What a report holds, and what it never holds

It holds what you write, the build, your Mac's model and macOS version, whether permissions are on, your settings switches, counts (sessions, minutes, nudges), a log of when things happened (kinds and times), Hushd's last few calls (on, unsure or off, and whether the model, a rule or shared words decided), and where in Hushd's code a crash happened if there was one.

It never holds your task or project names, window titles, web addresses, anything read from your screen, or pictures. Hushd never sends a report by itself: the report is a file you can open and read before you post or send it.

The beta log stays on your Mac. The Beta page lets you turn it off or clear it.

## When the beta ends

Each build has an end date. After it, Hushd keeps working, Today says the build is out of date, and your profile offers **Get the newest build**, which opens the releases page in your browser. Hushd itself never downloads or installs anything.

## Leaving the beta

Quit Hushd and drag it from Applications to the Trash. To remove your data too, first use Settings, Privacy, **Delete everything**, or delete the folder `~/Library/Application Support/Focus`.

## Things that are not finished

Hushd can be wrong. When it is not sure, it does nothing. A wrong call is exactly the kind of report we want.

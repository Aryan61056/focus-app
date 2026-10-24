import SwiftUI
import FocusBrain
import FocusJudge
import AppKit

/// Settings split into pages, each its own row in the sidebar, the way System Settings and Droppy lay them out.
public enum SettingsPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general = "General", nudges = "Nudges", cues = "Cues", notch = "Notch", rhythm = "Rhythm and goals", reading = "What Hushd reads", privacy = "Privacy", beta = "Beta"
    public var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape"; case .nudges: return "hand.wave"; case .cues: return "bell"
        case .notch: return "rectangle.topthird.inset"; case .rhythm: return "metronome"; case .reading: return "eye"; case .privacy: return "hand.raised"; case .beta: return "testtube.2"
        }
    }
}

struct SettingsView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    var page: SettingsPage = .nudges
    @State private var showMoreNudges = false
    @State private var confirmDelete = false
    var probeBusy: Bool { if case .waiting = c.probe { return true }; return false }
    var probeText: String {
        switch c.probe {
        case .idle: return "Switch to another window after pressing the button. Hushd tells you what it can see there. Nothing is kept."
        case .waiting(let n): return "Switch to the window you want to test. Reading in \(n)."
        case .nothing: return "Hushd itself was in front, so nothing was read. Try again and switch to another app before the countdown ends."
        case .saw(let app, let title, let trusted):
            if !trusted { return "Saw the app \u{201C}\(app)\u{201D} only. Allow Accessibility to see window titles." }
            return title.isEmpty ? "Saw the app \u{201C}\(app)\u{201D}, but that window gave no title." : "Saw \u{201C}\(app)\u{201D}, window \u{201C}\(title)\u{201D}."
        }
    }
    var body: some View {
        Form {
                if page == .general {
                    Section("Getting started") {
                        Button("See how it works") { c.showExample() }.disabled(c.isActive)
                            .help("A guided example with made-up windows. No permissions needed.")
                    }
                }
                if page == .nudges {
                    // The page opens on the thing it sets: a nudge as the notch shows it, in the tone you picked. A plain black plate, no art.
                    Section {
                        HStack { Spacer(); NudgePreviewPill(text: c.prefs.nudgeTone.example); Spacer() }
                            .padding(.vertical, Space.l)
                            .background(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).fill(Color(white: 0.16)))
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                            .accessibilityLabel("Preview of a nudge in the notch")
                    }
                }
                group("Feel", .notch) {
                    row("Tap the trackpad", "One soft tap when you press the notch, when it opens, when you change its page and when a file lands in the tray. Nothing while you only move the pointer over it. The Mac gives apps three tap shapes, so each moment gets its own. It only works on a Force Touch trackpad and only while a finger rests on it. Separate from the buzz that goes with a nudge.") {
                        HStack(spacing: Space.s) {
                            Button("Try") { NotchHaptics.play(.opened) }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            toggle(\.notchHaptics)
                        }
                    }
                }
                group("Nudges", .nudges) {
                    HStack(spacing: Space.s) {
                        opt(.gentle, "Gentle", "One quiet note after about three minutes.")
                        opt(.standard, "Standard", "A card after about a minute, again every five.")
                        opt(.strict, "Strict", "A pause screen after 45 seconds.")
                    }.padding(.vertical, Space.xxs)
                    row("How nudges sound", "For example \u{201C}\(c.prefs.nudgeTone.example)\u{201D}. A nudge never names what you were looking at.") {
                        segmented(NudgeTone.allCases, selection: Binding(get: { c.prefs.nudgeTone }, set: { c.prefs.nudgeTone = $0 }), title: \.title)
                    }
                    row("Play a soft tone with a nudge", "One short system sound when a nudge appears. Off unless you turn it on, and it never plays in practice mode.") {
                        Toggle("", isOn: Binding(get: { c.prefs.nudgeSound }, set: { c.prefs.nudgeSound = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                }
                group("How Hushd decides", .nudges) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            HStack(spacing: Space.xs) { Text("How often Hushd checks"); InfoButton(text: "\(c.prefs.checkRate.detail) Each check asks the on-device model, so checking more often uses more battery. Applies from the next session.") }
                            Spacer()
                            segmented(CheckRate.allCases, selection: Binding(get: { c.prefs.checkRate }, set: { c.prefs.checkRate = $0 }), title: \.title)
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            HStack(spacing: Space.xs) { Text("How sure Hushd must be"); InfoButton(text: sensitivityHelp) }
                            Spacer()
                            segmented(Sensitivity.allCases, selection: Binding(get: { c.prefs.sensitivity }, set: { c.prefs.sensitivity = $0 }), title: \.title)
                        }
                    }

                    row("Ease in, then push harder when behind", "Hushd is easy on you before noon and once you reach your daily goal, and it warns sooner and climbs faster when you are behind the goal's pace for the time of day (a 9 to 6 working day). Today always says which it is. Needs the daily goal below to be on.") {
                        toggle(\.paceMatters)
                    }
                }
                group("If you stay away", .nudges) {
                    row("If you stay away after a warning", "Gentle stops at the warning. Standard and Strict keep going: after about 40 seconds (20 on Strict) Hushd asks whether you are on task and reads the window again, then covers every screen with a pause screen, then hides the app you drifted into. Dismissing a card does not stop it; getting back to the task does.") {
                        Toggle("", isOn: Binding(get: { c.prefs.escalate }, set: { c.prefs.escalate = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    row("Fade the whole screen to gray", "While you are off task, every display loses its color a little at a time, deeper the longer you stay away, and it fades back when you return. Preview shows a 10 second fade. Nothing is captured.") {
                        HStack(spacing: Space.s) {
                            Button("Preview") { c.previewVeil() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            Toggle("", isOn: Binding(get: { c.prefs.screenGrayscale }, set: { c.prefs.screenGrayscale = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                    }
                    row("Fog the screen", "While you are off task the screen blurs a little more the longer you stay, until it can be made out but not read, and clears when you return. It goes where the gray goes (every display, or only the window you drifted into). Harsh, so it is off until you want it. Preview shows a 10 second fog.") {
                        HStack(spacing: Space.s) {
                            Button("Preview") { c.previewFog() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            Toggle("", isOn: Binding(get: { c.prefs.screenFog }, set: { c.prefs.screenFog = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                    }
                    row("Gray only the window you drifted into", "The gray covers just the window you are off task in, so the task window beside it stays in color and looks like the way back. If Hushd cannot tell which window that is, nothing is grayed. Preview always grays the whole screen.") {
                        Toggle("", isOn: Binding(get: { c.prefs.grayWindowOnly }, set: { c.prefs.grayWindowOnly = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    row("Ease the sound down", "While Hushd is nudging you on a video site, the Mac's volume eases down to about a third of where you had it and comes back when you return, the session ends or you pause. If you change the volume yourself it lets go. It never mutes, and it does nothing in a call or in practice.") {
                        toggle(\.easeSound)
                    }
                    row("A ring around the pointer", "While you are off task, a ring appears around the pointer and grows the longer you stay away, then goes when you return. It covers nothing and you can click through it. Preview shows a 10 second growth.") {
                        HStack(spacing: Space.s) {
                            Button("Preview") { c.previewHalo() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            Toggle("", isOn: Binding(get: { c.prefs.cursorHalo }, set: { c.prefs.cursorHalo = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                    }
                    row("Close in the edges of the screen", "While you are off task, the edges of every display darken and close in toward the middle, deeper the longer you stay away, and it opens again when you return. It works with the gray or on its own. Preview shows a 10 second fade. Nothing is captured.") {
                        HStack(spacing: Space.s) {
                            Button("Preview") { c.previewEdges() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            Toggle("", isOn: Binding(get: { c.prefs.screenEdges }, set: { c.prefs.screenEdges = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                    }
                }
                group("More options", .nudges) {
                    DisclosureGroup("Advanced", isExpanded: $showMoreNudges) {
                    if c.prefs.escalate {
                        row("Hide the app you drifted into", "The last step. It hides the app like Command-H: nothing is closed and no work is lost. Click the app in the Dock to bring it back. Hushd, Finder and system apps are never hidden.") {
                            Toggle("", isOn: Binding(get: { c.prefs.hideDistractingApp }, set: { c.prefs.hideDistractingApp = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                    }
                    row("Open it again if it was closed", "If the document, folder or page you were working in has been closed, or its app quit, \u{201C}Back to task\u{201D} opens it again instead of only bringing the app forward. Only things you had open and Hushd read as on task, and only when you press Back to task.") {
                        toggle(\.reopenClosed)
                    }
                    row("Bring your other windows too", "\u{201C}Back to task\u{201D} also brings forward up to two other windows you really worked in (the notes beside the page), then the main one on top, so the distraction ends up behind all of them.") {
                        toggle(\.bringWorkingSet)
                    }
                    row("Put it away when I go back", "When you press Back to task from an app you drifted into, that app is hidden, like Command-H. Nothing is closed and no work is lost; click it in the Dock to bring it back. Hushd, Finder, system apps and apps on your never-judged list are never hidden.") {
                        toggle(\.putAwayOnReturn)
                    }
                    row("Let a link or the Dock do it", "The link focusapp://back and the Dock icon's menu do \u{201C}Back to task\u{201D} during a session, so Shortcuts, Raycast or a button on a Stream Deck can. Nothing else can be started that way, and a burst of links counts once.") {
                        toggle(\.allowBackLink)
                    }
                    row("Back to your spot", "While you work, Hushd notes how far the window was scrolled and where the text cursor was (numbers, never the words, in memory only). \u{201C}Back to task\u{201D} puts both back. Not every app lets Hushd do this.") {
                        toggle(\.restoreSpot)
                    }
                    row("Mark the way back", "While Hushd is nudging you, a faint ring outlines the window \u{201C}Back to task\u{201D} would take you to, even if something is on top of it, and goes the moment you are back. It asks for nothing. A steady ring with Reduce Motion on.") {
                        toggle(\.beaconRing)
                    }
                    row("Ring the window you land in", "After \u{201C}Back to task\u{201D}, a soft ring marks the window that came forward for a second or two, so you can see where the task is. A fainter ring means only the app came forward, not the exact window. No motion with Reduce Motion on.") {
                        toggle(\.landingRing)
                    }
                    if c.prefs.escalate {
                        row("Switch back to your tab", "\u{201C}Back to task\u{201D} takes you to the exact tab you were last working in, in whichever browser it was, and the first time the last step runs Hushd does the same instead of only hiding the app. Works with Safari, Chrome, Brave, Edge and Comet. macOS asks once for permission to control the browser; if you say no, Hushd brings the browser or hides the app instead.") {
                            toggle(\.switchTabs)
                        }
                        row("Close the tab on Strict", "On the Strict preset, later rounds of the last step close the tab you were warned about, not the whole browser. Only tabs Hushd can name, never private windows or apps on your never-judged list. Closing can lose unsaved work in that tab, so the banner says so first.") {
                            toggle(\.closeOnStrict)
                        }
                    }
                    if !c.prefs.practiceRemoved {
                        row("Practice mode", "Watch without interrupting for the first \(Preferences.practiceSessions) sessions.") {
                            Toggle("", isOn: Binding(get: { c.prefs.practiceActive }, set: { $0 ? c.prefs.restartPractice() : c.prefs.turnNudgesOnNow() })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                    }
                    row("Remove practice mode", c.prefs.practiceRemoved ? "Practice mode is gone from Hushd. Every session nudges from the start, and Review shows only moments already waiting for an answer." : "Takes practice mode out of Hushd for good. Every session nudges from the start, and its screens, counts and messages disappear. You can bring it back here.") {
                        Toggle("", isOn: Binding(get: { c.prefs.practiceRemoved }, set: { c.prefs.practiceRemoved = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    }
                }
                group("On screen", .cues) {
                    row("Banner over the window you are in", "A small banner with your task, over the window you drifted into, from the warning until you are back. No sound, and it never covers the whole screen.") {
                        toggle(\.showBanner)
                    }
                    if c.prefs.showBanner {
                        row("Heads-up before a warning", "When your last few windows look like a rabbit hole, a gentler banner appears before any warning. It can be wrong, so \u{201C}This is part of it\u{201D} teaches Hushd the window, and it waits five minutes between heads-ups. Not in Gentle.") {
                            toggle(\.headsUp)
                        }
                    }
                    row("Cover a flagged site when it opens again", "After a pause screen, the same site is covered whenever you open it again: 20 seconds the first time, then 40 and 60. If you sit behind the cover without going back or explaining, Hushd acts on the site as the last step does (it switches tabs, hides the app, or on Strict closes the tab). Going back to the task is always one click.") {
                        toggle(\.frictionReturn)
                    }
                }
                group("Feel and sound", .cues) {
                    row("Tint the menu bar ring", "A warm tint for a heads-up or a prompt, and a slow pulse while you are away. The ring's shape shows the state either way.") {
                        toggle(\.menuBarCue)
                    }
                    row("Bounce the Dock icon", "Once for a warning, a step up the ladder or a prompt, only while Hushd is in the background.") {
                        toggle(\.dockBounce)
                    }
                    row("Tap the trackpad", "A silent buzz of several taps with each warning, and it repeats while you stay off task: every 20 seconds after a warning (12 on Strict), longer and stronger once the pause screen is up, and a light one every 15 seconds while Hushd suspects you are drifting. The Mac gives apps one tap strength, so stronger means more taps close together. It only works on a Force Touch trackpad and only while a finger rests on it, so it is a bonus cue, not a promise.") {
                        HStack(spacing: Space.s) {
                            Button("Try") { c.previewCue(haptic: true) }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            toggle(\.hapticTap)
                        }
                    }
                    row("Say nudges aloud", "The Mac's own voice reads the nudge, such as \u{201C}Back to your task.\u{201D} It runs on this Mac. Off by default because other people in the room can hear it, and it stays off in practice mode.") {
                        HStack(spacing: Space.s) {
                            Button("Try") { c.previewCue(haptic: false) }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            toggle(\.speakNudges)
                        }
                    }
                }
                group("Going back", .cues) {
                    row("Explaining a flagged window", "Saying \u{201C}That was fine\u{201D} about a window Hushd read as off topic asks you to explain it, with no wait and no hold: one button, then type. Hushd checks your words against the window itself with both of its judges, and your words alone never pass it. An accepted explanation covers that one page, not the site, for 8 minutes, then 5, 3 and 2 for later ones, and it never becomes a saved rule. Each later one must clear a higher bar, a pasted repeat is refused, and a session allows 8. A wrong answer is acted on at once (the app is hidden, or on Strict the tab is closed), and two lock explaining for 5 minutes, then 10, 20 and 30. A project rule that says never is final.") {
                        Label("Always on", systemImage: "lock").foregroundStyle(Tokens.ink2)
                    }
                    row("Hold to go back to your task", "Off by default. When on, \u{201C}Back to task\u{201D} on the pause, cover and claim screens asks you to press and hold for 3 seconds, as a small commitment to going back. Escape no longer skips it. It is never behind a wait or a lock, and explaining a window stays one press.") {
                        toggle(\.holdToReturn)
                    }
                }
                group("Rhythm", .rhythm) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            HStack(spacing: Space.xs) { Text("Scheduled prompts"); InfoButton(text: c.prefs.rhythm.detail) }
                            Spacer()
                            segmented(Rhythm.allCases, selection: Binding(get: { c.prefs.rhythm }, set: { c.prefs.rhythm = $0 }), title: \.title)
                        }
                    }
                    if c.prefs.rhythm == .checkIns {
                        row("Check in every", "Time spent in a session, not counting breaks or pauses. A prompt you ignore counts as a yes after 90 seconds.") {
                            Picker("", selection: Binding(get: { c.prefs.checkInMinutes }, set: { c.prefs.checkInMinutes = $0 })) {
                                ForEach(Rhythm.checkInChoices, id: \.self) { Text("\($0) min").tag($0) }
                            }.labelsHidden().frame(width: 100)
                        }
                    }
                }
                group("Progress", .rhythm) {
                    row("Show progress", "A daily goal, focus days with rest days, your longest stretch and how fast you get back on task. Nothing is ever taken away, and a missed day counts as a rest day, up to two a week. Off hides all of it.") {
                        Toggle("", isOn: Binding(get: { c.prefs.showProgress }, set: { c.prefs.showProgress = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    if c.prefs.showProgress {
                        row("Daily goal", "On-task time you would like most days. A day with 20 minutes on task counts as a focus day whatever the goal is.") {
                            Picker("", selection: Binding(get: { c.prefs.dailyGoalMinutes }, set: { c.prefs.dailyGoalMinutes = $0 })) {
                                ForEach(Preferences.goalChoices, id: \.self) { Text($0 >= 60 ? ($0 % 60 == 0 ? "\($0 / 60) h" : "\($0 / 60) h \($0 % 60) min") : "\($0) min").tag($0) }
                            }.labelsHidden().frame(width: 110)
                        }
                    }
                }
                group("What Hushd looks at", .reading) {
                    row("Window titles", "The app name, the window title and the page or file address, from the window in front.") { Text("On").foregroundStyle(Tokens.ink2) }
                    row("Window access", c.windowAccess == .allowed ? "Hushd can read window titles. Page addresses need Accessibility; titles alone also work with Screen Recording." : "Without Accessibility, Hushd can only see which app is in front. Allow it in System Settings, then come back.") {
                        if c.windowAccess == .allowed { Label("Allowed", systemImage: "checkmark").foregroundStyle(Tokens.ink2) }
                        else { Button("Open Accessibility settings") { c.onOpenAccessSettings?() }.buttonStyle(FocusButtonStyle(.secondary, small: true)) }
                    }
                    row("Try it", probeText) {
                        Button(probeBusy ? "Switch windows now" : "Check in 5 seconds") { c.runProbe() }.buttonStyle(FocusButtonStyle(.secondary, small: true)).disabled(probeBusy)
                    }
                }
                group("How it decides", .reading) {
                    row("Judge with the on-device model", "Apple's on-device model reads the window and decides whether it fits your task. It can be wrong. Off: Hushd only follows your project rules and matching words, shows everything else as not judged, and never nudges from its own reading.") {
                        Toggle("", isOn: Binding(get: { c.prefs.useModel }, set: { c.prefs.useModel = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    row("AI coaching, recaps and questions", "The on-device model can suggest a clearer task, write a short recap after a session and answer questions about it. It writes suggestions only and can be wrong. Off: none of these appear. Judging windows is a separate switch above.") {
                        Toggle("", isOn: Binding(get: { c.prefs.aiHelp }, set: { c.prefs.aiHelp = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    row("Count matching words as on task", "A window whose app name, title or address shares words with your task counts as on task without asking the model. It never applies on feeds, video or news sites, and it can only make Hushd quieter.") {
                        Toggle("", isOn: Binding(get: { c.prefs.matchTaskWords }, set: { c.prefs.matchTaskWords = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                }
                group("Left alone", .reading) {
                    row("Skip personal messages, music and blank pages", "Hushd leaves these alone: it does not read them and does not count them as off topic.") {
                        Toggle("", isOn: Binding(get: { c.prefs.skipPersonal }, set: { c.prefs.skipPersonal = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    if c.prefs.skipPersonal {
                        RuleGroup(title: "Apps", symbol: "app", items: Binding(get: { c.prefs.neverJudgedApps }, set: { c.prefs.neverJudgedApps = $0 }), addLabel: "Add app")

                    }
                    row("Never looked at", "Password managers, banking sites and private windows are skipped, always.") { Label("Always on", systemImage: "lock").foregroundStyle(Tokens.ink2) }
                    row("Tools for any work", "Finder, Terminal, Mail, Calendar, System Settings and Activity Monitor are not judged: the app alone does not say whether it serves your task. A project rule, or a task that names the app, still applies.") { Label("Always on", systemImage: "wrench.and.screwdriver").foregroundStyle(Tokens.ink2) }
                }
                group("Appearance", .general) {
                    row("Show in the notch", "A ring and the time while a session runs. On a Mac without a notch it is a small pill under the menu bar.") {
                        Toggle("", isOn: Binding(get: { c.prefs.showNotch }, set: { c.prefs.showNotch = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    row("Text size", "How large text is in this window. The notch and the banner over other windows keep their size, because they have to fit the menu bar.") {
                        Picker("", selection: Binding(get: { c.prefs.textScale }, set: { c.prefs.textScale = $0 })) {
                            ForEach(TextScale.choices, id: \.factor) { Text($0.title).tag(Double($0.factor)) }
                        }.labelsHidden().frame(width: 120)
                    }
                }
                group("Getting started", .general) {
                    row("Welcome", "The three steps from the first time: what Hushd does, window access and your first task.") {
                        Button("Show again") { c.welcomeRequested = true }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            .disabled(c.isActive).help(c.isActive ? "After this session" : "")
                    }
                }
                group("Shortcut", .general) {
                    Picker("Park a thought", selection: Binding(get: { c.prefs.parkingShortcut }, set: { c.prefs.parkingShortcut = $0 })) {
                        ForEach(ParkingShortcut.allCases) { Text($0.label).tag($0) }
                    }.help("Open the thought input from any app")
                    Picker("Back to task", selection: Binding(get: { c.prefs.backShortcut }, set: { c.prefs.backShortcut = $0 })) {
                        ForEach(BackShortcut.allCases) { Text($0.label).tag($0) }
                    }.help("Go back to the window you were working in, from any app, during a session")
                    if let error = c.backShortcutError { Text(error).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                    if let error = c.parkingShortcutError { Text(error).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2) }
                    row("Start or pause from anywhere", "Press Control, Option and F. With no session it opens the start sheet on the project you worked on last. During a session it pauses or resumes.") {
                        Text("\u{2303}\u{2325}F").font(Tokens.rounded(.callout, .semibold)).foregroundStyle(Tokens.ink2)
                    }
                }
                group("Screen reading", .reading) {
                    row("Read the words on screen", "While a session runs, Hushd takes a picture of the window every few seconds, reads the words on it on this Mac, and shows you the picture on Today. The model gets the words, not the picture. Needs Screen Recording. Nothing is saved. Private and never-judged windows are skipped.") {
                        Toggle("", isOn: Binding(get: { c.prefs.readScreen }, set: { c.prefs.readScreen = $0; if $0 { c.onRequestPreviewAccess?() } })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    if c.prefs.readScreen {
                        row("Screen Recording", c.previewAccess == .allowed ? "Allowed. If the picture does not appear, quit and reopen Hushd once." : "Not allowed yet. Allow Hushd in System Settings, then quit and reopen it. If Hushd is already switched on, remove it with the minus button and add it again.") {
                            if c.previewAccess == .allowed { Label("Allowed", systemImage: "checkmark").foregroundStyle(Tokens.ink2) }
                            else { Button("Open Screen Recording settings") { c.onRequestPreviewAccess?() }.buttonStyle(FocusButtonStyle(.secondary, small: true)) }
                        }
                    }
                }
                if c.updateSource != nil {
                    group("Updates", .general) {
                        row("Offer new builds from this Mac", "When a newer build appears in the project's build folder, Hushd offers to restart into it between sessions. Nothing is downloaded and the network is not used; it never restarts by itself.") {
                            Toggle("", isOn: Binding(get: { c.prefs.offerUpdates }, set: { c.prefs.offerUpdates = $0; if $0 { c.onCheckUpdates?() } })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                        row("Update Hushd", c.updateBuild == .building ? "Building the latest version. This can take a few minutes; Hushd restarts when it is done."
                            : c.updateBuild == .failed ? "The build did not finish. This copy is unchanged."
                            : c.isActive ? "Not during a session." : "Builds the latest version on this Mac and restarts into it.") {
                            Button(c.updateBuild == .building ? "Updating\u{2026}" : c.updateOffer != nil ? "Restart to update" : "Update now") { c.updateNow() }
                                .buttonStyle(FocusButtonStyle(.primary, small: true)).disabled(c.isActive || c.updateBuild == .building)
                        }
                        if c.prefs.offerUpdates {
                            row("Check now", c.updateOffer == nil ? "This copy is the newest build found." : "A newer build is ready. It is offered on Today when no session is running.") {
                                Button("Check for a new build") { c.onCheckUpdates?() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            }
                        }
                    }
                }
                if let beta = c.beta { BetaSettings(c: c, beta: beta, page: page) }
                group("Privacy", .privacy) {
                    row("Where the work happens", "The judge is Apple's on-device model. There is no account.") { Text("On this Mac").foregroundStyle(Tokens.ink2) }
                    row("Your data", "\(store.projects.count) projects, \(store.sessions.count) sessions and \(store.review.count) review moments.") {
                        HStack {
                            Button("Export") { export() }.buttonStyle(FocusButtonStyle(.plain, small: true))
                            Button("Delete everything") { confirmDelete = true }.buttonStyle(FocusButtonStyle(.plain, small: true))
                        }
                    }
                }
        }
        .formStyle(.grouped)
        // Rows and headers follow the Text size setting like the rest of the window.
        .font(Tokens.text(.body))
        .scrollContentBackground(.hidden)
        .tint(Tokens.accent)
        .confirmationDialog("Delete everything?", isPresented: $confirmDelete) {
            Button("Delete everything", role: .destructive) { store.deleteEverything() }
        } message: { Text("Projects, sessions, rules and review moments are removed from this Mac. This cannot be undone.") }
    }

    var sensitivityHelp: String {
        switch c.prefs.sensitivity {
        case .careful: return "Flags a window only when the model is nearly certain (95 percent or more). Fewest mistaken warnings; it misses some distractions."
        case .balanced: return "Flags a window when the model is at least 80 percent sure. A middle road."
        case .proactive: return "Flags a window when the model is at least 60 percent sure, so Hushd speaks up about distractions it is not completely sure of. It will sometimes call work a distraction; \u{201C}That was fine\u{201D} teaches it. A warning still needs the drift to last and two checks to agree."
        }
    }

    func toggle(_ key: ReferenceWritableKeyPath<Preferences, Bool>) -> some View {
        Toggle("", isOn: Binding(get: { c.prefs[keyPath: key] }, set: { c.prefs[keyPath: key] = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
    }

    /// A native segmented control: the system draws the sliding selection.
    func segmented<T: Identifiable & Hashable>(_ items: [T], selection: Binding<T>, title: KeyPath<T, String>) -> some View {
        Picker("", selection: selection) {
            ForEach(items) { Text($0[keyPath: title]).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
    }

    func opt(_ p: Preset, _ title: String, _ text: String) -> some View {
        let on = c.prefs.preset == p
        return Button { c.prefs.preset = p } label: {
            // The strength as three steps, the name under it; what it does is the tooltip, so the cards stay quiet.
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: Tokens.radiusTiny / 2).fill(i <= p.level ? Tokens.accent : Tokens.track).frame(width: 12, height: 10)
                    }
                }
                Text(title).font(Tokens.text(.body, .semibold))
            }
                .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(on ? Tokens.accentSoft : Tokens.control))
                .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(Tokens.accent.opacity(on ? 1 : 0), lineWidth: 1.5) }
                .contentShape(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
        .help(text).accessibilityHint(text)
        .motion(Motion.out(0.2), value: on)
    }

    /// A section of the form, shown only on its own page of the sidebar.
    @ViewBuilder func group<V: View>(_ title: String, _ on: SettingsPage, @ViewBuilder _ content: () -> V) -> some View {
        // The groups where the AI's own behavior is set carry its sparkle, as the Hushd panel does.
        if page == on {
            Section { content() } header: {
                HStack(spacing: 5) {
                    if title.contains("decides") { Image(systemName: "sparkles").foregroundStyle(Tokens.accent).accessibilityHidden(true) }
                    Text(title).font(Tokens.text(.body, .semibold))
                }
            }
        }
    }

    /// A settings row as Droppy and System Settings draw it: the title, a small info button that holds the explanation, and the
    /// control on the right. Nothing to read unless you ask.
    func row<V: View>(_ title: String, _ help: String, @ViewBuilder _ trailing: () -> V) -> some View {
        HStack(spacing: Space.l) {
            HStack(spacing: Space.xs) { Text(title); InfoButton(text: help) }
            Spacer(minLength: 12); trailing().fixedSize().layoutPriority(2)
        }
    }

    func export() {
        guard let data = store.exportJSON() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "focus-data.json"
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }
}

/// The circled "i" after a setting's name. Clicking it shows the whole explanation in a popover; VoiceOver reads it as the hint.
private struct InfoButton: View {
    let text: String
    @State private var shown = false
    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle.fill").font(Tokens.symbol(12, .regular)).foregroundStyle(.tertiary).hitTarget()
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel("About this setting").accessibilityHint(text)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true).frame(width: 280, alignment: .leading).padding(Space.m)
        }
    }
}

extension Preset {
    /// How firm, as steps on the strength cards: one, two or three.
    var level: Int { switch self { case .gentle: return 0; case .standard: return 1; case .strict: return 2 } }
}

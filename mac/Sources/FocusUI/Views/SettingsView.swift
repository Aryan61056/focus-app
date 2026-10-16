import SwiftUI
import FocusBrain
import FocusJudge
import AppKit

/// Settings split into pages, each its own row in the sidebar, the way System Settings and Droppy lay them out.
public enum SettingsPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general = "General", nudges = "Nudges", cues = "Cues", rhythm = "Rhythm and goals", reading = "What Focus reads", privacy = "Privacy"
    public var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"; case .nudges: return "hand.wave.fill"; case .cues: return "bell.badge.fill"
        case .rhythm: return "metronome.fill"; case .reading: return "eye.fill"; case .privacy: return "hand.raised.fill"
        }
    }
    var color: Color {
        switch self {
        case .general: return .gray; case .nudges: return Tokens.Art.leaf; case .cues: return .red
        case .rhythm: return .orange; case .reading: return .blue; case .privacy: return .indigo
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
        case .idle: return "Switch to another window after pressing the button. Focus tells you what it can see there. Nothing is kept."
        case .waiting(let n): return "Switch to the window you want to test. Reading in \(n)."
        case .nothing: return "Focus itself was in front, so nothing was read. Try again and switch to another app before the countdown ends."
        case .saw(let app, let title, let trusted):
            if !trusted { return "Saw the app \u{201C}\(app)\u{201D} only. Allow Accessibility to see window titles." }
            return title.isEmpty ? "Saw the app \u{201C}\(app)\u{201D}, but that window gave no title." : "Saw \u{201C}\(app)\u{201D}, window \u{201C}\(title)\u{201D}."
        }
    }
    var body: some View {
        Form {
                if page == .nudges {
                    // Droppy heads its pages with a picture of the feature: here, a nudge as the notch shows it, in the tone you picked.
                    Section {
                        HeroBanner(caption: "A nudge in the notch") { NudgePreviewPill(text: c.prefs.nudgeTone.example) }
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
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
                group("How Focus decides", .nudges) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            HStack(spacing: Space.xs) { Text("How often Focus checks"); InfoButton(text: "\(c.prefs.checkRate.detail) Each check asks the on-device model, so checking more often uses more battery. Applies from the next session.") }
                            Spacer()
                            segmented(CheckRate.allCases, selection: Binding(get: { c.prefs.checkRate }, set: { c.prefs.checkRate = $0 }), title: \.title)
                        }
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            HStack(spacing: Space.xs) { Text("How sure Focus must be"); InfoButton(text: sensitivityHelp) }
                            Spacer()
                            segmented(Sensitivity.allCases, selection: Binding(get: { c.prefs.sensitivity }, set: { c.prefs.sensitivity = $0 }), title: \.title)
                        }
                    }

                    row("Ease in, then push harder when behind", "Focus is easy on you before noon and once you reach your daily goal, and it warns sooner and climbs faster when you are behind the goal's pace for the time of day (a 9 to 6 working day). Today always says which it is. Needs the daily goal below to be on.") {
                        toggle(\.paceMatters)
                    }
                }
                group("If you stay away", .nudges) {
                    row("If you stay away after a warning", "Gentle stops at the warning. Standard and Strict keep going: after about 40 seconds (20 on Strict) Focus asks whether you are on task and reads the window again, then covers every screen with a pause screen, then hides the app you drifted into. Dismissing a card does not stop it; getting back to the task does.") {
                        Toggle("", isOn: Binding(get: { c.prefs.escalate }, set: { c.prefs.escalate = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    row("Fade the whole screen to gray", "While you are off task, every display loses its color a little at a time, deeper the longer you stay away, and it fades back when you return. Preview shows a 10 second fade. Nothing is captured.") {
                        HStack(spacing: Space.s) {
                            Button("Preview") { c.previewVeil() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            Toggle("", isOn: Binding(get: { c.prefs.screenGrayscale }, set: { c.prefs.screenGrayscale = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                    }
                }
                group("More options", .nudges) {
                    DisclosureGroup("Advanced", isExpanded: $showMoreNudges) {
                    if c.prefs.escalate {
                        row("Hide the app you drifted into", "The last step. It hides the app like Command-H: nothing is closed and no work is lost. Click the app in the Dock to bring it back. Focus, Finder and system apps are never hidden.") {
                            Toggle("", isOn: Binding(get: { c.prefs.hideDistractingApp }, set: { c.prefs.hideDistractingApp = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                    }
                    if c.prefs.escalate {
                        row("Switch back to your tab", "\u{201C}Back to task\u{201D} in a browser takes you to the tab you were last working in, and the first time the last step runs Focus does the same instead of only hiding the app. Works with Safari, Chrome, Brave, Edge and Comet. macOS asks once for permission to control the browser; if you say no, Focus hides the app instead.") {
                            toggle(\.switchTabs)
                        }
                        row("Close the tab on Strict", "On the Strict preset, later rounds of the last step close the tab you were warned about, not the whole browser. Only tabs Focus can name, never private windows or apps on your never-judged list. Closing can lose unsaved work in that tab, so the banner says so first.") {
                            toggle(\.closeOnStrict)
                        }
                    }
                    if !c.prefs.practiceRemoved {
                        row("Practice mode", "Watch without interrupting for the first \(Preferences.practiceSessions) sessions.") {
                            Toggle("", isOn: Binding(get: { c.prefs.practiceActive }, set: { $0 ? c.prefs.restartPractice() : c.prefs.turnNudgesOnNow() })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                    }
                    row("Remove practice mode", c.prefs.practiceRemoved ? "Practice mode is gone from Focus. Every session nudges from the start, and Review shows only moments already waiting for an answer." : "Takes practice mode out of Focus for good. Every session nudges from the start, and its screens, counts and messages disappear. You can bring it back here.") {
                        Toggle("", isOn: Binding(get: { c.prefs.practiceRemoved }, set: { c.prefs.practiceRemoved = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    }
                }
                group("On screen", .cues) {
                    row("Banner over the window you are in", "A small banner with your task, over the window you drifted into, from the warning until you are back. No sound, and it never covers the whole screen.") {
                        toggle(\.showBanner)
                    }
                    if c.prefs.showBanner {
                        row("Heads-up before a warning", "When your last few windows look like a rabbit hole, a gentler banner appears before any warning. It can be wrong, so \u{201C}This is part of it\u{201D} teaches Focus the window, and it waits five minutes between heads-ups. Not in Gentle.") {
                            toggle(\.headsUp)
                        }
                    }
                    row("Cover a flagged site when it opens again", "After a pause screen, the same site is covered whenever you open it again: 20 seconds the first time, then 40 and 60. If you sit behind the cover without going back or explaining, Focus acts on the site as the last step does (it switches tabs, hides the app, or on Strict closes the tab). Going back to the task is always one click.") {
                        toggle(\.frictionReturn)
                    }
                }
                group("Feel and sound", .cues) {
                    row("Tint the menu bar ring", "A warm tint for a heads-up or a prompt, and a slow pulse while you are away. The ring's shape shows the state either way.") {
                        toggle(\.menuBarCue)
                    }
                    row("Bounce the Dock icon", "Once for a warning, a step up the ladder or a prompt, only while Focus is in the background.") {
                        toggle(\.dockBounce)
                    }
                    row("Tap the trackpad", "A silent buzz of several taps with each warning, and it repeats while you stay off task: every 20 seconds after a warning (12 on Strict), longer and stronger once the pause screen is up, and a light one every 15 seconds while Focus suspects you are drifting. The Mac gives apps one tap strength, so stronger means more taps close together. It only works on a Force Touch trackpad and only while a finger rests on it, so it is a bonus cue, not a promise.") {
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
                    row("Explaining a flagged window", "Saying \u{201C}That was fine\u{201D} about a window Focus read as off topic asks you to explain it, with no wait and no hold: one button, then type. Focus checks your words against the window itself with both of its judges, and your words alone never pass it. An accepted explanation covers that one page, not the site, for 8 minutes, then 5, 3 and 2 for later ones, and it never becomes a saved rule. Each later one must clear a higher bar, a pasted repeat is refused, and a session allows 8. A wrong answer is acted on at once (the app is hidden, or on Strict the tab is closed), and two lock explaining for 5 minutes, then 10, 20 and 30. A project rule that says never is final.") {
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
                group("What Focus looks at", .reading) {
                    row("Window titles", "The app name, the window title and the page or file address, from the window in front.") { Text("On").foregroundStyle(Tokens.ink2) }
                    row("Window access", c.windowAccess == .allowed ? "Focus can read window titles. Page addresses need Accessibility; titles alone also work with Screen Recording." : "Without Accessibility, Focus can only see which app is in front. Allow it in System Settings, then come back.") {
                        if c.windowAccess == .allowed { Label("Allowed", systemImage: "checkmark").foregroundStyle(Tokens.ink2) }
                        else { Button("Open Accessibility settings") { c.onOpenAccessSettings?() }.buttonStyle(FocusButtonStyle(.secondary, small: true)) }
                    }
                    row("Try it", probeText) {
                        Button(probeBusy ? "Switch windows now" : "Check in 5 seconds") { c.runProbe() }.buttonStyle(FocusButtonStyle(.secondary, small: true)).disabled(probeBusy)
                    }
                }
                group("How it decides", .reading) {
                    row("Judge with the on-device model", "Apple's on-device model reads the window and decides whether it fits your task. It can be wrong. Off: Focus only follows your project rules and matching words, shows everything else as not judged, and never nudges from its own reading.") {
                        Toggle("", isOn: Binding(get: { c.prefs.useModel }, set: { c.prefs.useModel = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    row("AI coaching, recaps and questions", "The on-device model can suggest a clearer task, write a short recap after a session and answer questions about it. It writes suggestions only and can be wrong. Off: none of these appear. Judging windows is a separate switch above.") {
                        Toggle("", isOn: Binding(get: { c.prefs.aiHelp }, set: { c.prefs.aiHelp = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    row("Count matching words as on task", "A window whose app name, title or address shares words with your task counts as on task without asking the model. It never applies on feeds, video or news sites, and it can only make Focus quieter.") {
                        Toggle("", isOn: Binding(get: { c.prefs.matchTaskWords }, set: { c.prefs.matchTaskWords = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                }
                group("Left alone", .reading) {
                    row("Skip personal messages, music and blank pages", "Focus leaves these alone: it does not read them and does not count them as off topic.") {
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
                group("Shortcut", .general) {
                    row("Start or pause from anywhere", "Press Control, Option and F. With no session it opens the start sheet on the project you worked on last. During a session it pauses or resumes.") {
                        Text("\u{2303}\u{2325}F").font(Tokens.rounded(.callout, .semibold)).foregroundStyle(Tokens.ink2)
                    }
                }
                group("Screen reading", .reading) {
                    row("Read the words on screen", "While a session runs, Focus takes a picture of the window every few seconds, reads the words on it on this Mac, and shows you the picture on Today. The model gets the words, not the picture. Needs Screen Recording. Nothing is saved. Private and never-judged windows are skipped.") {
                        Toggle("", isOn: Binding(get: { c.prefs.readScreen }, set: { c.prefs.readScreen = $0; if $0 { c.onRequestPreviewAccess?() } })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                    }
                    if c.prefs.readScreen {
                        row("Screen Recording", c.previewAccess == .allowed ? "Allowed. If the picture does not appear, quit and reopen Focus once." : "Not allowed yet. Allow Focus in System Settings, then quit and reopen it. If Focus is already switched on, remove it with the minus button and add it again.") {
                            if c.previewAccess == .allowed { Label("Allowed", systemImage: "checkmark").foregroundStyle(Tokens.ink2) }
                            else { Button("Open Screen Recording settings") { c.onRequestPreviewAccess?() }.buttonStyle(FocusButtonStyle(.secondary, small: true)) }
                        }
                    }
                }
                if c.updateSource != nil {
                    group("Updates", .general) {
                        row("Offer new builds from this Mac", "When a newer build appears in the project's build folder, Focus offers to restart into it between sessions. Nothing is downloaded and the network is not used; it never restarts by itself.") {
                            Toggle("", isOn: Binding(get: { c.prefs.offerUpdates }, set: { c.prefs.offerUpdates = $0; if $0 { c.onCheckUpdates?() } })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                        }
                        if c.prefs.offerUpdates {
                            row("Check now", c.updateOffer == nil ? "This copy is the newest build found." : "A newer build is ready. It is offered on Today when no session is running.") {
                                Button("Check for a new build") { c.onCheckUpdates?() }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                            }
                        }
                    }
                }
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
        case .proactive: return "Flags a window when the model is at least 60 percent sure, so Focus speaks up about distractions it is not completely sure of. It will sometimes call work a distraction; \u{201C}That was fine\u{201D} teaches it. A warning still needs the drift to last and two checks to agree."
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
            VStack(alignment: .leading, spacing: Space.xxs) { Text(title).font(Tokens.text(.body, .semibold)); Text(text).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(on ? Tokens.accentSoft : Tokens.control))
                .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(Tokens.accent.opacity(on ? 1 : 0), lineWidth: 1.5) }
                .contentShape(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
        .motion(Motion.out(0.2), value: on)
    }

    /// A section of the form, shown only on its own page of the sidebar.
    @ViewBuilder func group<V: View>(_ title: String, _ on: SettingsPage, @ViewBuilder _ content: () -> V) -> some View {
        if page == on { Section { content() } header: { Text(title).font(Tokens.text(.body, .semibold)) } }
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

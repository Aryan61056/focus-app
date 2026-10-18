import SwiftUI
import AppKit

// MARK: the account chip

/// You, at the foot of the sidebar, where Mac apps keep the account: your avatar and name (the same ones Friends uses) and which build
/// this is. It is a local profile, not a sign-in: there is no account and nothing here leaves the Mac. A dot means the beta has
/// something for you (a question, or a report after Focus closed unexpectedly).
struct AccountChip: View {
    @Bindable var c: SessionController
    @Bindable var beta: BetaCenter
    @State private var open = false
    @State private var hover = false

    var name: String { c.prefs.friendName.trimmingCharacters(in: .whitespaces) }
    var attention: Bool { beta.crashNoticeDue || beta.pulseDue(c) || beta.notesDue }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: Space.xs) {
                FriendAvatar(name: name.isEmpty ? "You" : name, emoji: c.prefs.friendEmoji.isEmpty ? nil : c.prefs.friendEmoji, hue: .you, size: 28)
                    .overlay(alignment: .topTrailing) {
                        if attention { Circle().fill(Tokens.accent).frame(width: 8, height: 8).overlay { Circle().strokeBorder(Tokens.sidebar, lineWidth: 1.5) }.offset(x: 2, y: -2) }
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text(name.isEmpty ? "You" : name).font(Tokens.text(.body, .semibold)).lineLimit(1)
                    Text(beta.build.tag).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(1).monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(Tokens.symbol(10, .semibold)).foregroundStyle(Tokens.ink2)
            }
            .padding(.horizontal, Space.xs).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(hover || open ? Tokens.control : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .help("Your profile, feedback and this build")
        .accessibilityLabel("\(name.isEmpty ? "You" : name), \(beta.build.label)\(attention ? ", something new" : "")")
        // The sidebar is always dark, but a popover is its own window and follows the system, so it gets the system's scheme back.
        .popover(isPresented: $open, arrowEdge: .top) {
            AccountMenu(c: c, beta: beta, close: { open = false })
                .environment(\.colorScheme, NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
        }
        .onChange(of: beta.accountRequests) { _, _ in open = true }
    }
}

/// The chip's popover: who you are on this Mac, the build, how far through the beta's tries you are, and the ways to send feedback.
struct AccountMenu: View {
    @Bindable var c: SessionController
    @Bindable var beta: BetaCenter
    var close: () -> Void

    var body: some View {
        let missions = beta.missions(c)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                AvatarButton(emoji: Binding(get: { c.prefs.friendEmoji }, set: { c.prefs.friendEmoji = $0 }), name: c.prefs.friendName, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Your name", text: Binding(get: { c.prefs.friendName }, set: { c.prefs.friendName = String($0.prefix(24)) }))
                        .textFieldStyle(.plain).font(Tokens.text(.headline, .semibold))
                        .help("Shown on this Mac, and to friends only if you turn on Friends")
                    Text("Profile on this Mac. No account.").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                }
            }

            HStack(spacing: Space.s) {
                MissionRing(done: missions.filter(\.done).count, total: missions.count).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(beta.build.label).font(Tokens.text(.body, .semibold)).monospacedDigit()
                    Text(buildLine).font(Tokens.text(.caption)).foregroundStyle(beta.expired ? Tokens.slipInk : Tokens.ink2).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s).modifier(CardSurface(radius: Tokens.radiusInset))

            VStack(spacing: 2) {
                MenuRow(title: "Send feedback", symbol: "paperplane") { close(); beta.requestFeedback(.bug) }
                MenuRow(title: "Report a wrong call", symbol: "exclamationmark.bubble") { close(); beta.requestFeedback(.wrongCall) }
                if !beta.build.notes.isEmpty {
                    MenuRow(title: "What\u{2019}s new", symbol: "sparkle", dot: beta.notesDue) { close(); beta.notesShown = true }
                }
                MenuRow(title: "Beta settings", symbol: "testtube.2") { close(); c.requestSettingsPage(.beta) }
            }
        }
        .padding(Space.m)
        .frame(width: 280)
    }

    var buildLine: String {
        if beta.expired { return "Out of date. Ask for the newest build." }
        let tried = "\(beta.missions(c).filter(\.done).count) of \(beta.missions(c).count) tried"
        if let d = beta.build.daysLeft(at: beta.now()), beta.build.channel == .beta { return "\(tried) \u{00B7} \(d) days left" }
        return tried
    }
}

private struct MenuRow: View {
    var title: String
    var symbol: String
    var dot = false
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(Tokens.accent)
                Text(title)
                Spacer(minLength: 0)
                if dot { Circle().fill(Tokens.accent).frame(width: 7, height: 7).accessibilityLabel("New") }
            }
            .font(Tokens.text(.body)).padding(.horizontal, Space.xs).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(hover ? Tokens.control : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// How many of the build's tries are done, as a ring with the count inside. Green only for what is done.
struct MissionRing: View {
    var done: Int
    var total: Int
    var body: some View {
        let f = total > 0 ? Double(done) / Double(total) : 0
        ZStack {
            Circle().stroke(Tokens.track, lineWidth: 3)
            Circle().trim(from: 0, to: f).stroke(Tokens.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(done)").font(Tokens.fixed(.caption, .semibold, rounded: true)).monospacedDigit()
        }
        .motion(Motion.out(0.4), value: done)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(done) of \(total) tried")
    }
}

/// The tries as a short list: a check for what is done, an open circle for what is left. The detail is the tooltip.
struct MissionList: View {
    var missions: [BetaMission]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(missions) { m in
                HStack(spacing: Space.s) {
                    Image(systemName: m.done ? "checkmark.circle.fill" : "circle")
                        .font(Tokens.symbol(15, .regular)).foregroundStyle(m.done ? Tokens.accent : Tokens.ink2)
                        .contentTransition(.symbolEffect(.replace))
                    Text(m.title).foregroundStyle(m.done ? Tokens.ink2 : Tokens.ink)
                    Spacer(minLength: 0)
                }
                .font(Tokens.text(.body))
                .help(m.detail)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(m.title), \(m.done ? "done" : "not yet"). \(m.detail)")
            }
        }
    }
}

// MARK: feedback

/// Write what happened, see exactly what goes with it, then save the file (or hand it to your mail app when this build has an address).
/// Focus sends nothing itself. The preview is the file, byte for byte.
struct FeedbackSheet: View {
    @Bindable var c: SessionController
    @Bindable var beta: BetaCenter
    @State var draft: FeedbackDraft
    @State private var showPreview = false
    @State private var saved: URL?
    @State private var failed = false
    @State private var crash: CrashSummary?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var messageFocused: Bool

    init(c: SessionController, beta: BetaCenter, kind: FeedbackReport.Kind) {
        self.c = c; self.beta = beta; _draft = State(initialValue: FeedbackDraft(kind: kind))
    }

    var report: FeedbackReport { beta.report(draft, c: c) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let saved { done(saved) } else { form }
        }
        .padding(Space.l)
        .frame(width: 520)
        .onAppear { crash = beta.recentCrash(); draft.includeCrash = crash != nil; messageFocused = true }
    }

    @ViewBuilder var form: some View {
        Text("Send feedback").font(Tokens.rounded(.title3, .semibold)).accessibilityAddTraits(.isHeader)

        Picker("Kind", selection: $draft.kind) {
            ForEach(FeedbackReport.Kind.allCases) { k in Label(k.title, systemImage: k.symbol).tag(k) }
        }
        .pickerStyle(.segmented).labelsHidden()

        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(get: { draft.message }, set: { draft.message = String($0.prefix(FeedbackReport.messageLimit)) }))
                .font(Tokens.text(.body)).scrollContentBackground(.hidden).focused($messageFocused)
                .padding(Space.xs)
            if draft.message.isEmpty {
                Text(draft.kind.prompt).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                    .padding(.horizontal, Space.xs + 5).padding(.vertical, Space.xs).allowsHitTesting(false)
            }
        }
        .frame(height: 130)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
        .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(messageFocused ? Tokens.accent : Tokens.line, lineWidth: messageFocused ? 1.5 : 1) }
        .accessibilityLabel("What happened")

        TextField("How to reach you (optional)", text: $draft.contact).wellField()

        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Goes with it").font(Tokens.text(.body, .semibold))
            include("This Mac and your settings", "macOS version, Mac model, memory, whether permissions are on, and your switches and choices.", $draft.includeSystem)
            include("Counts", "Sessions, minutes, nudges and Review answers from the last two weeks. Numbers only.", $draft.includeUsage)
            include("What happened when", "The beta log: when sessions, nudges, crashes and slow moments happened. Kinds and times only.", $draft.includeEvents)
            if crash != nil {
                include("The last crash", "What went wrong and where in Focus's code, from the report macOS wrote. Paths and IDs removed.", $draft.includeCrash)
            }
            HStack(spacing: Space.xxs) {
                Image(systemName: "lock").font(Tokens.symbol(11))
                Text("Never included: task and project names, window titles, addresses, screen words, pictures.")
            }
            .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).padding(.top, 2)
        }

        DisclosureGroup("See the whole file", isExpanded: $showPreview) {
            ScrollView {
                Text(String(data: report.encoded() ?? Data(), encoding: .utf8) ?? "")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.xs)
            }
            .frame(height: 180)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
        }
        .font(Tokens.text(.body))

        if failed { Text("Could not save the report. Try another folder.").font(Tokens.text(.caption)).foregroundStyle(Tokens.slipInk) }

        HStack(spacing: Space.s) {
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(FocusButtonStyle(.plain)).keyboardShortcut(.cancelAction)
            if beta.build.feedbackAddress != nil && beta.onEmail != nil {
                Button("Save file\u{2026}") { save() }.buttonStyle(FocusButtonStyle(.secondary)).disabled(!draft.ready)
                Button("Email report") { email() }.buttonStyle(FocusButtonStyle(.primary)).disabled(!draft.ready).keyboardShortcut(.defaultAction)
            } else {
                Button("Save report\u{2026}") { save() }.buttonStyle(FocusButtonStyle(.primary)).disabled(!draft.ready).keyboardShortcut(.defaultAction)
            }
        }
    }

    func include(_ title: String, _ detail: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) { Text(title) }.toggleStyle(.checkbox).help(detail).accessibilityHint(detail)
    }

    func save() {
        let r = report
        switch beta.savePanel(for: r) {
        case .saved(let url): failed = false; withAnimation(Motion.out()) { saved = url }
        case .failed: failed = true
        case .cancelled: break
        }
    }
    func email() {
        let r = report
        if beta.email(r), let url = beta.lastSaved { withAnimation(Motion.out()) { saved = url } } else { failed = true }
    }

    @ViewBuilder func done(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Image(systemName: "checkmark.circle.fill").font(Tokens.symbol(28, .regular)).foregroundStyle(Tokens.accent)
            Text("Report saved").font(Tokens.rounded(.title3, .semibold))
            Text(beta.build.feedbackAddress != nil && beta.onEmail != nil
                 ? "Your mail app has it attached. Send it when you are ready."
                 : "Send \(url.lastPathComponent) to whoever gave you this build.")
                .font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(FocusButtonStyle(.secondary))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
            }
            .padding(.top, Space.xs)
        }
    }
}

// MARK: what's new

struct WhatsNewSheet: View {
    @Bindable var beta: BetaCenter
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.xs) {
                Image(systemName: "sparkle").foregroundStyle(Tokens.accent)
                Text("New in \(beta.build.label)").font(Tokens.rounded(.title3, .semibold)).monospacedDigit()
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(Array(beta.build.notes.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Circle().fill(Tokens.accent).frame(width: 5, height: 5).offset(y: -2)
                        Text(line).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(Tokens.text(.body))
            HStack {
                Button("Send feedback") { dismiss(); beta.requestFeedback(.idea) }.buttonStyle(FocusButtonStyle(.plain))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.l).frame(width: 440)
        .onAppear { beta.journal.markNotesSeen(for: beta.build) }
    }
}

// MARK: the weekly question

/// Five dots, worst to best, on Today's notice line. One click answers; the tooltip says what each means.
struct PulseDots: View {
    var answer: (Int) -> Void
    @State private var hover: Int?
    static let meanings = ["Not working for me", "Mostly in the way", "Some days it helps", "It helps", "I rely on it"]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Button { answer(i) } label: {
                    Circle().fill((hover ?? 0) >= i ? Tokens.accent : Tokens.track).frame(width: 14, height: 14).hitTarget()
                }
                .buttonStyle(.plain).help(Self.meanings[i - 1]).onHover { hover = $0 ? i : (hover == i ? nil : hover) }
                .accessibilityLabel("\(i) of 5, \(Self.meanings[i - 1])")
            }
        }
        .animation(Motion.hover, value: hover)
    }
}

// MARK: Settings > Beta

/// The beta's page in Settings: this build, the tries, feedback, and what the beta keeps on this Mac (with a way to see and clear it).
struct BetaSettings: View {
    @Bindable var c: SessionController
    @Bindable var beta: BetaCenter
    var page: SettingsPage
    @State private var confirmClear = false

    var body: some View {
        if page == .beta {
            let missions = beta.missions(c)
            Section {
                HStack(spacing: Space.m) {
                    MissionRing(done: missions.filter(\.done).count, total: missions.count).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(beta.build.label).font(Tokens.rounded(.headline, .semibold)).monospacedDigit()
                        Text(subtitle).font(Tokens.text(.caption)).foregroundStyle(beta.expired ? Tokens.slipInk : Tokens.ink2).monospacedDigit()
                    }
                    Spacer(minLength: 12)
                    if !beta.build.notes.isEmpty {
                        Button("What\u{2019}s new") { beta.notesShown = true }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    }
                }
                .padding(.vertical, Space.xxs)
            } header: { header("This build") }

            Section {
                MissionList(missions: missions).padding(.vertical, Space.xxs)
            } header: { header("Try these") }

            Section {
                HStack(spacing: Space.s) {
                    Button { beta.requestFeedback(.bug) } label: { Label("Send feedback", systemImage: "paperplane") }.buttonStyle(FocusButtonStyle(.primary, small: true))
                    Button { beta.requestFeedback(.wrongCall) } label: { Label("Wrong call", systemImage: "exclamationmark.bubble") }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    Spacer()
                    if beta.journal.count(.feedbackSaved) > 0 {
                        Text("\(beta.journal.count(.feedbackSaved)) sent").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                    }
                }
            } header: { header("Feedback") }

            Section {
                row("Keep a beta log", "When sessions, nudges, crashes and slow moments happen, as kinds and times. No names, titles or screen words. It stays on this Mac and only goes in a report you save. Off: nothing new is written.") {
                    Toggle("", isOn: Binding(get: { beta.journal.recording }, set: { beta.journal.recording = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                }
                row("Ask once a week", "One question on Today, between sessions, at most once a week: how Focus is working for you. Five dots, one click.") {
                    Toggle("", isOn: Binding(get: { beta.journal.pulseOn }, set: { beta.journal.pulseOn = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                }
                row("Log on this Mac", "\(beta.journal.events.count) entries and \(beta.journal.pulses.count) answers. Clearing removes them; your sessions are not touched.") {
                    HStack(spacing: Space.xs) {
                        Text(slowLine).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                        Button("Clear") { confirmClear = true }.buttonStyle(FocusButtonStyle(.plain, small: true)).disabled(beta.journal.events.isEmpty && beta.journal.pulses.isEmpty)
                    }
                }
            } header: { header("What the beta keeps") }
            .confirmationDialog("Clear the beta log?", isPresented: $confirmClear) {
                Button("Clear log", role: .destructive) { beta.journal.clear() }
            } message: { Text("Entries and weekly answers are removed from this Mac. Sessions and projects stay.") }
        }
    }

    var subtitle: String {
        if beta.expired { return "Out of date. Ask for the newest build." }
        var parts: [String] = []
        if let d = beta.build.daysLeft(at: beta.now()), beta.build.channel == .beta { parts.append("\(d) days left") }
        if let id = beta.build.buildID { parts.append(String(id.suffix(7))) }
        return parts.isEmpty ? beta.build.tag : parts.joined(separator: " \u{00B7} ")
    }
    var slowLine: String {
        let crashes = beta.journal.count(.uncleanExit), hangs = beta.journal.count(.hang)
        return crashes + hangs == 0 ? "No crashes" : "\(crashes) crash\(crashes == 1 ? "" : "es"), \(hangs) slow"
    }

    func header(_ t: String) -> some View { Text(t).font(Tokens.text(.body, .semibold)) }
    func row<V: View>(_ title: String, _ help: String, @ViewBuilder _ trailing: () -> V) -> some View {
        HStack(spacing: Space.l) {
            Text(title).help(help).accessibilityHint(help)
            Spacer(minLength: 12); trailing().fixedSize().layoutPriority(2)
        }
    }
}

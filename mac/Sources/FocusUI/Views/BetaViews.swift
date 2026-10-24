import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The beta, seen by a tester: the profile chip at the foot of the sidebar, its popover, the Beta page in Settings, the feedback sheet
// and What's new. Shapes carry the state (a ring for the days left, a bar of seven for the tries, three checks for this Mac); words
// are labels, and anything longer is a tooltip.

// MARK: the account chip

/// You, at the foot of the sidebar, where Mac apps keep the account: your avatar and name (the same ones Friends uses) and which build
/// this is. It is a local profile, not a sign-in: there is no account and nothing here leaves the Mac. A dot means the beta has
/// something for you (a question, or a report after Hushd closed unexpectedly).
struct AccountChip: View {
    @Bindable var c: SessionController
    @Bindable var beta: BetaCenter
    @State private var open = false
    @State private var hover = false

    var name: String { c.prefs.friendName.trimmingCharacters(in: .whitespaces) }
    var attention: Bool { beta.crashNoticeDue || beta.pulseDue(c) || beta.notesDue || beta.welcomeDue }

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

/// The chip's popover: who you are on this Mac, the build with its days and tries, and the ways to send feedback.
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

            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.s) {
                    BetaClock(beta: beta, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(beta.build.label).font(Tokens.text(.body, .semibold)).monospacedDigit()
                        Text(BetaWords.timeLine(beta)).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: Space.xs) {
                    MissionBar(missions: missions)
                    Text("\(missions.filter(\.done).count) of \(missions.count)").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                        .fixedSize()
                }
                .help(missions.filter { !$0.done }.map(\.title).joined(separator: ", ").isEmpty ? "All tried" : "Still to try: " + missions.filter { !$0.done }.map(\.title).joined(separator: ", "))
            }
            .padding(Space.s).modifier(CardSurface(radius: Tokens.radiusInset))

            VStack(spacing: 2) {
                MenuRow(title: "Send feedback", symbol: "paperplane") { close(); beta.requestFeedback(.bug) }
                MenuRow(title: "Report a wrong call", symbol: "exclamationmark.bubble") { close(); beta.requestFeedback(.wrongCall) }
                if !beta.build.notes.isEmpty || !beta.build.knownIssues.isEmpty {
                    MenuRow(title: "What\u{2019}s new", symbol: "sparkle", dot: beta.notesDue) { close(); beta.notesShown = true }
                }
                if beta.canOpenReleases {
                    MenuRow(title: "Get the newest build", symbol: "arrow.down.circle", dot: beta.expired) { close(); beta.openNewestBuild() }
                        .help("Opens the beta's downloads on GitHub in your browser")
                }
                MenuRow(title: "Beta page", symbol: "testtube.2") { close(); c.requestSettingsPage(.beta) }
            }
        }
        .padding(Space.m)
        .frame(width: 288)
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

/// Short lines shared by the popover and the Beta page.
@MainActor enum BetaWords {
    static func timeLine(_ beta: BetaBuild, now: Date) -> String {
        guard beta.channel == .beta else { return beta.channel == .dev ? "Built on this Mac" : "Release" }
        guard let e = beta.expires else { return "No end date" }
        if beta.expired(at: now) { return "Out of date since \(e.formatted(.dateTime.month(.abbreviated).day()))" }
        let d = beta.daysLeft(at: now) ?? 0
        return d == 0 ? "Last day" : "\(d) day\(d == 1 ? "" : "s") left \u{00B7} until \(e.formatted(.dateTime.month(.abbreviated).day()))"
    }
    static func timeLine(_ center: BetaCenter) -> String { timeLine(center.build, now: center.now()) }
}

// MARK: shapes

/// The beta's time as a ring that empties toward the end date, with the days left inside. Dev builds show a full, quiet ring.
struct BetaClock: View {
    @Bindable var beta: BetaCenter
    var size: CGFloat = 52
    var body: some View {
        let left = beta.build.channel == .beta ? (beta.build.remaining(at: beta.now()) ?? 1) : 1
        let days = beta.build.channel == .beta ? beta.build.daysLeft(at: beta.now()) : nil
        let line = max(2.5, size / 16)
        ZStack {
            Circle().stroke(Tokens.track, lineWidth: line)
            Circle().trim(from: 0, to: left).stroke(beta.expired ? Tokens.ink2 : Tokens.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let days {
                VStack(spacing: -2) {
                    Text("\(max(0, days))").font(Tokens.rounded(size >= 48 ? .headline : .caption, .semibold)).monospacedDigit()
                    if size >= 48 { Text(days == 1 ? "day" : "days").font(Tokens.text(.caption2)).foregroundStyle(Tokens.ink2) }
                }
            } else {
                Image(systemName: "hammer").font(Tokens.symbol(size * 0.3, .medium)).foregroundStyle(Tokens.ink2)
            }
        }
        .frame(width: size, height: size)
        .motion(Motion.out(0.4), value: left)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days.map { "\($0) days left in this beta" } ?? "Development build")
    }
}

/// The build's tries as a bar of short segments, one per try, filled when done. Order follows the list.
struct MissionBar: View {
    var missions: [BetaMission]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(missions) { m in
                Capsule().fill(m.done ? Tokens.accent : Tokens.track).frame(height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .motion(Motion.out(0.4), value: missions.map(\.done))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(missions.filter(\.done).count) of \(missions.count) tried")
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

/// The tries in two columns: the try's own symbol, its name, and a check once done. The detail is the tooltip.
struct MissionGrid: View {
    var missions: [BetaMission]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m, alignment: .leading), GridItem(.flexible(), spacing: Space.m, alignment: .leading)],
                  alignment: .leading, spacing: Space.xs) {
            ForEach(missions) { m in
                HStack(spacing: Space.xs) {
                    Image(systemName: m.done ? "checkmark.circle.fill" : m.symbol)
                        .font(Tokens.symbol(14, .medium)).foregroundStyle(m.done ? Tokens.accent : Tokens.ink2).frame(width: 20)
                        .contentTransition(.symbolEffect(.replace))
                    Text(m.title).foregroundStyle(m.done ? Tokens.ink2 : Tokens.ink).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(Tokens.text(.body))
                .frame(minHeight: 26)
                .help(m.detail)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(m.title), \(m.done ? "done" : "not yet"). \(m.detail)")
            }
        }
    }
}

/// What this Mac needs for a useful test, as three checks side by side. A check that needs you has its one fix beside it.
struct ReadyRow: View {
    @Bindable var c: SessionController
    @Bindable var beta: BetaCenter
    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            ForEach(beta.readiness(c)) { check in
                HStack(alignment: .center, spacing: Space.xs) {
                    glyph(check.ok)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(check.title).font(Tokens.text(.body, .semibold)).lineLimit(1)
                        Text(check.status)
                            .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let fix = check.fix {
                        Button("Fix") { apply(fix) }.buttonStyle(FocusButtonStyle(.secondary, small: true)).help(check.detail)
                    }
                }
                .padding(.horizontal, Space.s).frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
                .help(check.detail)
                .accessibilityElement(children: .combine)
            }
        }
    }
    /// A filled check when ready, an open dashed ring while unknown, an outlined mark when it needs you: shape, not only color.
    @ViewBuilder func glyph(_ ok: Bool?) -> some View {
        switch ok {
        case .some(true): Image(systemName: "checkmark.circle.fill").font(Tokens.symbol(18, .regular)).foregroundStyle(Tokens.accent)
        case .some(false): Image(systemName: "exclamationmark.circle").font(Tokens.symbol(18, .regular)).foregroundStyle(Tokens.ink)
        case .none: Circle().strokeBorder(Tokens.ink2, style: StrokeStyle(lineWidth: 1.5, dash: [2.4, 2.4])).frame(width: 17, height: 17)
        }
    }
    func apply(_ fix: BetaCenter.ReadyCheck.Fix) {
        switch fix {
        case .model: c.onOpenModelSettings?()
        case .access: c.onOpenAccessSettings?()
        case .log: beta.journal.recording = true
        }
    }
}

// MARK: feedback

/// Write what happened, see exactly what goes with it, then save the file and post it on GitHub, mail it, or send it yourself.
/// Hushd sends nothing itself. The preview is the file, byte for byte.
struct FeedbackSheet: View {
    @Bindable var c: SessionController
    @Bindable var beta: BetaCenter
    @State var draft: FeedbackDraft
    @State private var showPreview = false
    @State private var saved: URL?
    @State private var route = Route.file
    @State private var failed = false
    @State private var opened = false
    @State private var crash: CrashSummary?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var messageFocused: Bool

    enum Route { case file, email, github }

    init(c: SessionController, beta: BetaCenter, kind: FeedbackReport.Kind, message: String = "", saved: URL? = nil, route: Route = .file) {
        self.c = c; self.beta = beta
        var d = FeedbackDraft(kind: kind); d.message = message
        _draft = State(initialValue: d); _saved = State(initialValue: saved); _route = State(initialValue: route)
    }

    var report: FeedbackReport { beta.report(draft, c: c) }
    var canEmail: Bool { beta.build.feedbackAddress != nil && beta.onEmail != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let saved { done(saved).transition(.rise(reduce: reduceMotion)) } else { form }
        }
        .padding(Space.l)
        .frame(width: 540)
        .tint(Tokens.accent)
        .onAppear { crash = beta.recentCrash(); draft.includeCrash = crash != nil; messageFocused = true }
    }

    @ViewBuilder var form: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Send feedback").font(Tokens.rounded(.title3, .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(beta.build.tag).font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2).monospacedDigit()
                .padding(.horizontal, Space.xs).frame(height: 22).overlay { Capsule().strokeBorder(Tokens.line) }
                .help(beta.build.label)
        }

        HStack(spacing: Space.xs) {
            ForEach(FeedbackReport.Kind.allCases) { k in
                Button { draft.kind = k } label: { Label(k.title, systemImage: k.symbol) }
                    .buttonStyle(ChoiceStyle(on: draft.kind == k))
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Kind of feedback")

        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(get: { draft.message }, set: { draft.message = String($0.prefix(FeedbackReport.messageLimit)) }))
                .font(Tokens.text(.body)).scrollContentBackground(.hidden).focused($messageFocused)
                .padding(Space.xs)
            if draft.message.isEmpty {
                Text(draft.kind.prompt).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
                    .padding(.horizontal, Space.xs + 5).padding(.vertical, Space.xs).allowsHitTesting(false)
            }
        }
        .frame(height: 124)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
        .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(messageFocused ? Tokens.accent : Tokens.line, lineWidth: messageFocused ? 1.5 : 1) }
        .accessibilityLabel("What happened")

        if !beta.postsToGitHub {
            TextField("How to reach you (optional)", text: $draft.contact).wellField()
        }

        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text("Goes with it").font(Tokens.text(.body, .semibold))
                Spacer()
                Button(showPreview ? "Hide the file" : "See the whole file") { withAnimation(Motion.out()) { showPreview.toggle() } }
                    .buttonStyle(.plain).font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.accent)
            }
            Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.xxs) {
                GridRow {
                    include("This Mac and settings", "macOS version, Mac model, memory, whether permissions are on, and your switches and choices.", $draft.includeSystem)
                    include("Counts", "Sessions, minutes, nudges and Review answers from the last two weeks. Numbers only.", $draft.includeUsage)
                }
                GridRow {
                    include("What happened when", "The beta log: when sessions, nudges, crashes and slow moments happened. Kinds and times only.", $draft.includeEvents)
                    if !c.readings.isEmpty {
                        include("Hushd\u{2019}s last calls", "On, unsure or off, and whether the model, a rule or shared words decided. Never which window.", $draft.includeCalls)
                    }
                }
                if crash != nil {
                    GridRow {
                        include("The last crash", "What went wrong and where in Hushd's code, from the report macOS wrote. Paths and IDs removed.", $draft.includeCrash)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Image(systemName: "lock").font(Tokens.symbol(11))
                Text("Never included: task or project names, window titles, addresses, screen words, pictures.").fixedSize(horizontal: false, vertical: true)
            }
            .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).padding(.top, 2)
        }

        if showPreview {
            ScrollView {
                Text(String(data: report.encoded() ?? Data(), encoding: .utf8) ?? "")
                    .font(.system(size: 11 * TextScale.shared.factor, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.xs)
            }
            .frame(height: 170)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
            .transition(.rise(reduce: reduceMotion))
        }

        if failed { Text("Could not save the report. Try another folder.").font(Tokens.text(.caption)).foregroundStyle(Tokens.slipInk) }

        HStack(spacing: Space.s) {
            if beta.postsToGitHub {
                Label("Issues are public", systemImage: "globe").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize()
                    .help("Anyone can read an issue. The report holds no task names, titles, addresses or screen words, and you see it before you post.")
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(FocusButtonStyle(.plain)).keyboardShortcut(.cancelAction)
            if beta.postsToGitHub {
                if canEmail { Button("Email report") { email() }.buttonStyle(FocusButtonStyle(.secondary)).disabled(!draft.ready) }
                else { Button("Save file\u{2026}") { save(.file) }.buttonStyle(FocusButtonStyle(.secondary)).disabled(!draft.ready) }
                Button("Post on GitHub\u{2026}") { save(.github) }.buttonStyle(FocusButtonStyle(.primary)).disabled(!draft.ready).keyboardShortcut(.defaultAction)
            } else if canEmail {
                Button("Save file\u{2026}") { save(.file) }.buttonStyle(FocusButtonStyle(.secondary)).disabled(!draft.ready)
                Button("Email report") { email() }.buttonStyle(FocusButtonStyle(.primary)).disabled(!draft.ready).keyboardShortcut(.defaultAction)
            } else {
                Button("Save report\u{2026}") { save(.file) }.buttonStyle(FocusButtonStyle(.primary)).disabled(!draft.ready).keyboardShortcut(.defaultAction)
            }
        }
    }

    func include(_ title: String, _ detail: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) { Text(title) }.toggleStyle(.checkbox).help(detail).accessibilityHint(detail)
    }

    func save(_ to: Route) {
        let r = report
        switch beta.savePanel(for: r, forGitHub: to == .github) {
        case .saved(let url): failed = false; route = to; withAnimation(Motion.out()) { saved = url }
        case .failed: failed = true
        case .cancelled: break
        }
    }
    func email() {
        let r = report
        if beta.email(r), let url = beta.lastSaved { route = .email; withAnimation(Motion.out()) { saved = url } } else { failed = true }
    }

    @ViewBuilder func done(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Image(systemName: "checkmark.circle.fill").font(Tokens.symbol(26, .regular)).foregroundStyle(Tokens.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Report saved").font(Tokens.rounded(.title3, .semibold)).accessibilityAddTraits(.isHeader)
                    Text(subtitle(url)).font(Tokens.text(.body)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            ReportFileTile(url: url)
            if route == .github {
                VStack(alignment: .leading, spacing: Space.xs) {
                    step(1, "Open the form on GitHub") {
                        Button(opened ? "Open again" : "Open the form") { opened = beta.openIssueForm(draft.kind) || opened }
                            .buttonStyle(FocusButtonStyle(opened ? .secondary : .primary, small: true))
                    }
                    step(2, "Drag the file above into it") { EmptyView() }
                    step(3, "Read it, then submit") { EmptyView() }
                }
                .padding(Space.s)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
            }
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(FocusButtonStyle(.plain))
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(FocusButtonStyle(route == .github && !opened ? .secondary : .primary)).keyboardShortcut(.defaultAction)
            }
        }
    }

    func subtitle(_ url: URL) -> String {
        switch route {
        case .github: return "Post it as an issue. Anyone can read issues on GitHub."
        case .email: return "Your mail app has it attached. Send it when you are ready."
        case .file: return "Send it to whoever gave you this build."
        }
    }

    func step<A: View>(_ n: Int, _ text: String, @ViewBuilder action: () -> A) -> some View {
        HStack(spacing: Space.s) {
            Text("\(n)").font(Tokens.rounded(.caption, .semibold)).monospacedDigit().foregroundStyle(Tokens.accentInk)
                .frame(width: 22, height: 22).background(Circle().fill(Tokens.accentSoft))
            Text(text).font(Tokens.text(.body))
            Spacer(minLength: 0)
            action()
        }
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }
}

/// The saved report as a file you can drag straight into a browser form, a message or Mail. Clicking it shows it in Finder.
struct ReportFileTile: View {
    var url: URL
    @State private var hover = false
    var body: some View {
        HStack(spacing: Space.s) {
            Image(nsImage: NSWorkspace.shared.icon(for: .json)).resizable().interpolation(.high).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(Tokens.text(.body, .semibold)).lineLimit(1).truncationMode(.middle)
                Text(size).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
            }
            Spacer(minLength: Space.s)
            Label("Drag", systemImage: "hand.draw").labelStyle(.titleAndIcon).font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2)
        }
        .padding(.horizontal, Space.s).frame(height: 54)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(hover ? Tokens.controlHover : Tokens.control))
        .overlay { RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).strokeBorder(Tokens.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        .help("Drag this file into the GitHub form, a message or Mail")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Report file \(url.lastPathComponent), \(size). Drag it where you want to send it.")
        .accessibilityAddTraits(.isButton)
    }
    var size: String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: what's new

struct WhatsNewSheet: View {
    @Bindable var beta: BetaCenter
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                BetaClock(beta: beta, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("New in \(beta.build.label)").font(Tokens.rounded(.title3, .semibold)).monospacedDigit()
                    Text(BetaWords.timeLine(beta)).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)

            if !beta.build.notes.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(Array(beta.build.notes.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                            Image(systemName: "sparkle").font(Tokens.symbol(10, .semibold)).foregroundStyle(Tokens.accent).accessibilityHidden(true)
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(Tokens.text(.body))
            }
            if !beta.build.knownIssues.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Known, no report needed").font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.ink2)
                    ForEach(Array(beta.build.knownIssues.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                            Circle().strokeBorder(Tokens.ink2, lineWidth: 1.2).frame(width: 7, height: 7).offset(y: -1).accessibilityHidden(true)
                            Text(line).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(Tokens.text(.body))
                .padding(Space.s).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusInset, style: .continuous).fill(Tokens.well))
            }
            HStack {
                Button("Send feedback") { dismiss(); beta.requestFeedback(.idea) }.buttonStyle(FocusButtonStyle(.plain))
                if beta.expired && beta.canOpenReleases {
                    Button("Get the newest build") { beta.openNewestBuild() }.buttonStyle(FocusButtonStyle(.secondary))
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(FocusButtonStyle(.primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.l).frame(width: 460)
        .onAppear { beta.journal.markNotesSeen(for: beta.build) }
    }
}

/// The beta's views for offscreen snapshots (focus-snapshot --beta), which cannot reach this module's internal types.
public enum BetaPreview {
    @MainActor public static func account(_ c: SessionController, _ beta: BetaCenter) -> some View { AccountMenu(c: c, beta: beta, close: {}) }
    @MainActor public static func feedback(_ c: SessionController, _ beta: BetaCenter, kind: FeedbackReport.Kind, message: String = "") -> some View {
        FeedbackSheet(c: c, beta: beta, kind: kind, message: message)
    }
    /// The sheet after saving: `route` is "github", "email" or "file".
    @MainActor public static func feedbackSaved(_ c: SessionController, _ beta: BetaCenter, file: URL, route: String) -> some View {
        FeedbackSheet(c: c, beta: beta, kind: .wrongCall, saved: file, route: route == "github" ? .github : (route == "email" ? .email : .file))
    }
    @MainActor public static func whatsNew(_ beta: BetaCenter) -> some View { WhatsNewSheet(beta: beta) }
    @MainActor public static func page(_ c: SessionController) -> some View {
        Group { if let store = c.store { SettingsView(c: c, store: store, page: .beta) } }
    }
    @MainActor public static func welcomeNotice(_ c: SessionController) -> some View { NoticeRow(notice: .betaWelcome, c: c) }
    @MainActor public static func expiredNotice(_ c: SessionController) -> some View { NoticeRow(notice: .betaExpired, c: c) }
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

/// The beta's page in Settings: this build and its days, whether this Mac is ready to test, the tries, feedback, and what the beta
/// keeps on this Mac (with a way to turn it off and clear it).
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
                    BetaClock(beta: beta, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hushd \(beta.build.label)").font(Tokens.rounded(.headline, .semibold)).monospacedDigit()
                        Text(subtitle).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                        if !beta.build.knownIssues.isEmpty {
                            Button { beta.notesShown = true } label: {
                                Text("\(beta.build.knownIssues.count) known issue\(beta.build.knownIssues.count == 1 ? "" : "s")")
                            }
                            .buttonStyle(.plain).font(Tokens.text(.caption, .semibold)).foregroundStyle(Tokens.accent).padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 12)
                    if beta.expired && beta.canOpenReleases {
                        Button("Get the newest build") { beta.openNewestBuild() }.buttonStyle(FocusButtonStyle(.primary, small: true))
                    } else if !beta.build.notes.isEmpty || !beta.build.knownIssues.isEmpty {
                        Button("What\u{2019}s new") { beta.notesShown = true }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    }
                }
                .padding(.vertical, Space.xxs)
            }

            Section {
                ReadyRow(c: c, beta: beta).padding(.vertical, Space.xxs)
            } header: { header("Ready to test") }

            Section {
                VStack(alignment: .leading, spacing: Space.s) {
                    MissionBar(missions: missions)
                    MissionGrid(missions: missions)
                }
                .padding(.vertical, Space.xxs)
            } header: {
                HStack {
                    header("Try these")
                    Spacer()
                    Text(missions.allSatisfy(\.done) ? "All tried" : "\(missions.filter(\.done).count) of \(missions.count)")
                        .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                }
            }

            Section {
                HStack(spacing: Space.s) {
                    Button { beta.requestFeedback(.bug) } label: { Label("Send feedback", systemImage: "paperplane") }.buttonStyle(FocusButtonStyle(.primary, small: true))
                    Button { beta.requestFeedback(.wrongCall) } label: { Label("Wrong call", systemImage: "exclamationmark.bubble") }.buttonStyle(FocusButtonStyle(.secondary, small: true))
                    Spacer()
                    Label(destination.text, systemImage: destination.symbol).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).help(destination.help)
                }
                .padding(.vertical, Space.xxs)
            } header: {
                HStack {
                    header("Feedback")
                    Spacer()
                    if beta.journal.count(.feedbackSaved) > 0 {
                        Text("\(beta.journal.count(.feedbackSaved)) saved").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                    }
                }
            }

            Section {
                row("Keep a beta log", "When sessions, nudges, crashes and slow moments happen, as kinds and times. No names, titles or screen words. It stays on this Mac and only goes in a report you save. Off: nothing new is written.") {
                    Toggle("", isOn: Binding(get: { beta.journal.recording }, set: { beta.journal.recording = $0 })).labelsHidden().toggleStyle(.switch).tint(Tokens.accent)
                }
                row("Ask once a week", "One question on Today, between sessions, at most once a week: how Hushd is working for you. Five dots, one click.") {
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
        var parts = [BetaWords.timeLine(beta)]
        if let id = beta.build.buildID { parts.append(String(id.suffix(7))) }
        return parts.joined(separator: " \u{00B7} ")
    }
    var destination: (text: String, symbol: String, help: String) {
        if beta.postsToGitHub { return ("To GitHub, by you", "arrow.up.forward.square", "You save the file, Hushd opens the GitHub form, you drag it in and submit. Issues are public.") }
        if beta.build.feedbackAddress != nil && beta.onEmail != nil { return ("By mail, from you", "envelope", "Your mail app opens a draft with the file attached. You press Send.") }
        return ("A file you send", "doc", "Save the report and send the file to whoever gave you this build.")
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

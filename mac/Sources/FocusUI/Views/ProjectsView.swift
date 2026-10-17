import SwiftUI
import FocusJudge

struct ProjectsView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    @Binding var selected: UUID?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack {
                Spacer()
                Button { let p = store.addProject(name: "New project"); selected = p.id } label: { Label("New project", systemImage: "plus") }
                    .buttonStyle(FocusButtonStyle(.secondary))
            }
            if store.projects.isEmpty {
                EmptyState(symbol: "folder", title: "No projects yet", text: "Start a session and Focus makes a project from what you type. Or add one now and tell it what counts.") {
                    Button("New project") { let p = store.addProject(name: "New project"); selected = p.id }.buttonStyle(FocusButtonStyle(.primary))
                }
            } else {
                HStack(alignment: .top, spacing: Space.xl) {
                    VStack(spacing: 2) { ForEach(store.projects) { p in row(p) } }
                        .padding(Space.xs).frame(width: 250).modifier(CardSurface())
                    if let p = store.project(selected ?? store.projects.first?.id) { ProjectDetail(c: c, store: store, project: p, confirmDelete: $confirmDelete) }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { if selected == nil { selected = store.projects.first?.id } }
    }

    func row(_ p: Project) -> some View {
        let on = (selected ?? store.projects.first?.id) == p.id
        let sessions = store.sessions(for: p.id)
        let live = c.isActive && c.projectId == p.id
        return SidebarRow(selected: on, action: { selected = p.id }) {
            RingView(live ? c.ringState : (sessions.isEmpty ? .unsure : .on), color: live || on ? Tokens.accent : Tokens.ink2).frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(Tokens.text(.body, on ? .semibold : .medium)).lineLimit(1).help(p.name)
                Text(live ? "In a session now" : (sessions.first.map { $0.start.formatted(.relative(presentation: .named)) } ?? "No sessions yet"))
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 50)
    }
}

struct ProjectDetail: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    var project: Project
    @Binding var confirmDelete: Bool

    var body: some View {
        let binding = Binding(get: { store.project(project.id) ?? project }, set: { store.update($0) })
        Scroller {
            VStack(alignment: .leading, spacing: Space.l) {
                // Name and Start side by side when they fit; at large text sizes Start moves under the name instead of cutting it.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) { titleBlock(binding); Spacer(); startButton.fixedSize() }
                    VStack(alignment: .leading, spacing: Space.s) { titleBlock(binding); startButton.fixedSize() }
                }
                field("What Focus should know", help: "Focus compares every window with this and your task. A sentence or two of detail helps more than any list. It stays on this Mac.") {
                    ZStack(alignment: .topLeading) {
                        if binding.wrappedValue.context.isEmpty {
                            Text("For example: writing the methods chapter. The survey tool, Zotero and the stats docs count.")
                                .font(Tokens.text(.body)).foregroundStyle(Tokens.ink2.opacity(0.8)).padding(.horizontal, Space.s).padding(.vertical, Space.xs).allowsHitTesting(false)
                        }
                        TextEditor(text: binding.context).font(Tokens.text(.body)).scrollContentBackground(.hidden).padding(.horizontal, Space.xs).padding(.vertical, Space.xs)
                    }
                    .frame(height: 92).wellField(height: nil)
                }
                AskFocusBox(c: c, project: store.project(project.id) ?? project)
                recent
                RulesDisclosure(profile: binding.profile)
                HStack { Spacer(); Button("Delete project") { confirmDelete = true }.buttonStyle(FocusButtonStyle(.plain, small: true)) }
            }
            .padding(Space.xl).modifier(CardSurface())
            .padding(.bottom, Space.xl)   // the page has no bottom padding of its own, so this scrolls to the window's edge instead of stopping above it
        }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmDelete) {
            Button("Delete project", role: .destructive) { store.deleteProject(project.id) }
        } message: { Text("Its rules are removed. Past sessions stay in History.") }
    }

    func titleBlock(_ binding: Binding<Project>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Name", text: binding.name).textFieldStyle(.plain).font(Tokens.rounded(.title3, .semibold)).frame(minWidth: 200, minHeight: 30)
            let n = store.sessions(for: project.id)
            Text("\(n.count) session\(n.count == 1 ? "" : "s") \u{00B7} \(durationText(n.reduce(0) { $0 + $1.onTaskSeconds })) on task")
                .font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
        }
    }
    var startButton: some View {
        Button { _ = c.startWithDraft(task: project.name, projectId: project.id) } label: { Label("Start session", systemImage: "play.fill") }
            .buttonStyle(FocusButtonStyle(.primary)).disabled(c.isActive)
    }

    /// A field's title with its explanation as a tooltip, so the card reads as fields, not paragraphs.
    func field<V: View>(_ title: String, help: String?, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xxs) {
                Text(title).font(Tokens.text(.body, .semibold))
                if let help { Image(systemName: "info.circle").font(Tokens.symbol(12, .regular)).foregroundStyle(Tokens.ink2).help(help).accessibilityLabel(help).hitTarget() }
            }
            content()
        }
    }

    /// This project's last sessions as timelines, so you see how it has gone without opening History.
    @ViewBuilder var recent: some View {
        let n = Array(store.sessions(for: project.id).prefix(4))
        if !n.isEmpty {
            let longest = n.map(\.activeSeconds).max() ?? 1
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Recent sessions").font(Tokens.text(.body, .semibold))
                ForEach(n) { s in
                    HStack(spacing: Space.s) {
                        Text(s.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                            .frame(width: 96 * TextScale.shared.factor, alignment: .leading)
                        GeometryReader { g in
                            MiniTimeline(segments: s.segments, height: 10).frame(width: max(24, g.size.width * min(1, s.activeSeconds / max(1, longest)))).frame(maxHeight: .infinity)
                        }
                        .frame(height: 18)
                        Text(durationText(s.activeSeconds)).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct RuleGroup: View {
    var title: String, symbol: String
    @Binding var items: [String]
    var addLabel: String
    @State private var adding = false
    @State private var draft = ""
    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text(title).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).frame(width: 60, alignment: .leading).padding(.top, Space.xxs)
            FlowRow {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: Space.xs) {
                        Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Tokens.ink2)
                        Text(item).font(Tokens.text(.caption))
                        Button { items.removeAll { $0 == item } } label: { Image(systemName: "xmark").font(Tokens.symbol(9, .bold)).hitTarget() }
                            .buttonStyle(.plain).foregroundStyle(Tokens.ink2).accessibilityLabel("Remove \(item)")
                    }
                    .padding(.leading, Space.s).padding(.trailing, Space.xxs).frame(height: 28).background(Capsule().fill(Tokens.control))
                }
                if adding {
                    TextField(addLabel, text: $draft).textFieldStyle(.plain).font(Tokens.text(.caption)).padding(.horizontal, Space.s).frame(width: 170, height: 28)
                        .background(Capsule().strokeBorder(Tokens.accent, lineWidth: 1.5))
                        .onSubmit { let v = draft.trimmingCharacters(in: .whitespaces); if !v.isEmpty { items.append(v) }; draft = ""; adding = false }
                } else {
                    Button(addLabel) { adding = true }.buttonStyle(.plain).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                        .padding(.horizontal, Space.s).frame(height: 28).overlay { Capsule().strokeBorder(Tokens.line) }
                }
            }
        }
        .padding(.vertical, Space.xs)
    }
}

/// Minimal wrapping row layout.
struct FlowRow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > w && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }; x += z.width + spacing; rowH = max(rowH, z.height) }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, rowH: CGFloat = 0
        for s in subviews { let z = s.sizeThatFits(.unspecified); if x + z.width > b.maxX && x > b.minX { x = b.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += z.width + spacing; rowH = max(rowH, z.height) }
    }
}

/// Try the judge on a window you describe. Shows the call and the reason, so the AI's thinking is something you can poke at.
struct AskFocusBox: View {
    @Bindable var c: SessionController
    var project: Project
    @State private var app = ""
    @State private var title = ""
    @State private var result: Judgement?
    @State private var asking = false
    var body: some View {
        // Set into the card as a well, not a second card on top of it.
        Inset {
            VStack(alignment: .leading, spacing: Space.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { askTitle; Spacer(); askNote }
                    VStack(alignment: .leading, spacing: 2) { askTitle; askNote }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.xs) { field("App", $app).frame(width: 130 * TextScale.shared.factor); field("Window title", $title).frame(minWidth: 140); askButton }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.xs) { field("App", $app).frame(width: 130 * TextScale.shared.factor); field("Window title", $title) }
                        askButton
                    }
                }
                if let j = result {
                    let call = SessionController.call(j.label)
                    HStack(alignment: .top, spacing: Space.s) {
                        RingView(call == .on ? .on : (call == .off ? .drift : .unsure), color: call == .on ? Tokens.accent : Tokens.ink).frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(call == .on ? "On task" : (call == .off ? "Off topic" : "Not sure")).font(Tokens.text(.body, .semibold))
                            Text(SessionController.tidy(j.reason, failed: j.error != nil)).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
    var askTitle: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles").foregroundStyle(Tokens.accent).accessibilityHidden(true)
            Text("Ask Focus about a window").font(Tokens.text(.body, .semibold))
        }.fixedSize()
    }
    var askNote: some View { Text("Typed, not read from your screen").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize() }
    var askButton: some View {
        Button(asking ? "Asking" : "Ask Focus") { ask() }.buttonStyle(FocusButtonStyle(.secondary)).fixedSize()
            .disabled(asking || title.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    func field(_ prompt: String, _ text: Binding<String>) -> some View {
        TextField(prompt, text: text).font(Tokens.text(.body)).wellField(height: 32, raised: true)
            .onSubmit { ask() }
    }
    func ask() {
        guard !asking else { return }
        asking = true
        let a = app, t = title, p = project
        Task { let j = await c.ask(app: a, title: t, project: p); result = j; asking = false }
    }
}

/// Allow and never lists, still here but tucked away: the model decides first-class, rules only add certainty.
struct RulesDisclosure: View {
    @Binding var profile: ProjectProfile
    @State private var open = false
    var body: some View {
        let n = profile.alwaysAllowApps.count + profile.alwaysAllowDomains.count + profile.linkedPaths.count
        let never = profile.alwaysOffApps.count + profile.alwaysOffDomains.count
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Checked before Focus reads anything. Most projects don't need them.")
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true).padding(.bottom, Space.xs)
                Text("Counts as on task").font(Tokens.text(.caption, .semibold))
                RuleGroup(title: "Apps", symbol: "app", items: $profile.alwaysAllowApps, addLabel: "Add app")
                RuleGroup(title: "Sites", symbol: "globe", items: $profile.alwaysAllowDomains, addLabel: "Add site")
                RuleGroup(title: "Folders", symbol: "folder", items: $profile.linkedPaths, addLabel: "Add folder")
                Text("Never counts").font(Tokens.text(.caption, .semibold)).padding(.top, Space.xs)
                RuleGroup(title: "Apps", symbol: "app", items: $profile.alwaysOffApps, addLabel: "Add app")
                RuleGroup(title: "Sites", symbol: "globe", items: $profile.alwaysOffDomains, addLabel: "Add site")
            }.padding(.top, Space.xs)
        } label: {
            HStack(spacing: Space.s) {
                Text("Rules you set").font(Tokens.text(.body, .semibold))
                Text(n + never == 0 ? "Optional. None set" : "Optional. \(n) that count, \(never) never").font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
            }
        }
        // A plain disclosure under a hairline: rules are optional, so they do not get a box of their own.
        .padding(.top, Space.s)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.line).frame(height: 1) }
    }
}

import SwiftUI
import FocusJudge

struct ProjectsView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    @Binding var selected: UUID?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Projects", subtitle: "What each project is about. Focus reads this to decide what counts, and keeps it between sessions.") {
                Button { let p = store.addProject(name: "New project"); selected = p.id } label: { Label("New project", systemImage: "plus") }
                    .buttonStyle(FocusButtonStyle(.secondary))
            }
            if store.projects.isEmpty {
                EmptyState(symbol: "folder", title: "No projects yet", text: "Start a session and Focus makes a project from what you type. Or add one now and tell it what counts.") {
                    Button("New project") { let p = store.addProject(name: "New project"); selected = p.id }.buttonStyle(FocusButtonStyle(.primary))
                }
            } else {
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 2) { ForEach(store.projects) { p in row(p) } }
                        .padding(6).frame(width: 250).modifier(CardSurface(radius: 16))
                    if let p = store.project(selected ?? store.projects.first?.id) { ProjectDetail(c: c, store: store, project: p, confirmDelete: $confirmDelete) }
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { if selected == nil { selected = store.projects.first?.id } }
    }

    func row(_ p: Project) -> some View {
        let on = (selected ?? store.projects.first?.id) == p.id
        let sessions = store.sessions(for: p.id)
        let live = c.isActive && c.projectId == p.id
        return SidebarRow(selected: on, action: { selected = p.id }) {
            RingView(live ? c.ringState : (sessions.isEmpty ? .unsure : .on), color: live || on ? Tokens.accent : Tokens.ink2).frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(Tokens.text(13.5, on ? .semibold : .medium)).lineLimit(1)
                Text(live ? "In a session now" : (sessions.first.map { $0.start.formatted(.relative(presentation: .named)) } ?? "No sessions yet"))
                    .font(Tokens.text(12)).foregroundStyle(Tokens.ink2).lineLimit(1)
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
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Name", text: binding.name).textFieldStyle(.plain).font(Tokens.rounded(22, .semibold)).frame(minHeight: 30)
                        let n = store.sessions(for: project.id)
                        Text("\(n.count) session\(n.count == 1 ? "" : "s") · \(durationText(n.reduce(0) { $0 + $1.onTaskSeconds })) on task")
                            .font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
                    }
                    Spacer()
                    Button { c.begin(task: project.name, projectId: project.id, autoTick: true) } label: { Label("Start session", systemImage: "play.fill") }
                        .buttonStyle(FocusButtonStyle(.primary)).disabled(c.isActive)
                }
                field("What Focus should know about this project", help: "Focus compares every window with this and your task. A sentence or two of detail helps more than any list. It stays on this Mac.") {
                    ZStack(alignment: .topLeading) {
                        if binding.wrappedValue.context.isEmpty {
                            Text("For example: writing the methods chapter. The survey tool, Zotero and the stats docs count.")
                                .font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2.opacity(0.8)).padding(.horizontal, 11).padding(.vertical, 8).allowsHitTesting(false)
                        }
                        TextEditor(text: binding.context).font(Tokens.text(13.5)).scrollContentBackground(.hidden).padding(.horizontal, 6).padding(.vertical, 8)
                    }
                    .frame(height: 92).wellField(height: nil)
                }
                field("Next step", help: "Shown when you start this project again.") {
                    TextField("One small thing", text: binding.nextStep).font(Tokens.text(13.5)).wellField()
                }
                AskFocusBox(c: c, project: store.project(project.id) ?? project)
                RulesDisclosure(profile: binding.profile)
                HStack { Spacer(); Button("Delete project") { confirmDelete = true }.buttonStyle(FocusButtonStyle(.plain, small: true)) }
            }
            .padding(24).modifier(CardSurface(radius: 18))
        }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmDelete) {
            Button("Delete project", role: .destructive) { store.deleteProject(project.id) }
        } message: { Text("Its rules are removed. Past sessions stay in History.") }
    }

    func field<V: View>(_ title: String, help: String?, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Tokens.text(13, .semibold)); content()
            if let help { Text(help).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2) }
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
        HStack(alignment: .top, spacing: 10) {
            Text(title).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).frame(width: 60, alignment: .leading).padding(.top, 5)
            FlowRow {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 6) {
                        Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Tokens.ink2)
                        Text(item).font(Tokens.text(12.5))
                        Button { items.removeAll { $0 == item } } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                            .buttonStyle(.plain).foregroundStyle(Tokens.ink2).accessibilityLabel("Remove \(item)")
                    }
                    .padding(.leading, 10).padding(.trailing, 8).frame(height: 28).background(Capsule().fill(Tokens.control))
                }
                if adding {
                    TextField(addLabel, text: $draft).textFieldStyle(.plain).font(Tokens.text(12.5)).padding(.horizontal, 10).frame(width: 170, height: 28)
                        .background(Capsule().strokeBorder(Tokens.accent, lineWidth: 1.5))
                        .onSubmit { let v = draft.trimmingCharacters(in: .whitespaces); if !v.isEmpty { items.append(v) }; draft = ""; adding = false }
                } else {
                    Button(addLabel) { adding = true }.buttonStyle(.plain).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
                        .padding(.horizontal, 10).frame(height: 28).overlay { Capsule().strokeBorder(Tokens.line) }
                }
            }
        }
        .padding(.vertical, 6)
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
        Panel(tinted: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ask Focus about a window").font(Tokens.text(12.5, .semibold))
                    Spacer()
                    Text("Type anything. Nothing is read from your screen.").font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
                }
                HStack(spacing: 8) {
                    field("App", $app).frame(width: 130)
                    field("Window title", $title)
                    Button(asking ? "Asking" : "Ask Focus") { ask() }.buttonStyle(FocusButtonStyle(.secondary)).disabled(asking || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let j = result {
                    let call = SessionController.call(j.label)
                    HStack(alignment: .top, spacing: 10) {
                        RingView(call == .on ? .on : (call == .off ? .drift : .unsure), color: call == .on ? Tokens.accent : Tokens.ink).frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(call == .on ? "On task" : (call == .off ? "Off topic" : "Not sure")).font(Tokens.text(13.5, .semibold))
                            Text(SessionController.tidy(j.reason, failed: j.error != nil)).font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true)
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
    func field(_ prompt: String, _ text: Binding<String>) -> some View {
        TextField(prompt, text: text).font(Tokens.text(13)).wellField(height: 32, raised: true)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Rules are checked first, before Focus reads anything. Most projects do not need them. Describe the project above and let Focus decide.")
                    .font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                Text("Counts as on task").font(Tokens.text(12.5, .semibold))
                RuleGroup(title: "Apps", symbol: "app", items: $profile.alwaysAllowApps, addLabel: "Add app")
                RuleGroup(title: "Sites", symbol: "globe", items: $profile.alwaysAllowDomains, addLabel: "Add site")
                RuleGroup(title: "Folders", symbol: "folder", items: $profile.linkedPaths, addLabel: "Add folder")
                Text("Never counts").font(Tokens.text(12.5, .semibold)).padding(.top, 8)
                RuleGroup(title: "Apps", symbol: "app", items: $profile.alwaysOffApps, addLabel: "Add app")
                RuleGroup(title: "Sites", symbol: "globe", items: $profile.alwaysOffDomains, addLabel: "Add site")
            }.padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Text("Rules you set").font(Tokens.text(13, .semibold))
                Text(n + never == 0 ? "Optional. None set" : "Optional. \(n) that count, \(never) never").font(Tokens.text(12.5)).foregroundStyle(Tokens.ink2)
            }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tokens.well))
    }
}

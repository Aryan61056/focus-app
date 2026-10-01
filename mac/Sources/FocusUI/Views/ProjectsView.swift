import SwiftUI
import FocusJudge

struct ProjectsView: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    @State private var selected: UUID?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projects").font(Tokens.rounded(26, .semibold))
                    Text("What each project counts as on task. Focus keeps this between sessions.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
                }
                Spacer()
                Button { let p = store.addProject(name: "New project"); selected = p.id } label: { Label("New project", systemImage: "plus") }
                    .buttonStyle(FocusButtonStyle(.plain))
            }
            if store.projects.isEmpty {
                EmptyState(title: "No projects yet", text: "Start a session and Focus makes a project from what you type. Or add one now and tell it what counts.")
            } else {
                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 4) { ForEach(store.projects) { p in row(p) } }.frame(width: 260)
                    if let p = store.project(selected ?? store.projects.first?.id) { ProjectDetail(c: c, store: store, project: p, confirmDelete: $confirmDelete) }
                }
            }
            Spacer(minLength: 0)
        }
        .onAppear { if selected == nil { selected = store.projects.first?.id } }
    }

    func row(_ p: Project) -> some View {
        let on = (selected ?? store.projects.first?.id) == p.id
        let last = store.sessions(for: p.id).first
        return Button { selected = p.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(Tokens.text(13.5, .semibold)).lineLimit(1)
                Text(last.map { $0.start.formatted(.relative(presentation: .named)) } ?? "No sessions yet").font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Tokens.control : .clear))
            .overlay { if on { RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.accent, lineWidth: 1.5) } }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct ProjectDetail: View {
    @Bindable var c: SessionController
    @Bindable var store: DataStore
    var project: Project
    @Binding var confirmDelete: Bool

    var body: some View {
        let binding = Binding(get: { store.project(project.id) ?? project }, set: { store.update($0) })
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Name", text: binding.name).textFieldStyle(.plain).font(Tokens.rounded(22, .semibold))
                        let n = store.sessions(for: project.id)
                        Text("\(n.count) session\(n.count == 1 ? "" : "s") · \(durationText(n.reduce(0) { $0 + $1.onTaskSeconds })) on task")
                            .font(Tokens.text(13)).foregroundStyle(Tokens.ink2)
                    }
                    Spacer()
                    Button { c.begin(task: project.name, projectId: project.id, autoTick: true) } label: { Label("Start session", systemImage: "play.fill") }
                        .buttonStyle(FocusButtonStyle(.primary)).disabled(c.isActive)
                }
                field("What this project is", help: "Focus reads this when it is unsure about a window. It stays on this Mac.") {
                    TextEditor(text: binding.context).font(Tokens.text(13.5)).scrollContentBackground(.hidden).frame(height: 62).padding(6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.control))
                }
                field("Next step", help: nil) {
                    TextField("One small thing", text: binding.nextStep).textFieldStyle(.plain).padding(.horizontal, 12).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.control))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Counts as on task").font(Tokens.text(12.5, .semibold))
                    RuleGroup(title: "Apps", symbol: "app", items: binding.profile.alwaysAllowApps, addLabel: "Add app")
                    RuleGroup(title: "Sites", symbol: "globe", items: binding.profile.alwaysAllowDomains, addLabel: "Add site")
                    RuleGroup(title: "Folders", symbol: "folder", items: binding.profile.linkedPaths, addLabel: "Add folder")
                    Text("Never counts").font(Tokens.text(12.5, .semibold)).padding(.top, 8)
                    RuleGroup(title: "Apps", symbol: "app", items: binding.profile.alwaysOffApps, addLabel: "Add app")
                    RuleGroup(title: "Sites", symbol: "globe", items: binding.profile.alwaysOffDomains, addLabel: "Add site")
                }
                HStack { Spacer(); Button("Delete project") { confirmDelete = true }.buttonStyle(FocusButtonStyle(.plain, small: true)) }
            }
            .padding(.trailing, 4)
        }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmDelete) {
            Button("Delete project", role: .destructive) { store.deleteProject(project.id) }
        } message: { Text("Its rules are removed. Past sessions stay in History.") }
    }

    func field<V: View>(_ title: String, help: String?, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Tokens.text(12.5, .semibold)); content()
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

struct EmptyState: View {
    var title: String, text: String
    var body: some View {
        Panel(tinted: true) {
            VStack(alignment: .leading, spacing: 6) { Text(title).font(Tokens.rounded(17, .semibold)); Text(text).font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2) }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

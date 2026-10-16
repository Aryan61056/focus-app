import SwiftUI
import AppKit
import FocusBrain

public enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today", projects = "Projects", history = "History", insights = "Insights", review = "Review", settings = "Settings"
    public var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: return "calendar"; case .projects: return "folder"; case .history: return "clock"
        case .insights: return "chart.bar"; case .review: return "checklist"; case .settings: return "slider.horizontal.3"
        }
    }
}

/// One place in the sidebar: an app section, a settings page, or one of your projects (listed under "Projects", the way Droppy
/// lists its droplets).
enum SidebarItem: Hashable {
    case section(AppSection), settings(SettingsPage), project(UUID)
}

public struct RootView: View {
    @Bindable var c: SessionController
    @State var selection: AppSection
    @State private var showStart = false
    @State private var settingsPage = SettingsPage.nudges
    @State private var projectID: UUID?
    @State private var confirmDelete = false
    /// Where you have been and where Back would take you back from, for the toolbar's back and forward buttons.
    @State private var back: [SidebarItem] = []
    @State private var forward: [SidebarItem] = []
    @State private var travelling = false
    @State private var columns = NavigationSplitViewVisibility.all
    /// The project picked inside the Projects screen's own list.
    @State private var listProject: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(controller: SessionController, selection: AppSection = .today) { self.c = controller; self._selection = State(initialValue: selection) }

    var current: SidebarItem {
        if let projectID, selection == .projects { return .project(projectID) }
        return selection == .settings ? .settings(settingsPage) : .section(selection)
    }

    func go(_ item: SidebarItem) {
        switch item {
        case .section(let s): projectID = nil; selection = s
        case .settings(let p): projectID = nil; settingsPage = p; selection = .settings
        case .project(let id): projectID = id; selection = .projects
        }
    }

    var title: String {
        switch current {
        case .section(let s): return s.rawValue
        case .settings(let p): return p.rawValue
        case .project(let id): return c.store?.project(id)?.name ?? "Project"
        }
    }

    public var body: some View {
        Group {
            if SnapshotMode.on {
                // ImageRenderer cannot draw a split view, so offscreen snapshots keep a plain two-pane layout.
                HStack(spacing: 0) { Sidebar(c: c, selection: $selection).background(Tokens.sidebar); detail }
            } else {
                // Laid out like Droppy's window: a source list with search and a header row, the page name in the toolbar beside
                // back and forward, and one action on the right.
                NavigationSplitView(columnVisibility: $columns) {
                    SourceList(c: c, item: Binding(get: { current }, set: { if let v = $0 { go(v) } }), selection: selection)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                        // The sidebar button sits at the sidebar's own right edge, where Droppy has it.
                        .toolbar(removing: .sidebarToggle)
                        .toolbar {
                            ToolbarItem(placement: .automatic) {
                                Button { withAnimation(Motion.glide) { columns = columns == .detailOnly ? .all : .detailOnly } } label: {
                                    Label("Show or hide the sidebar", systemImage: "sidebar.left")
                                }
                                .keyboardShortcut("s", modifiers: [.command, .control])
                            }
                        }
                } detail: {
                    detail
                        .navigationTitle(title)
                        .toolbar {
                            // Back and forward share one glass capsule, as in Droppy and System Settings.
                            ToolbarItemGroup(placement: .navigation) {
                                Button { travel(from: &back, to: &forward) } label: { Label("Back", systemImage: "chevron.left") }
                                    .disabled(back.isEmpty).keyboardShortcut("[", modifiers: .command)
                                Button { travel(from: &forward, to: &back) } label: { Label("Forward", systemImage: "chevron.right") }
                                    .disabled(forward.isEmpty).keyboardShortcut("]", modifiers: .command)
                            }
                            ToolbarItem(placement: .primaryAction) { SessionToolbarPill(c: c, showStart: $showStart) }
                        }
                }
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .foregroundStyle(Tokens.ink)
        .onChange(of: current) { old, _ in
            if travelling { travelling = false } else { back.append(old); forward.removeAll() }
        }
        .onChange(of: c.sectionRequest?.serial) { _, _ in if let r = c.sectionRequest { go(.section(r.section)) } }
        .onChange(of: c.settingsPageRequest?.serial) { _, _ in if let r = c.settingsPageRequest { go(.settings(r.page)) } }
        .onChange(of: c.startRequests) { _, _ in if !c.isActive { go(.section(.today)); showStart = true } }
        .sheet(isPresented: $showStart) { StartSheet(controller: c, isPresented: $showStart) }
    }

    func travel(from a: inout [SidebarItem], to b: inout [SidebarItem]) {
        guard let to = a.popLast() else { return }
        b.append(current); travelling = true; go(to)
    }

    var detail: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                    switch current {
                    case .project(let id):
                        if let st = c.store, let p = st.project(id) { ProjectDetail(c: c, store: st, project: p, confirmDelete: $confirmDelete).id(id) }
                        else { ComingNext(section: .projects) }
                    case .section(.today): TodayView(c: c, showStart: $showStart)
                    case .section(.projects): if let st = c.store { ProjectsView(c: c, store: st, selected: $listProject) } else { ComingNext(section: selection) }
                    case .section(.history): if let st = c.store { HistoryView(store: st) } else { ComingNext(section: selection) }
                    case .section(.review) where !c.showsReview: TodayView(c: c, showStart: $showStart)
                    case .section(.review): if let st = c.store { ReviewView(c: c, store: st) } else { ComingNext(section: selection) }
                    case .section(.insights): if let st = c.store { InsightsView(c: c, store: st) } else { ComingNext(section: selection) }
                    case .settings(let page): if let st = c.store { SettingsView(c: c, store: st, page: page) } else { ComingNext(section: selection) }
                    default: ComingNext(section: selection)
                    }
                }
                // Each page arrives with a short rise out of a soft blur. Keyframes on the same views (no new identity), so the
                // scroll position and anything else that changes at the same moment are left alone.
                .keyframeAnimator(initialValue: Entrance(), trigger: current) { content, v in
                    content.opacity(v.opacity).offset(y: reduceMotion ? 0 : v.rise).blur(radius: reduceMotion ? 0 : v.blur)
                } keyframes: { _ in
                    KeyframeTrack(\.opacity) { MoveKeyframe(0); CubicKeyframe(1, duration: 0.26) }
                    KeyframeTrack(\.rise) { MoveKeyframe(10); SpringKeyframe(0, duration: 0.42, spring: .init(duration: 0.42, bounce: 0.1)) }
                    KeyframeTrack(\.blur) { MoveKeyframe(4); CubicKeyframe(0, duration: 0.22) }
                }
                // One centred column, as wide as Droppy's, so every page reads the same way on any window size.
                .frame(maxWidth: selection == .settings ? 700 : 720)
                .padding(.horizontal, selection == .settings ? 0 : 24).padding(.top, selection == .settings ? 0 : 12).padding(.bottom, selection == .settings ? 0 : 24)
                // A page taller than the window scrolls inside itself; it must never make the split view (and so the window) taller.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()

            // The card has its own animation scope. An animation on the whole content (the old veil fade, then the card fade) made every
            // change that landed with it, such as a session ending, cross-fade the old and new screens over each other.
            ZStack(alignment: .topTrailing) {
                // Cards drop in from the corner they are pinned to and leave the same way.
                if c.checkIn != nil { CheckInCard(c: c).padding(Space.l).transition(.card(from: .topTrailing, reduce: reduceMotion)) }
                else if let s = c.surface, s.kind != "gate" { NudgeCard(c: c, kind: s.kind).padding(Space.l).transition(.card(from: .topTrailing, reduce: reduceMotion)) }
                else if c.rhythmPrompt != nil { RhythmCard(c: c).padding(Space.l).transition(.card(from: .topTrailing, reduce: reduceMotion)) }
            }
            .motion(Motion.out(0.24), value: c.rhythmPrompt)
            .motion(Motion.out(0.24), value: c.surface)
            .motion(Motion.out(0.24), value: c.checkIn)
            ZStack(alignment: .topTrailing) {
                if c.reentryOpen || c.manualNextStep {
                    ReentryCard(c: c).padding(Space.l).padding(.top, c.surface == nil && c.rhythmPrompt == nil ? 0 : 190)
                        .transition(.card(from: .topTrailing, reduce: reduceMotion))
                }
            }
            .motion(Motion.out(0.24), value: c.reentryOpen || c.manualNextStep)
        }
        .background { WindowBackdrop() }
    }
}

/// The one action at the right of the toolbar, as Droppy keeps one there: the running session (ring and clock), or Start.
struct SessionToolbarPill: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    var body: some View {
        if c.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let t = c.clockText()
                Button { c.requestSection(.today) } label: {
                    HStack(spacing: Space.xs) {
                        LiveRing(c.ringState, color: c.ringColor).frame(width: 14, height: 14)
                        Text(t).font(Tokens.fixed(.body, .semibold)).monospacedDigit()
                            .contentTransition(.numericText(countsDown: c.mode == .timed)).motion(Motion.out(0.3), value: t)
                    }
                    .padding(.horizontal, Space.xxs)
                }
                .help("\(c.taskName), \(c.presenceLabel)")
                .accessibilityLabel("\(c.taskName), \(c.presenceLabel), \(t)")
            }
        } else {
            Button { showStart = true } label: { Label("Start session", systemImage: "play.fill").labelStyle(.titleAndIcon) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}

/// The window's own surface: the system's plain window gray, as Droppy's pages sit on, so the grouped cards on top read as cards.
struct WindowBackdrop: View {
    var body: some View {
        if SnapshotMode.on { Tokens.window } else { Color(nsColor: .windowBackgroundColor).ignoresSafeArea() }
    }
}

/// NSVisualEffectView behind the window, the one way to get a translucent window body in SwiftUI on macOS 14.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = .behindWindow; v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}


/// The sidebar as a system source list, laid out like Droppy's: a search field, a header row for the session (where Droppy has the
/// account), the app's places, every settings page as its own row, and your projects under their own heading. Each has a colored tile.
struct SourceList: View {
    @Bindable var c: SessionController
    @Binding var item: SidebarItem?
    var selection: AppSection
    @State private var search = ""

    func shows(_ name: String) -> Bool { search.isEmpty || name.localizedCaseInsensitiveContains(search) }

    var body: some View {
        let places = [AppSection.today, .projects].filter { shows($0.rawValue) }
        let records = [AppSection.history, .insights, .review].filter { ($0 != .review || c.showsReview) && shows($0.rawValue) }
        let pages = SettingsPage.allCases.filter { shows($0.rawValue) }
        let projects = (c.store?.projects ?? []).filter { shows($0.name) }
        List(selection: $item) {
            SessionHeader(c: c).padding(.vertical, Space.xxs).selectionDisabled()
                .onTapGesture { item = .section(.today) }
            // A group with nothing matching the search is left out, heading and all.
            if !places.isEmpty { Section { ForEach(places) { s in row(s) } } }
            if !records.isEmpty { Section { ForEach(records) { s in row(s) } } }
            if !pages.isEmpty {
                Section {
                    ForEach(pages) { p in
                        Label { Text(p.rawValue) } icon: { IconTile(symbol: p.symbol, color: p.color) }.tag(SidebarItem.settings(p))
                    }
                }
            }
            if !projects.isEmpty {
                Section("Projects") {
                    ForEach(projects) { p in
                        Label { Text(p.name).lineLimit(1) } icon: { ProjectTile(name: p.name) }
                            // The project the running session belongs to.
                            .badge(c.isActive && c.projectId == p.id ? Text("Now").foregroundStyle(Tokens.accent) : nil)
                            .tag(SidebarItem.project(p.id))
                    }
                }
            }
            if places.isEmpty && records.isEmpty && pages.isEmpty && projects.isEmpty {
                Text("Nothing called \u{201C}\(search)\u{201D}").font(Tokens.text(.caption)).foregroundStyle(.secondary).selectionDisabled()
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: "Search")
    }

    func row(_ s: AppSection) -> some View {
        Label { Text(s.rawValue) } icon: { IconTile(symbol: s.tileSymbol, color: s.tileColor) }
            // Moments still waiting for an answer, as a count on Review. The tag goes last so the row stays selectable.
            .badge(s == .review ? (c.store?.openReviewCount ?? 0) : 0)
            .tag(SidebarItem.section(s))
    }
}

/// The top of the sidebar, where Droppy shows your account: here, the session. A big ring on a green disc, the task and how Focus
/// reads you, or a quiet "Focus" when nothing is running.
// The sidebar is window chrome: like the system's own rows beside it, it keeps the system size whatever the Text size setting.
struct SessionHeader: View {
    @Bindable var c: SessionController
    var body: some View {
        HStack(spacing: Space.s) {
            ZStack {
                Circle().fill(LinearGradient(colors: Tokens.Art.disc, startPoint: .top, endPoint: .bottom))
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    LiveRing(c.isActive ? c.ringState : .on, color: .white).frame(width: 20, height: 20)
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.isActive ? c.taskName : "Focus").font(Tokens.fixed(.body, .semibold)).lineLimit(1)
                Text(c.isActive ? c.presenceLabel : "No session running").font(Tokens.fixed(.caption2, .regular)).foregroundStyle(.secondary)
                    .contentTransition(.interpolate).motion(Motion.out(0.25), value: c.presenceLabel)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows Today")
    }
}

/// A project's tile: its first letter on a color picked from its name, so each project keeps the same color.
struct ProjectTile: View {
    var name: String
    static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .brown]
    var body: some View {
        let color = Self.palette[abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.palette.count]
        Text(String(name.prefix(1)).uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusTiny + 1, style: .continuous).fill(color.gradient))
            .accessibilityHidden(true)
    }
}

/// A white symbol on a small colored rounded square, the way System Settings (and Droppy) mark each section in the sidebar.
struct IconTile: View {
    var symbol: String
    var color: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: Tokens.radiusTiny + 1, style: .continuous).fill(color.gradient))
            .accessibilityHidden(true)
    }
}

extension AppSection {
    var tileSymbol: String {
        switch self {
        case .today: return "sun.max.fill"; case .projects: return "folder.fill"; case .history: return "clock.fill"
        case .insights: return "chart.bar.fill"; case .review: return "checklist"; case .settings: return "gearshape.fill"
        }
    }
    var tileColor: Color {
        switch self {
        case .today: return Tokens.Art.leaf; case .projects: return .blue; case .history: return .orange
        case .insights: return .purple; case .review: return .pink; case .settings: return .gray
        }
    }
}

/// What a section's entrance animates. Starts at rest, so the first screen at launch simply shows.
struct Entrance { var opacity = 1.0, rise = 0.0, blur = 0.0 }

struct Sidebar: View {
    @Bindable var c: SessionController
    @Binding var selection: AppSection
    @Namespace private var pill
    @State private var hovered: AppSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Space.s) { RingView(.on, color: Tokens.accent).frame(width: 20, height: 20); Text("Focus").font(Tokens.rounded(.callout, .semibold)) }
                .padding(.horizontal, Space.xs).padding(.top, Space.l).padding(.bottom, Space.m)
            ForEach(AppSection.allCases.filter { $0 != .settings && ($0 != .review || c.showsReview) }) { s in row(s) }
            Spacer()
            ZStack {
                if c.isActive {
                    SessionCard(c: c).padding(.bottom, Space.s)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)).combined(with: .scale(scale: 0.97, anchor: .bottom)))
                }
            }
            .motion(Motion.notchSettle, value: c.isActive)
            row(.settings)
        }
        .padding(.horizontal, Space.s).padding(.bottom, Space.s)
        .frame(width: 228)
        .motion(Motion.glide, value: selection)
    }

    /// The selection is one shape that slides between rows; the pointer gets a fainter one of its own.
    func row(_ s: AppSection) -> some View {
        Button { selection = s } label: {
            HStack(spacing: Space.s) {
                Image(systemName: s.symbol).frame(width: 18).foregroundStyle(selection == s ? Tokens.accent : Tokens.ink2)
                    .symbolEffect(.bounce, value: selection == s)
                Text(s.rawValue); Spacer()
            }
            .font(Tokens.text(.body, selection == s ? .semibold : .regular)).padding(.horizontal, Space.s).frame(height: 32)
            .background {
                ZStack {
                    if hovered == s && selection != s { RoundedRectangle(cornerRadius: Tokens.radiusRow).fill(Tokens.control.opacity(0.55)).transition(.opacity) }
                    if selection == s { RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(Tokens.accentSoft).matchedGeometryEffect(id: "selection", in: pill) }
                }
                .animation(Motion.hover, value: hovered)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selection == s ? .isSelected : [])
        .onHover { hovered = $0 ? s : (hovered == s ? nil : hovered) }
    }
}

/// The running session at the foot of the sidebar: a small copy of the notch, so the two always agree.
private struct SessionCard: View {
    @Bindable var c: SessionController
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let t = c.clockText()
            HStack(spacing: Space.s) {
                LiveRing(c.ringState, color: c.ringColor).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.taskName).font(Tokens.text(.body, .semibold)).lineLimit(1)
                    Text(c.presenceLabel).font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                        .contentTransition(.interpolate).motion(Motion.out(0.25), value: c.presenceLabel)
                }
                Spacer()
                Text(t).font(Tokens.rounded(.callout)).monospacedDigit()
                    .contentTransition(.numericText(countsDown: c.mode == .timed)).motion(Motion.out(0.3), value: t)
            }
        }
        .padding(Space.s).background(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).fill(Tokens.window.opacity(0.7)))
        .overlay { RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).strokeBorder(Tokens.line) }
    }
}

/// Screens designed in docs/design/app.html but not built yet. Honest placeholder, not a fake screen.
struct ComingNext: View {
    var section: AppSection
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(section.rawValue).font(Tokens.rounded(.title2, .semibold))
            Text("This screen is designed (see docs/design/app.html) but not built yet.").font(Tokens.text(.body)).foregroundStyle(Tokens.ink2)
        }
    }
}


/// A selectable row with a soft fill when selected or hovered (History uses it for its session list).
struct SidebarRow<Label: View>: View {
    var selected: Bool
    var small = false
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) { label }
                .font(Tokens.text(.body, selected ? .semibold : .regular))
                .padding(.horizontal, Space.s).padding(.vertical, Space.xs).frame(minHeight: small ? 30 : 32)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusRow, style: .continuous).fill(selected ? Tokens.control : (hover ? Tokens.control.opacity(0.5) : .clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

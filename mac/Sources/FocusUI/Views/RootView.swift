import SwiftUI
import AppKit
import FocusBrain

public enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today", projects = "Projects", history = "History", insights = "Insights", review = "Review", settings = "Settings"
    public var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: return "sun.max"; case .projects: return "folder"; case .history: return "clock"
        case .insights: return "chart.xyaxis.line"; case .review: return "flag"; case .settings: return "gearshape"
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
        if case .section(.today) = current, c.isActive { return c.taskName }
        switch current {
        case .section(let s): return s.rawValue
        case .settings(let p): return p.rawValue
        case .project(let id): return c.store?.project(id)?.name ?? "Project"
        }
    }

    public var body: some View {
        Group {
            if c.showsWelcome {
                // A new Mac: the welcome takes the whole window until it is finished or skipped.
                WelcomeView(c: c)
            } else if SnapshotMode.on {
                // ImageRenderer cannot draw a split view, so offscreen snapshots keep a plain sidebar and page.
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
                            ToolbarItemGroup(placement: .primaryAction) { SessionToolbar(c: c, showStart: $showStart) }
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

    /// Pages that draw the Focus panel beside themselves and so take the whole detail area.
    var ownsLayout: Bool {
        switch current { case .section(.today), .section(.history), .section(.review): return true; default: return false }
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
                // Today, History and Review lay out their own page and Focus panel across the whole window. Settings is one centred
                // form; Projects and Insights use the width up to a readable maximum.
                .frame(maxWidth: ownsLayout ? .infinity : (selection == .settings ? 700 : Tokens.contentWidth))
                .padding(.horizontal, ownsLayout || selection == .settings ? 0 : Space.xl).padding(.top, ownsLayout || selection == .settings ? 0 : Space.s).padding(.bottom, ownsLayout || selection == .settings ? 0 : Space.xl)
                // A page taller than the window scrolls inside itself; it must never make the split view (and so the window) taller.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()

            // The card has its own animation scope. An animation on the whole content (the old veil fade, then the card fade) made every
            // change that landed with it, such as a session ending, cross-fade the old and new screens over each other.
            ZStack(alignment: .topTrailing) {
                // Cards drop in from the corner they are pinned to and leave the same way. While the banner is up it carries the moment
                // (it sits over whichever window is in front, this one included), so the card would only repeat it.
                if c.banner != nil { EmptyView() }
                else if c.checkIn != nil { CheckInCard(c: c).padding(Space.l).transition(.card(from: .topTrailing, reduce: reduceMotion)) }
                else if let s = c.surface, s.kind != "gate" { NudgeCard(c: c, kind: s.kind).padding(Space.l).transition(.card(from: .topTrailing, reduce: reduceMotion)) }
                else if c.rhythmPrompt != nil { RhythmCard(c: c).padding(Space.l).transition(.card(from: .topTrailing, reduce: reduceMotion)) }
            }
            .motion(Motion.out(0.24), value: c.rhythmPrompt)
            .motion(Motion.out(0.24), value: c.surface)
            .motion(Motion.out(0.24), value: c.checkIn)
            .motion(Motion.out(0.24), value: c.banner)
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

/// The session's controls, always in reach at the right of the toolbar: the ring and clock, Pause or Resume, Break and End. Start when
/// nothing runs. Icons with labels for VoiceOver and tooltips, so the toolbar stays quiet.
struct SessionToolbar: View {
    @Bindable var c: SessionController
    @Binding var showStart: Bool
    var body: some View {
        if c.isActive {
            // Clocks that change every second do not roll their digits: a roll each second is motion that never ends, and in the glass
            // toolbar it cost about a fifth of a core and kept memory climbing (measured on the demo session, 2026-10-16).
            TimelineView(.everySecond) { _ in
                let t = c.clockText()
                Button { c.requestSection(.today) } label: {
                    HStack(spacing: Space.xs) {
                        LiveRing(c.ringState, color: c.ringColor).frame(width: 14, height: 14)
                        Text(t).font(Tokens.fixed(.body, .semibold)).monospacedDigit()
                    }
                    .padding(.horizontal, Space.xxs)
                }
                .help("\(c.taskName), \(c.presenceLabel)")
                .accessibilityLabel("\(c.taskName), \(c.presenceLabel), \(t)")
            }
            Button { c.act(c.isPaused ? .resume : .pause) } label: {
                Label(c.isPaused ? "Resume" : "Pause", systemImage: c.isPaused ? "play.fill" : "pause.fill").contentTransition(.symbolEffect(.replace))
            }
            .help(c.isPaused ? "Resume" : "Pause")
            Menu {
                ForEach([5, 10, 15], id: \.self) { m in Button("\(m) minute break") { c.act(.breakTime, minutes: m) } }
            } label: { Label("Break", systemImage: "cup.and.saucer") }
            .help("Take a break")
            Button { c.end() } label: { Label("End", systemImage: "stop.fill") }.help("End the session")
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
    @State private var settingsOpen = true

    func shows(_ name: String) -> Bool { search.isEmpty || name.localizedCaseInsensitiveContains(search) }

    var body: some View {
        let places = [AppSection.today, .projects].filter { shows($0.rawValue) }
        let records = [AppSection.history, .insights, .review].filter { ($0 != .review || c.showsReview) && shows($0.rawValue) }
        let pages = SettingsPage.allCases.filter { shows($0.rawValue) }
        let projects = (c.store?.projects ?? []).filter { shows($0.name) }
        List(selection: $item) {
            // A group with nothing matching the search is left out, heading and all.
            if !places.isEmpty { Section { ForEach(places) { s in row(s) } } }
            if !records.isEmpty { Section { ForEach(records) { s in row(s) } } }
            if !projects.isEmpty {
                Section("Projects") {
                    ForEach(projects) { p in
                        let now = c.isActive && c.projectId == p.id
                        Label { Text(p.name).lineLimit(1) } icon: { ProjectDot(now: now) }
                            // The project the running session belongs to.
                            .badge(now ? Text("Now").foregroundStyle(Tokens.accent) : nil)
                            .tag(SidebarItem.project(p.id))
                    }
                }
            }
            if !pages.isEmpty {
                // Every settings page keeps its own row; the group folds away when you do not need it.
                Section("Settings", isExpanded: $settingsOpen) {
                    ForEach(pages) { p in Label(p.rawValue, systemImage: p.symbol).tag(SidebarItem.settings(p)) }
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
        Label(s.rawValue, systemImage: s.symbol)
            // Moments still waiting for an answer, as a count on Review. The tag goes last so the row stays selectable.
            .badge(s == .review ? (c.store?.openReviewCount ?? 0) : 0)
            .tag(SidebarItem.section(s))
    }
}

/// A project in the sidebar: a small ring, filled green for the project the running session belongs to.
struct ProjectDot: View {
    var now: Bool
    var body: some View {
        Circle().strokeBorder(now ? Tokens.accent : Tokens.ink2.opacity(0.6), lineWidth: 1.5)
            .background(Circle().fill(now ? Tokens.accent : .clear).padding(3))
            .frame(width: 12, height: 12).accessibilityHidden(true)
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
        TimelineView(.everySecond) { _ in
            let t = c.clockText()
            // The task gets the card's whole width (two lines if it needs them); the clock sits with the state underneath,
            // where it used to squeeze even a short task name down to a few letters.
            HStack(alignment: .center, spacing: Space.s) {
                LiveRing(c.ringState, color: c.ringColor).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.taskName).font(Tokens.text(.body, .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.xxs) {
                        Text(c.presenceLabel).contentTransition(.interpolate).motion(Motion.out(0.25), value: c.presenceLabel)
                        Text("\u{00B7}")
                        Text(t).monospacedDigit()
                    }
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
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

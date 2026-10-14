import SwiftUI
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

public struct RootView: View {
    @Bindable var c: SessionController
    @State var selection: AppSection
    @State private var showStart = false
    /// The project the Projects screen shows. The sidebar's project list sets it.
    @State private var project: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(controller: SessionController, selection: AppSection = .today) { self.c = controller; self._selection = State(initialValue: selection) }

    public var body: some View {
        HStack(spacing: 0) {
            Sidebar(c: c, selection: $selection, project: $project)
            Divider().overlay(Tokens.line)
            ZStack(alignment: .topTrailing) {
                Group {
                    switch selection {
                    case .today: TodayView(c: c, showStart: $showStart)
                    case .projects: if let st = c.store { ProjectsView(c: c, store: st, selected: $project) } else { ComingNext(section: selection) }
                    case .history: if let st = c.store { HistoryView(store: st) } else { ComingNext(section: selection) }
                    case .review where !c.showsReview: TodayView(c: c, showStart: $showStart)
                    case .review: if let st = c.store { ReviewView(c: c, store: st) } else { ComingNext(section: selection) }
                    case .insights: if let st = c.store { InsightsView(c: c, store: st) } else { ComingNext(section: selection) }
                    case .settings: if let st = c.store { SettingsView(c: c, store: st) } else { ComingNext(section: selection) }
                    default: ComingNext(section: selection)
                    }
                }
                .padding(.horizontal, 32).padding(.top, 22).padding(.bottom, 26)
                .frame(maxWidth: Tokens.contentWidth, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Tokens.window)

                // The card has its own animation scope. An animation on the whole content (the old veil fade, then the card fade) made every
                // change that landed with it, such as a session ending, cross-fade the old and new screens over each other.
                ZStack(alignment: .topTrailing) {
                    if c.checkIn != nil { CheckInCard(c: c).padding(18).transition(.opacity) }
                    else if let s = c.surface, s.kind != "gate" { NudgeCard(c: c, kind: s.kind).padding(18).transition(.opacity) }
                    else if c.rhythmPrompt != nil { RhythmCard(c: c).padding(18).transition(.opacity) }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: c.rhythmPrompt)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: c.surface)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: c.checkIn)
                if c.reentryOpen || c.manualNextStep { ReentryCard(c: c).padding(18).padding(.top, c.surface == nil && c.rhythmPrompt == nil ? 0 : 190) }
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(Tokens.window)
        .foregroundStyle(Tokens.ink)
        .onChange(of: c.sectionRequest?.serial) { _, _ in if let r = c.sectionRequest { selection = r.section } }
        .onChange(of: c.startRequests) { _, _ in if !c.isActive { selection = .today; showStart = true } }
        .sheet(isPresented: $showStart) { StartSheet(controller: c, isPresented: $showStart) }
    }
}

struct Sidebar: View {
    @Bindable var c: SessionController
    @Binding var selection: AppSection
    @Binding var project: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) { RingView(.on, color: Tokens.accent).frame(width: 20, height: 20); Text("Focus").font(Tokens.rounded(16, .semibold)) }
                .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 18)
                .accessibilityElement(children: .combine)
            ForEach(AppSection.allCases.filter { $0 != .settings && ($0 != .review || c.showsReview) }) { s in row(s) }
            if let projects = c.store?.projects, !projects.isEmpty {
                Text("Projects").font(Tokens.text(12, .semibold)).foregroundStyle(Tokens.ink2)
                    .padding(.horizontal, 10).padding(.top, 22).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                ForEach(projects.prefix(6)) { p in projectRow(p) }
            }
            Spacer(minLength: 12)
            if c.isActive { liveCard }
            row(.settings)
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .frame(width: 236).background(Tokens.sidebar)
    }

    /// The running session, one click from any screen.
    var liveCard: some View {
        Button { selection = .today } label: {
            HStack(spacing: 10) {
                RingView(c.ringState, color: c.ringColor).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.taskName).font(Tokens.text(13, .semibold)).lineLimit(1)
                    Text(c.presenceLabel).font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
                }
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { _ in Text(c.clockText()).font(Tokens.rounded(14, .semibold)).monospacedDigit() }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .modifier(CardSurface(radius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).padding(.bottom, 8)
        .accessibilityLabel("Session: \(c.taskName), \(c.presenceLabel). Open Today.")
    }

    func row(_ s: AppSection) -> some View {
        let badge = s == .review ? (c.store?.openReviewCount ?? 0) : 0
        return SidebarRow(selected: selection == s, action: { selection = s }) {
            Image(systemName: s.symbol).font(.system(size: 13.5)).frame(width: 18)
                .foregroundStyle(selection == s ? Tokens.accent : Tokens.ink2)
            Text(s.rawValue)
            Spacer()
            if badge > 0 {
                Text("\(badge)").font(Tokens.rounded(11.5, .semibold)).foregroundStyle(Tokens.ink2).monospacedDigit()
                    .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 18).background(Capsule().fill(Tokens.control))
                    .accessibilityLabel("\(badge) to review")
            }
        }
    }

    func projectRow(_ p: Project) -> some View {
        let live = c.isActive && c.projectId == p.id
        let on = selection == .projects && project == p.id
        // The Projects row above already carries the selection fill, so the open project is marked by its ring and weight alone.
        return SidebarRow(selected: false, small: true, action: { project = p.id; selection = .projects }) {
            Group {
                if live { RingView(c.ringState, color: Tokens.accent) }
                else { Circle().strokeBorder(on ? Tokens.accent : Tokens.ink2.opacity(0.7), lineWidth: on ? 2.5 : 1.5) }
            }
            .frame(width: 11, height: 11).frame(width: 18)
            Text(p.name).lineLimit(1).fontWeight(on ? .semibold : .regular)
            Spacer(minLength: 4)
            if live { Text("Now").font(Tokens.text(11.5, .medium)).foregroundStyle(Tokens.accent) }
        }
    }
}

/// One sidebar row: a soft fill when selected or hovered, nothing otherwise.
struct SidebarRow<Label: View>: View {
    var selected: Bool
    var small = false
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { label }
                .font(Tokens.text(small ? 13 : 13.5, selected ? .semibold : .regular))
                .padding(.horizontal, 10).frame(height: small ? 30 : 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Tokens.control : (hover ? Tokens.control.opacity(0.5) : .clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Screens designed in docs/design/app.html but not built yet. Honest placeholder, not a fake screen.
struct ComingNext: View {
    var section: AppSection
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.rawValue).font(Tokens.rounded(26, .semibold))
            Text("This screen is designed (see docs/design/app.html) but not built yet.").font(Tokens.text(13.5)).foregroundStyle(Tokens.ink2)
        }
    }
}

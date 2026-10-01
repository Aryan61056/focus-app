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

    public init(controller: SessionController, selection: AppSection = .today) { self.c = controller; self._selection = State(initialValue: selection) }

    public var body: some View {
        HStack(spacing: 0) {
            Sidebar(c: c, selection: $selection)
            Divider().overlay(Tokens.line)
            ZStack(alignment: .topTrailing) {
                Group {
                    switch selection {
                    case .today: TodayView(c: c, showStart: $showStart)
                    case .projects: if let st = c.store { ProjectsView(c: c, store: st) } else { ComingNext(section: selection) }
                    case .history: if let st = c.store { HistoryView(store: st) } else { ComingNext(section: selection) }
                    case .review: if let st = c.store { ReviewView(c: c, store: st) } else { ComingNext(section: selection) }
                    case .settings: if let st = c.store { SettingsView(c: c, store: st) } else { ComingNext(section: selection) }
                    default: ComingNext(section: selection)
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Tokens.window)
                .saturation(1 - Double(c.veilTarget) / 100)
                .animation(.linear(duration: Double(c.veilDuration)), value: c.veilTarget)

                if let s = c.surface, s.kind != "gate" { NudgeCard(c: c, kind: s.kind).padding(18).transition(.opacity) }
                if c.reentryOpen { ReentryCard(c: c).padding(18).padding(.top, c.surface == nil ? 0 : 190) }
                if let s = c.surface, s.kind == "gate" { GateOverlay(c: c) }
            }
            .animation(.easeOut(duration: 0.2), value: c.surface)
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(Tokens.window)
        .foregroundStyle(Tokens.ink)
        .sheet(isPresented: $showStart) { StartSheet(controller: c, isPresented: $showStart) }
    }
}

struct Sidebar: View {
    @Bindable var c: SessionController
    @Binding var selection: AppSection
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) { RingView(.on, color: Tokens.accent).frame(width: 20, height: 20); Text("Focus").font(Tokens.rounded(15, .semibold)) }
                .padding(.horizontal, 8).padding(.top, 18).padding(.bottom, 16)
            ForEach(AppSection.allCases.filter { $0 != .settings }) { s in row(s) }
            Spacer()
            if c.isActive {
                HStack(spacing: 10) {
                    RingView(c.ringState, color: c.ringColor).frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.taskName).font(Tokens.text(13, .semibold)).lineLimit(1)
                        Text(c.presenceLabel).font(Tokens.text(12)).foregroundStyle(Tokens.ink2)
                    }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { _ in Text(c.clockText()).font(Tokens.rounded(14)).monospacedDigit() }
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Tokens.window))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Tokens.line) }.padding(.bottom, 10)
            }
            row(.settings)
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .frame(width: 236).background(Tokens.sidebar)
    }

    func row(_ s: AppSection) -> some View {
        Button { selection = s } label: {
            HStack(spacing: 10) { Image(systemName: s.symbol).frame(width: 18); Text(s.rawValue); Spacer() }
                .font(Tokens.text(13.5, selection == s ? .semibold : .regular)).padding(.horizontal, 10).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(selection == s ? Tokens.control : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selection == s ? .isSelected : [])
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

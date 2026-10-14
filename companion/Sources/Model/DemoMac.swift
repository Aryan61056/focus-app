import Foundation
import FocusLinkNet

/// A pretend Mac, so the app can be explored (and demonstrated) without one. It follows the same rules the real Mac sends:
/// state only on change, a drift that the Mac recovers from, and a session that is saved to Insights when it ends.
@MainActor final class DemoMac {
    var onState: ((SessionState) -> Void)?
    var onInsights: ((Insights) -> Void)?
    var onResult: ((CommandResult) -> Void)?

    private var state = SessionState.idle
    private var elapsed = 0.0
    private var phaseAge = 0.0
    private var onTaskTotal = 0.0
    private var drifts = 0
    private var startedAt = Date()
    private var ticker: Task<Void, Never>?
    private var recent: [Insights.Digest] = DemoMac.sampleRecent()

    func connect() {
        onState?(state)
        onInsights?(insights())
    }

    func disconnect() { ticker?.cancel(); ticker = nil }

    func handle(_ c: Command) {
        switch c {
        case .start(let task, let minutes):
            guard !state.isActive else { return onResult?(.refused(reason: "A session is already running.")) ?? () }
            elapsed = 0; phaseAge = 0; onTaskTotal = 0; drifts = 0; startedAt = Date()
            let timed = minutes != nil, total = Double((minutes ?? 0) * 60)
            state = SessionState(sessionID: UUID(), phase: .onTask, task: task, timed: timed, clockSeconds: timed ? total : 0, clockRunning: true, totalSeconds: total)
            publish(); runTicker()
        case .pause: guard state.isActive, state.phase != .paused else { return }; freeze(.paused)
        case .takeBreak: guard state.isActive else { return }; freeze(.onBreak)
        case .resume:
            guard state.phase == .paused || state.phase == .onBreak else { return }
            state.phase = .onTask; state.clockRunning = true; phaseAge = 0; publish()
        case .backToTask:
            guard state.phase == .drifting else { return }
            state.phase = .recovering; state.driftStep = 0; state.offTopicRunning = false; state.note = nil; phaseAge = 0; publish()
        case .extend(let m):
            guard state.timed else { return }
            state.totalSeconds += Double(m * 60); state.clockSeconds = remaining() + Double(m * 60); publish()
        case .end: end()
        }
        onResult?(.done)
    }

    private func remaining() -> Double { state.timed ? max(0, state.totalSeconds - elapsed) : elapsed }

    private func freeze(_ phase: SessionState.Phase) {
        state.phase = phase; state.clockRunning = false; state.clockSeconds = remaining(); state.offTopicRunning = false; state.note = nil; publish()
    }

    private func publish() { state.clockSeconds = remaining(); onState?(state) }

    private func runTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    /// A tiny script: 25 s on task, a drift that climbs a step after 15 s, and a recovery, on repeat.
    private func tick() {
        guard state.isActive, state.clockRunning else { return }
        elapsed += 1; phaseAge += 1
        if state.phase == .onTask || state.phase == .recovering { onTaskTotal += 1 }
        if state.timed, elapsed >= state.totalSeconds { return end() }
        switch state.phase {
        case .onTask where phaseAge >= 25:
            drifts += 1; state.phase = .unsure; phaseAge = 0; publish()
        case .unsure where phaseAge >= 6:
            state.phase = .drifting; state.offTopicSeconds = 0; state.offTopicRunning = true; phaseAge = 0; publish()
        case .drifting where phaseAge >= 15 && state.driftStep == 0:
            state.driftStep = 1; state.note = "Are you working on \(state.task)?"; publish()
        case .recovering where phaseAge >= 5:
            state.phase = .onTask; state.note = "Back in 5 s"; phaseAge = 0; publish()
        case .onTask where state.note != nil && phaseAge >= 6:
            state.note = nil; publish()
        default: break
        }
    }

    private func end() {
        ticker?.cancel(); ticker = nil
        let digest = Insights.Digest(id: UUID(), task: state.task, start: startedAt, end: Date(), onTaskSeconds: onTaskTotal, activeSeconds: elapsed, drifts: drifts, practice: false)
        if elapsed >= 5 { recent.insert(digest, at: 0) }
        state = .idle
        onState?(state); onInsights?(insights())
    }

    // MARK: sample insights
    func insights() -> Insights {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        let sample: [Double] = [3200, 0, 5400, 4100, 0, 2600, 0]
        var week: [Insights.Day] = []
        for (i, s) in sample.enumerated() {
            let day = cal.date(byAdding: .day, value: i - 6, to: today)!
            let isToday = i == 6
            let todays = recent.filter { cal.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.onTaskSeconds }
            let secs = s + todays
            week.append(.init(day: day, onTaskSeconds: secs, mark: secs >= 1200 ? .focus : (isToday ? .pending : (i == 1 || i == 4 ? .rest : .none))))
        }
        let todayTotal = week.last?.onTaskSeconds ?? 0
        return Insights(todayOnTaskSeconds: todayTotal, goalMinutes: 90, streak: 3, bestStreak: 6, restDaysUsed: 1, week: week,
                        recent: Array(recent.prefix(8)), bestStretchSeconds: 1860, returnSeconds: 38, returnCount: 7)
    }

    static func sampleRecent() -> [Insights.Digest] {
        let now = Date()
        func d(_ task: String, minutesAgo: Double, length: Double, drifts: Int) -> Insights.Digest {
            Insights.Digest(id: UUID(), task: task, start: now.addingTimeInterval(-minutesAgo * 60 - length * 60), end: now.addingTimeInterval(-minutesAgo * 60),
                            onTaskSeconds: length * 60 * 0.9, activeSeconds: length * 60, drifts: drifts, practice: false)
        }
        return [d("Calc homework", minutesAgo: 180, length: 50, drifts: 1), d("Essay outline", minutesAgo: 1500, length: 25, drifts: 0),
                d("Chem lab report", minutesAgo: 1700, length: 90, drifts: 3), d("Calc homework", minutesAgo: 3000, length: 45, drifts: 2)]
    }
}

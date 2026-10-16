import Foundation
import Observation
import FocusBrain
import FocusJudge

public enum StartLength: String, CaseIterable, Identifiable, Sendable {
    case five, twentyFive, until, open
    public var id: Self { self }
    public var title: String { switch self { case .five: return "5 min"; case .twentyFive: return "25"; case .until: return "Until…"; case .open: return "Open" } }
}

/// One draft shared by Today, the start sheet and quick project starts. Never persisted.
@MainActor @Observable public final class StartDraft {
    public var task = ""
    public var length: StartLength = .open
    public var until = Date().addingTimeInterval(25 * 60)
    public var done = ""
    public var extras = false
    var accepted: Sharpened?
    public init() {}
    static func nextClockTime(_ time: Date, after now: Date, calendar: Calendar = .current) -> Date? {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.nextDate(after: now, matching: DateComponents(hour: parts.hour, minute: parts.minute, second: 0), matchingPolicy: .nextTime)
    }
    func plan(now: Date, calendar: Calendar = .current, text: String? = nil) -> StartPlan? {
        let parsed = StartSheet.parse(text ?? task)
        if let minutes = parsed.minutes { return StartPlan(mode: .timed, duration: Double(minutes * 60), deadline: nil, five: minutes == 5) }
        switch length {
        case .five: return StartPlan(mode: .timed, duration: 300, deadline: nil, five: true)
        case .twentyFive: return StartPlan(mode: .timed, duration: 1500, deadline: nil, five: false)
        case .open: return StartPlan(mode: .open, duration: nil, deadline: nil, five: false)
        case .until:
            guard let end = Self.nextClockTime(until, after: now, calendar: calendar) else { return nil }
            return StartPlan(mode: .timed, duration: end.timeIntervalSince(now), deadline: end, five: false)
        }
    }
}
struct StartPlan { var mode: Mode; var duration: Double?; var deadline: Date?; var five: Bool }

extension SessionController {
    @discardableResult public func startWithDraft(task explicitTask: String? = nil, projectId explicitID: UUID? = nil, autoTick: Bool = true) -> Bool {
        guard !isActive, let plan = startDraft.plan(now: date(), text: explicitTask) else { return false }
        let parsed = StartSheet.parse(explicitTask ?? startDraft.task)
        let last = StartSheet.lastProject(store)
        let task = parsed.task.isEmpty ? (last?.name ?? "") : parsed.task
        guard !task.isEmpty else { return false }
        let project = store?.project(explicitID) ?? store?.projects.first { $0.name.caseInsensitiveCompare(task) == .orderedSame }
        let goal = (explicitTask == nil ? startDraft.done : (project?.carriedGoal ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard goal.count <= 240 else { return false }
        if let accepted = startDraft.accepted, accepted.task == task { saveContextIfEmpty(task: task, context: accepted.counts) }
        // A clock deadline is scheduled by the controller with SessionEnd. The pure brain needs no new event or timer semantics.
        begin(task: task, mode: plan.mode, duration: plan.duration, projectId: project?.id ?? explicitID ?? (parsed.task.isEmpty ? last?.id : nil), autoTick: autoTick,
              deadline: plan.deadline, goal: goal.isEmpty ? project?.carriedGoal : goal, fiveMinuteStart: plan.five)
        prefs.introSeen = true; startDraft.task = ""; startDraft.done = ""; startDraft.accepted = nil
        return isActive
    }
    public func resolveSessionGoal(done: Bool) {
        guard !isActive, !sessionGoal.isEmpty, let finishedRecordID else { return }
        store?.resolveGoal(for: finishedRecordID, done: done)
        goalDisposition = done ? "done" : "carried"
        startDraft.done = done ? "" : sessionGoal
    }
    public func keepGoing() {
        guard shortSessionOffer, !isActive else { return }
        if !sessionGoal.isEmpty && goalDisposition == nil { resolveSessionGoal(done: false) }
        let goal = goalDisposition == "done" ? nil : sessionGoal
        begin(task: taskName, projectId: projectId, autoTick: true, goal: goal)
    }
    public func finishFiveMinutes() { shortSessionOffer = false }
}

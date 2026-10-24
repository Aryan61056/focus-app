import Foundation
import Observation
import FocusBrain
import FocusJudge

/// How a session is bounded: a number of minutes (the slider), a clock time, or nothing (Open).
public enum StartLength: String, Sendable {
    case minutes, until, open
}

/// The stops on the length slider. Finer at the short end, where five minutes matters, and wider further out, where it does not; the last
/// stop is Open (no timer). The slider moves one stop at a time, so there is no way to land on an odd number.
public enum LengthStops {
    public static let minutes = [5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 90, 120, 150, 180]
    /// The index of the last stop, which means "no timer".
    public static var open: Int { minutes.count }
    /// The stop closest to `m` minutes.
    public static func nearest(_ m: Int) -> Int {
        minutes.indices.min { abs(minutes[$0] - m) < abs(minutes[$1] - m) } ?? 0
    }
    /// "25 min", "1 hour", "1 h 30 min".
    public static func describe(minutes m: Int) -> String {
        if m < 60 { return "\(m) min" }
        if m % 60 == 0 { return m == 60 ? "1 hour" : "\(m / 60) hours" }
        return "\(m / 60) h \(m % 60) min"
    }
    /// The length this person usually picks, once they have shown a habit: at least three of their last ten sessions timed and at least
    /// ten minutes long, and at least half of those ten timed. The middle of those lengths, moved to the nearest stop. Nil otherwise, so
    /// anyone who mostly runs Open sessions keeps Open as the starting point.
    public static func usualMinutes(from sessions: [SessionRecord]) -> Int? {
        let recent = Array(sessions.sorted { $0.start > $1.start }.prefix(10))
        let timed = recent.filter { $0.timed && $0.activeSeconds >= 600 }
        guard timed.count >= 3, timed.count * 2 >= recent.count else { return nil }
        let lengths = timed.map { $0.activeSeconds / 60 }.sorted()
        let middle = lengths.count % 2 == 1 ? lengths[lengths.count / 2] : (lengths[lengths.count / 2 - 1] + lengths[lengths.count / 2]) / 2
        return minutes[nearest(Int(middle.rounded()))]
    }
}

/// One draft shared by Today, the start sheet and quick project starts. Never persisted.
@MainActor @Observable public final class StartDraft {
    public var task = ""
    public var length: StartLength = .open
    /// Used when `length` is `.minutes`.
    public var minutes = 25
    /// Set once the person moves the slider, so Hushd stops suggesting a length of its own.
    public var lengthTouched = false
    /// The suggested length that was applied for them, if any, so the form can say it is their usual.
    public var usualMinutes: Int?
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
        case .minutes: return StartPlan(mode: .timed, duration: Double(minutes * 60), deadline: nil, five: minutes == 5)
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

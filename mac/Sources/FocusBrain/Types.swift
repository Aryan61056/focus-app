// The focus brain's public vocabulary: events in, effects out. See docs/BRAIN-SPEC.md.
// No Foundation, no clock, no randomness: the same event sequence gives the same effects everywhere.

public enum Mode: String, Sendable { case timed = "Timed", open = "Open" }
public enum Preset: String, Sendable { case gentle = "Gentle", standard = "Standard", strict = "Strict" }
public enum JudgmentLabel: String, Sendable { case onTask = "on_task", unsure, offTask = "off_task" }
public enum JudgmentSource: String, Sendable { case model, unchanged, rule }
public enum JudgmentFlag: String, Sendable { case none, refusal, error }

public enum UserAction: String, Sendable {
    case pause, resume, snooze, extend, end, dismiss, panic
    case breakTime = "break"
    case thatWasFine = "that_was_fine", markRelevant = "mark_relevant", ignoreWindow = "ignore_window"
    case markOffTask = "mark_off_task", backToTask = "back_to_task", nextStep = "next_step"
}

public struct SessionConfig: Sendable {
    public var sessionId = "s", taskId = "task"
    public var mode = Mode.open
    public var durationSeconds: Double?
    public var preset = Preset.standard
    public var shadow = false
    public var reentryPrompt: Bool?
    public var sound = false
    public init() {}
}

public struct JudgmentInput: Sendable {
    public var requestId: Int?
    public var observedAt: Double
    public var windowKey: String
    public var contentKey: String
    public var label: JudgmentLabel
    public var strong = false
    public var source = JudgmentSource.model
    public var flag = JudgmentFlag.none
    public init(requestId: Int? = nil, observedAt: Double, windowKey: String, contentKey: String, label: JudgmentLabel) {
        self.requestId = requestId; self.observedAt = observedAt; self.windowKey = windowKey
        self.contentKey = contentKey; self.label = label
    }
}

public struct WindowChangeInput: Sendable {
    public var windowKey: String
    public var siteKey: String
    public var ruleLabel: JudgmentLabel?   // stage 1 project rule: on_task or off_task; unsure means "never judged" (neutral, no model call)
    public init(windowKey: String, siteKey: String? = nil, ruleLabel: JudgmentLabel? = nil) {
        self.windowKey = windowKey; self.siteKey = siteKey ?? windowKey; self.ruleLabel = ruleLabel
    }
}

public enum Event: Sendable {
    case sessionStart(SessionConfig)
    case sessionEnd
    case tick
    case judgment(JudgmentInput)
    case windowChange(WindowChangeInput)
    case userAction(UserAction, minutes: Int?)
    case idle, active, sleep, wake
    case meetingStart, meetingEnd
    case sensitiveEntered, sensitiveLeft
    case powerChange(constrained: Bool, critical: Bool)
}

public enum Effect: Equatable, Sendable {
    case withdraw(what: String)
    case beacon(state: String, reason: String?)
    case veil(from: Int, to: Int, seconds: Int)
    case offTopicTimer(seconds: Double, running: Bool, visible: Bool)
    case clock(seconds: Double, running: Bool)
    case interrupt(kind: String, severity: Int, block: Int, windowKey: String)
    case reentryPrompt(block: Int)
    case wrapUp(remaining: Double)
    case askResume(reason: String)
    case shadowMark(block: Int, kind: String, windowKey: String)
    case learnRule(scope: String, kind: String, keyType: String, key: String)
    case bringBack(windowKey: String?)
    case requestJudgment(id: Int, reason: String, urgency: String, windowKey: String, allowVision: Bool)
    case cue
    case summary(activeSeconds: Double, offTopicSeconds: Double, unsureSeconds: Double, drifts: Int, interrupts: Int, refusals: Int)

    /// Position in the fixed emission order of spec section 5.2.
    var order: Int {
        switch self {
        case .withdraw: return 1
        case .beacon: return 2
        case .veil: return 3
        case .offTopicTimer: return 4
        case .clock: return 5
        case .interrupt: return 6
        case .reentryPrompt: return 7
        case .wrapUp: return 8
        case .askResume: return 9
        case .shadowMark: return 10
        case .learnRule: return 11
        case .bringBack: return 12
        case .requestJudgment: return 13
        case .cue: return 14
        case .summary: return 15
        }
    }
}

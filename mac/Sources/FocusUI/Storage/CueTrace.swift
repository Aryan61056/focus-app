import Foundation

// "What brings you back": for each time you drifted and came back, which of Hushd's cues had appeared most recently, and how long after it
// appeared you were back. Counts and kinds only (no window, app, site or text), saved with the session like the other counts. It reports what
// was on screen, not what caused the return, and it decides nothing: no cue is chosen or skipped because of it.

public enum CueKind: String, Codable, CaseIterable, Sendable {
    case banner, card, gray, fog, edges, checkIn, pauseScreen, hidden

    public var label: String {
        switch self {
        case .banner: return "Heads-up banner"; case .card: return "Nudge card"; case .gray: return "Gray screen"; case .fog: return "Fog"; case .edges: return "Closing edges"
        case .checkIn: return "Check-in"; case .pauseScreen: return "Pause screen"; case .hidden: return "App hidden"
        }
    }
}

/// One return: the cue that had appeared last (nil: you were back before any cue) and the seconds from then until you were back on task.
public struct ReturnCue: Codable, Equatable, Sendable {
    public var cue: CueKind?
    public var seconds: Double
    public init(cue: CueKind?, seconds: Double) { self.cue = cue; self.seconds = seconds }
}

/// Watches which cues are on screen while you are away and remembers when each one appeared.
public struct CueTrace: Equatable, Sendable {
    private var appeared: [CueKind: Double] = [:]
    private var showing: Set<CueKind> = []
    public init() {}

    public mutating func reset() { appeared = [:]; showing = [] }

    /// Call every second while away with the cues on screen now. A cue is "new" when it was not showing a second ago.
    public mutating func observe(_ visible: Set<CueKind>, at t: Double) {
        for k in visible where !showing.contains(k) { appeared[k] = t }
        showing = visible
    }

    /// How the return that happened at `returnedAt` went: the latest cue that had appeared by then, and the seconds since. With none, the
    /// seconds are `sinceDrift` (how long you were away). Resets the trace.
    public mutating func finish(returnedAt: Double, sinceDrift: Double) -> ReturnCue {
        defer { reset() }
        if let latest = appeared.filter({ $0.value <= returnedAt }).max(by: { $0.value < $1.value }) {
            return ReturnCue(cue: latest.key, seconds: max(1, returnedAt - latest.value))
        }
        return ReturnCue(cue: nil, seconds: max(1, sinceDrift))
    }
}

extension Rewards {
    public struct CueResponse: Equatable, Sendable {
        public var cue: CueKind?
        public var count: Int
        public var median: Double
    }

    /// The typical time from a cue appearing to being back, per cue, for the last `days` days. A cue needs at least `minimum` returns to be shown.
    /// Fastest first. Practice sessions say nothing and are left out.
    public static func cueResponses(_ sessions: [SessionRecord], days: Int = 30, minimum: Int = 3, today: Date, calendar cal: Calendar = .current) -> [CueResponse] {
        let from = cal.date(byAdding: .day, value: -days, to: today)!
        var by: [String: [Double]] = [:]
        for s in sessions where counts(s) && s.start >= from {
            for r in s.returnCues ?? [] { by[r.cue?.rawValue ?? "", default: []].append(r.seconds) }
        }
        return by.compactMap { key, v -> CueResponse? in
            guard v.count >= minimum else { return nil }
            let sorted = v.sorted(), mid = sorted.count / 2
            let median = sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
            return CueResponse(cue: CueKind(rawValue: key), count: v.count, median: median)
        }.sorted { $0.median < $1.median }
    }
}

extension Rewards {
    /// Where in a session slips tend to start, in ten-minute steps (0 to 10 minutes in, 10 to 20, and so on; the last step is 50 and later).
    /// Minutes into the session only: no windows, no text. Shown only when there is enough to say something (a few sessions and slips),
    /// and a peak is named only when it holds a clear share, so a flat spread is left as a spread.
    public struct SlipTiming: Equatable, Sendable {
        public var buckets: [Int]        // slips per ten-minute step, 6 steps
        public var total: Int, sessions: Int
        /// The step with a clear share of all slips (at least 40 percent and at least 4 slips), if there is one.
        public var peak: Int? {
            guard let top = buckets.indices.max(by: { buckets[$0] < buckets[$1] }), buckets[top] >= 4, Double(buckets[top]) >= 0.4 * Double(total) else { return nil }
            return top
        }
        public static let stepMinutes = 10
        public static func label(_ step: Int) -> String { step >= 5 ? "50+" : "\(step * 10) to \((step + 1) * 10)" }
    }

    public static func slipTiming(_ sessions: [SessionRecord], days: Int = 30, today: Date, calendar cal: Calendar = .current) -> SlipTiming? {
        let from = cal.date(byAdding: .day, value: -days, to: today)!
        var buckets = [Int](repeating: 0, count: 6), used = 0
        for s in sessions where counts(s) && s.start >= from && s.activeSeconds >= 10 * 60 {
            var t = 0.0, away = false, slips = 0
            for seg in s.segments {
                if seg.kind == .off {
                    if !away { buckets[min(5, Int(t / 600))] += 1; slips += 1 }
                    away = true
                } else if seg.kind == .on { away = false }
                t += seg.seconds
            }
            if slips > 0 { used += 1 }
        }
        let total = buckets.reduce(0, +)
        guard used >= 4, total >= 8 else { return nil }
        return SlipTiming(buckets: buckets, total: total, sessions: used)
    }
}

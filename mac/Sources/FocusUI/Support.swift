import Foundation
import AppKit
import FocusJudge
import FocusBrain

/// The judge the app uses: Apple's on-device model when it is available, otherwise one that always says "unsure"
/// (so a Mac without Apple Intelligence never nudges, per CLAUDE.md principle 7).
public struct UnsureJudge: Judge {
    public init() {}
    public func reasonFirst(prompt: String) async -> Verdict { Verdict(label: .unsure, reason: "judge unavailable") }
    public func relation(prompt: String) async -> Verdict { Verdict(label: .unsure, reason: "judge unavailable") }
}

/// Whether the judge can run. Shown on Today so a Mac without Apple Intelligence does not just look broken.
public enum JudgeStatus: Equatable, Sendable {
    case unknown, ready
    case unavailable(String)

    /// Plain words for the reason macOS gives ("appleIntelligenceNotEnabled", "modelNotReady", ...).
    static func friendly(_ reason: String) -> String {
        let r = reason.lowercased()
        if r.contains("notenabled") { return "Apple Intelligence is turned off. Turn it on in System Settings, under Apple Intelligence and Siri." }
        if r.contains("noteligible") || r.contains("ineligible") { return "This Mac cannot run Apple's on-device model." }
        if r.contains("notready") { return "Apple's on-device model is still downloading or preparing. This can take a while after turning Apple Intelligence on." }
        return "Apple's on-device model is not available right now."
    }
}

public enum DefaultJudge {
    public static func status() -> JudgeStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch AppleJudge.availability {
            case .available: return .ready
            case .unavailable(let why): return .unavailable(JudgeStatus.friendly(why))
            }
        }
        #endif
        return .unavailable("Apple's on-device model needs macOS 26 or later.")
    }

    /// Checks on every call, so turning Apple Intelligence on (or the model finishing its download) takes effect without relaunching.
    public static func make() -> any Judge { AdaptiveJudge() }
}

public struct AdaptiveJudge: Judge {
    public init() {}
    private func current() -> any Judge {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = AppleJudge.availability { return AppleJudge() }
        #endif
        return UnsureJudge()
    }
    public func reasonFirst(prompt: String) async -> Verdict { await current().reasonFirst(prompt: prompt) }
    public func relation(prompt: String) async -> Verdict { await current().relation(prompt: prompt) }
}

public enum DefaultAssistant {
    public static func make() -> any Assistant { AdaptiveAssistant() }
}

/// Like AdaptiveJudge: checks on every call, so Apple Intelligence turning on takes effect without a relaunch.
public struct AdaptiveAssistant: Assistant {
    public init() {}
    private func current() -> any Assistant {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = AppleJudge.availability { return AppleAssistant() }
        #endif
        return NoAssistant()
    }
    public func sharpen(task: String, context: String) async -> Sharpened? { await current().sharpen(task: task, context: context) }
    public func recap(facts: String) async -> Recap? { await current().recap(facts: facts) }
    public func answer(question: String, facts: String) async -> String? { await current().answer(question: question, facts: facts) }
}

/// Deterministic judge for demos, snapshots and tests: a window whose prompt contains a marker gets that label.
public struct ScriptedJudge: Judge {
    public var markers: [(String, JudgmentLabelShim, String)]
    public init(markers: [(String, JudgmentLabelShim)]) { self.markers = markers.map { ($0.0, $0.1, "scripted") } }
    public init(readings: [(String, JudgmentLabelShim, String)]) { self.markers = readings }
    func verdict(_ prompt: String) -> Verdict {
        for (m, l, why) in markers where prompt.contains(m) { return Verdict(label: l.label, reason: why) }
        return Verdict(label: .unsure, reason: "scripted")
    }
    public func reasonFirst(prompt: String) async -> Verdict { verdict(prompt) }
    public func relation(prompt: String) async -> Verdict { verdict(prompt) }
}
public enum JudgmentLabelShim: Sendable {
    case on, off, unsure
    var label: Label { switch self { case .on: return .onTask; case .off: return .offTask; case .unsure: return .unsure } }
}

/// Feeds a scripted sequence of windows to the controller. Real window sensing is spike S2 and needs permissions.
@MainActor public final class DemoSenses {
    public struct Step { public var after: Double; public var window: WindowSnapshot
        public init(after: Double, window: WindowSnapshot) { self.after = after; self.window = window } }
    let controller: SessionController, script: [Step]
    var task: Task<Void, Never>?
    public init(controller: SessionController, script: [Step]) { self.controller = controller; self.script = script }
    public func start() {
        task = Task { [controller, script] in
            for s in script {
                try? await Task.sleep(nanoseconds: UInt64(s.after * 1_000_000_000))
                if Task.isCancelled { return }
                controller.windowChanged(s.window)
            }
        }
    }
    public func stop() { task?.cancel() }
}

/// Menu bar glyph drawn as a template image so the system tints it for light, dark and wallpaper.
public enum RingImage {
    public static func make(_ state: RingState, size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.set()
            let c = CGPoint(x: rect.midX, y: rect.midY), r = size * 6 / 18, lw = size * 2.25 / 18
            func ring(_ from: CGFloat, _ to: CGFloat) -> NSBezierPath {
                let p = NSBezierPath(); p.appendArc(withCenter: c, radius: r, startAngle: from, endAngle: to, clockwise: false)
                p.lineWidth = lw; p.lineCapStyle = .round; return p
            }
            switch state {
            case .on: ring(0, 360).stroke()
            case .unsure:
                let p = ring(0, 360); let circ = 2 * CGFloat.pi * r; p.setLineDash([circ * 2.4 / 37.7, circ * 2.4 / 37.7], count: 2, phase: 0); p.stroke()
            case .drift: ring(120, 120 + 281.5).stroke()
            case .paused:
                for x in [5.2, 10.0] { NSBezierPath(roundedRect: NSRect(x: size * x / 18, y: size * 4 / 18, width: size * 2.8 / 18, height: size * 10 / 18), xRadius: size * 1.4 / 18, yRadius: size * 1.4 / 18).fill() }
            case .breakTime:
                ring(0, 360).stroke(); NSBezierPath(ovalIn: NSRect(x: c.x - size * 1.9 / 18, y: c.y - size * 1.9 / 18, width: size * 3.8 / 18, height: size * 3.8 / 18)).fill()
            case .done:
                ring(0, 360).stroke()
                let t = NSBezierPath(); t.move(to: NSPoint(x: c.x - r * 0.42, y: c.y - r * 0.02)); t.line(to: NSPoint(x: c.x - r * 0.1, y: c.y - r * 0.36)); t.line(to: NSPoint(x: c.x + r * 0.46, y: c.y + r * 0.32))
                t.lineWidth = lw; t.lineCapStyle = .round; t.lineJoinStyle = .round; t.stroke()
            case .progress(let f): ring(90, 90 - 360 * CGFloat(max(0.02, min(1, f)))).stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

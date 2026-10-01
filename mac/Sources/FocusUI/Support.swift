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

public enum DefaultJudge {
    public static func make() -> any Judge {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = AppleJudge.availability { return AppleJudge() }
        #endif
        return UnsureJudge()
    }
}

/// Deterministic judge for demos, snapshots and tests: a window whose prompt contains a marker gets that label.
public struct ScriptedJudge: Judge {
    public var markers: [(String, JudgmentLabelShim)]
    public init(markers: [(String, JudgmentLabelShim)]) { self.markers = markers }
    func verdict(_ prompt: String) -> Verdict {
        for (m, l) in markers where prompt.contains(m) { return Verdict(label: l.label, reason: "scripted") }
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
            case .progress(let f): ring(90, 90 - 360 * CGFloat(max(0.02, min(1, f)))).stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

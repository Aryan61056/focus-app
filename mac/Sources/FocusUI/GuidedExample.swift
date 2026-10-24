import Foundation
import Observation
import FocusBrain

/// An isolated, replayable example. Its judge, clock, store and callbacks never touch the user's windows.
@MainActor @Observable
public final class GuidedExample {
    final class Clock { var seconds = 0.0 }
    public let controller: SessionController
    public private(set) var step = 0
    public private(set) var playing = false
    public private(set) var preparing = false
    @ObservationIgnored private let clock: Clock
    @ObservationIgnored private var rendering: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var playback: Task<Void, Never>?
    public static let titles = ["Start with your work", "Notice a detour", "A gentle way back", "Pick up where you left off"]
    public static let explanations = [
        "You set a task. Hushd compares a window with what you want to do.",
        "A short glance is not enough. Hushd waits for sustained evidence.",
        "The example nudge appears in your Mac notch. It names your task, never the detour.",
        "When your work returns, the nudge clears and the ring settles."
    ]

    public init() {
        let clock = Clock(); self.clock = clock
        let name = "focus-app.guided-example"
        UserDefaults.standard.removePersistentDomain(forName: name)
        let p = Preferences(defaults: UserDefaults(suiteName: name)!)
        p.matchTaskWords = false; p.checkRate = .normal; p.paceMatters = false
        p.aiHelp = false; p.escalate = false; p.headsUp = false; p.showProgress = false
        p.hapticTap = false; p.dockBounce = false; p.speakNudges = false; p.nudgeSound = false
        p.readScreen = false
        controller = SessionController(judge: ScriptedJudge(readings: [
            ("Example calculus", .on, "These worked integrals directly support your calculus task."),
            ("Example entertainment", .off, "This window does not help with your calculus task.")
        ]), store: DataStore(), prefs: p, now: { clock.seconds })
        controller.onBringBackToApp = { [weak self] _ in self?.select(3) }
        select(0)
    }

    public func select(_ value: Int) {
        guard (0...3).contains(value) else { return }
        pause(); prepare(value)
    }

    private func prepare(_ value: Int) {
        generation += 1
        let version = generation
        rendering?.cancel(); step = value; preparing = true
        rendering = Task { [weak self] in
            guard let self, !Task.isCancelled, self.generation == version else { return }
            self.controller.end()
            let origin = self.clock.seconds + 1
            self.clock.seconds = origin
            self.controller.windowChanged(WindowSnapshot(app: "Example notes", title: "Example calculus: integration by parts"))
            self.controller.begin(task: "Calc homework", preset: .standard, shadow: false)
            await self.advance(to: origin + 5)
            guard !Task.isCancelled, self.generation == version else { return }
            if value >= 1 {
                self.clock.seconds = origin + 6
                self.controller.windowChanged(WindowSnapshot(app: "Example browser", title: "Example entertainment feed"))
                await self.advance(to: origin + (value == 1 ? 40 : 85))
            }
            guard !Task.isCancelled, self.generation == version else { return }
            if value == 3 {
                self.clock.seconds = origin + 86
                self.controller.windowChanged(WindowSnapshot(app: "Example notes", title: "Example calculus: integration by parts"))
                await self.advance(to: origin + 108)
            }
            guard !Task.isCancelled, self.generation == version else { return }
            self.preparing = false
        }
    }

    private func advance(to target: Double) async {
        while clock.seconds < target && !Task.isCancelled {
            clock.seconds += 1; controller.tick()
            await controller.waitForJudgments()
            await Task.yield()
        }
    }

    public func waitUntilReady() async { await rendering?.value }
    public func pause() { playback?.cancel(); playback = nil; playing = false }
    public func autoplay() {
        pause()
        if step == 3 { prepare(0) }
        playing = true
        playback = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.waitUntilReady()
                do { try await Task.sleep(nanoseconds: UInt64([18, 24, 25, 18][self.step]) * 1_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                if self.step == 3 { self.playing = false; return }
                self.prepare(self.step + 1)
            }
        }
    }
    public func stop() { generation += 1; pause(); rendering?.cancel(); preparing = false; controller.end() }
}

extension SessionController {
    public func showExample() {
        guard !isActive, example == nil else { return }
        example = GuidedExample()
    }
    public func closeExample() { example?.stop(); example = nil }
}

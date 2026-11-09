import Foundation
import Observation

/// Updates for the copy people install: Hushd asks its release feed for a newer version once a day, downloads it quietly and offers
/// "Restart to update" between sessions. This is only the state the screens show; the network and the install belong to the app target
/// (SparkleUpdater.swift), which moves `state` as Sparkle reports. Never restarts by itself and never during a session.
@MainActor @Observable
public final class ReleaseUpdates {
    public enum State: Equatable, Sendable {
        case idle, checking, upToDate
        case found(String)
        /// Fraction of the download, nil until its size is known.
        case downloading(String, Double?)
        case preparing(String)
        case ready(String)
        case installing
        case failed(String)
    }
    public private(set) var state: State = .idle
    public private(set) var lastChecked: Date?
    /// Look for a new version once a day (and download it quietly). Mirrors Sparkle's own setting; Check for updates always works.
    public private(set) var automatic: Bool
    @ObservationIgnored public var onCheck: (() -> Void)?
    @ObservationIgnored public var onInstall: (() -> Void)?
    @ObservationIgnored public var onSetAutomatic: ((Bool) -> Void)?
    @ObservationIgnored public var now: () -> Date = Date.init

    public init(automatic: Bool = true) { self.automatic = automatic }

    public func set(_ s: State) { if state != s { state = s } }
    public func checked() { lastChecked = now() }
    public func setAutomatic(_ on: Bool) { automatic = on; onSetAutomatic?(on) }
    /// Sets the mirror without telling Sparkle (it is where the value came from).
    public func setAutomaticQuietly(_ on: Bool) { automatic = on }
    public func check() { onCheck?() }
    /// Restart into the downloaded version. Straight to the updater, so it works whatever happened to the Today notice.
    public func install() { onInstall?() }

    public var busy: Bool {
        switch state { case .checking, .found, .downloading, .preparing, .installing: return true; default: return false }
    }
    public var readyVersion: String? { if case .ready(let v) = state { return v }; return nil }

    /// One short line for Settings.
    public var summary: String {
        switch state {
        case .idle:
            guard let d = lastChecked else { return "Hushd checks once a day." }
            return "Last checked \(Self.ago(d, now: now()))."
        case .checking: return "Checking\u{2026}"
        case .upToDate: return "Hushd is up to date."
        case .found(let v): return "Version \(v) found."
        case .downloading(let v, let f): return f.map { "Downloading version \(v), \(Int($0 * 100)) percent." } ?? "Downloading version \(v)\u{2026}"
        case .preparing(let v): return "Preparing version \(v)\u{2026}"
        case .ready(let v): return "Version \(v) is ready. Restart Hushd to use it."
        case .installing: return "Installing\u{2026}"
        case .failed(let why): return why
        }
    }

    static func ago(_ d: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(d))
        if s < 90 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) minutes ago" }
        if s < 86400 { let h = Int(s / 3600); return "\(h) hour\(h == 1 ? "" : "s") ago" }
        let days = Int(s / 86400); return "\(days) day\(days == 1 ? "" : "s") ago"
    }
}

extension ReleaseUpdates.State {
    public var isFailure: Bool { if case .failed = self { return true }; return false }
}

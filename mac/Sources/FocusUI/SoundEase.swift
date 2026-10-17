import Foundation

// Easing the sound down while you are off task on a video site, and back when you return. A strong cue for video rabbit holes, and the one
// that touches something outside Focus, so it is built to give the volume back in every way it can end: you return, you pause, the session
// ends, you quit, or Focus crashes (the lowered volume is remembered and put right at the next launch). If you change the volume yourself
// while it is lowered, Focus lets go and never fights you for it. It never mutes: it goes to about a third of where you had it.

/// The Mac's output volume, 0 to 1. The app provides the real one (CoreAudio); tests provide a fake.
public protocol SystemVolume: AnyObject {
    func read() -> Float?
    /// False when the output cannot be set (some HDMI or display speakers).
    func write(_ value: Float) -> Bool
}

public enum SoundEase {
    /// Where the volume goes, as a share of where you had it.
    public static let fraction: Float = 0.35
    /// A volume already this low is left alone.
    public static let minimumOriginal: Float = 0.08
    /// How much of the way to the goal each second covers going down, and coming back.
    public static let downRate: Float = 0.3, upRate: Float = 0.5
    /// How far the volume may be from what Focus set before it counts as you having changed it.
    public static let tolerance: Float = 0.03

    static let videoHosts = ["youtube.com", "youtu.be", "netflix.com", "twitch.tv", "tiktok.com", "hulu.com", "disneyplus.com", "primevideo.com", "vimeo.com"]
    static let videoTitleWords = ["youtube", "netflix", "twitch", "tiktok", "hulu", "disney+", "prime video", "vimeo"]

    /// A page that plays video: by address, or by name in the title for a browser that does not report the address.
    public static func looksLikeVideo(_ w: WindowSnapshot) -> Bool {
        if let h = Keys.host(w.url)?.host { return videoHosts.contains { h == $0 || h.hasSuffix("." + $0) } }
        let t = w.title.lowercased()
        return Rules_isBrowserName(w.app) && videoTitleWords.contains { t.contains($0) }
    }

    static func Rules_isBrowserName(_ app: String) -> Bool {
        ["safari", "google chrome", "firefox", "arc", "brave browser", "microsoft edge", "opera", "vivaldi", "orion", "comet"].contains(app.lowercased())
    }

    /// One step toward `goal`; exact when close enough, so it settles.
    public static func step(from v: Float, to goal: Float, rate: Float) -> Float {
        abs(goal - v) < 0.01 ? goal : v + (goal - v) * rate
    }

    /// What is remembered while the volume is lowered, so a crash can be put right.
    public struct Saved: Equatable, Sendable {
        public var original: Float, lowered: Float
        public init(original: Float, lowered: Float) { self.original = original; self.lowered = lowered }
        public var text: String { "\(original),\(lowered)" }
        public init?(text: String) {
            let p = text.split(separator: ",").compactMap { Float($0) }
            guard p.count == 2, p.allSatisfy({ $0 >= 0 && $0 <= 1 }) else { return nil }
            self.init(original: p[0], lowered: p[1])
        }
    }

    /// At launch: the volume to put back after a crash, or nil. Only when the volume is still where Focus last left it (`lowered` is updated at
    /// every step): if you have changed it since, it is yours and is left alone.
    public static func recover(saved: Saved?, current: Float?) -> Float? {
        guard let s = saved, let c = current else { return nil }
        return abs(c - s.lowered) <= tolerance ? s.original : nil
    }
}

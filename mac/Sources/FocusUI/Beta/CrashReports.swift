import Foundation

/// The part of a macOS crash report that helps fix the crash: what went wrong and the crashed thread's code frames.
/// Read from the report macOS itself writes (~/Library/Logs/DiagnosticReports/focus-app-*.ips). Paths, device and incident IDs,
/// and the app-specific text block are left out, so nothing from this Mac or its user travels with it.
public struct CrashSummary: Codable, Equatable, Sendable {
    public var when: Date?
    public var appVersion: String?
    public var osVersion: String?
    public var exception: String?
    public var signal: String?
    public var termination: String?
    public var frames: [String]
}

public enum CrashReports {
    public static let maxFrames = 24
    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// The newest report for this app written after `since`, or nil.
    public static func latest(in dir: URL = folder, since: Date, process: String = "focus-app", fm: FileManager = .default) -> URL? {
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
        let mine = names.filter { $0.hasPrefix(process + "-") && ($0.hasSuffix(".ips") || $0.hasSuffix(".crash")) }
        let dated: [(URL, Date)] = mine.compactMap { n in
            let u = dir.appendingPathComponent(n)
            guard let d = (try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date, d >= since else { return nil }
            return (u, d)
        }
        return dated.max { $0.1 < $1.1 }?.0
    }

    /// The .ips format: one line of JSON (the header), then a JSON body. Anything else gives nil.
    public static func summary(ips text: String) -> CrashSummary? {
        guard let nl = text.firstIndex(of: "\n") else { return nil }
        let headText = String(text[..<nl]), bodyText = String(text[text.index(after: nl)...])
        guard let head = (try? JSONSerialization.jsonObject(with: Data(headText.utf8))) as? [String: Any],
              let body = (try? JSONSerialization.jsonObject(with: Data(bodyText.utf8))) as? [String: Any] else { return nil }
        let exc = body["exception"] as? [String: Any]
        let term = body["termination"] as? [String: Any]
        var frames: [String] = []
        let images = (body["usedImages"] as? [[String: Any]]) ?? []
        if let threads = body["threads"] as? [[String: Any]] {
            let faulting = body["faultingThread"] as? Int ?? threads.firstIndex { ($0["triggered"] as? Bool) == true } ?? 0
            if threads.indices.contains(faulting), let fs = threads[faulting]["frames"] as? [[String: Any]] {
                for f in fs.prefix(maxFrames) {
                    let image = (f["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0]["name"] as? String : nil } ?? "?"
                    let symbol = f["symbol"] as? String ?? "0x" + String(f["imageOffset"] as? Int ?? 0, radix: 16)
                    frames.append("\(Self.clean(image)) \(Self.clean(symbol))")
                }
            }
        }
        let when = (head["timestamp"] as? String).flatMap(parseStamp)
        return CrashSummary(when: when, appVersion: head["app_version"] as? String, osVersion: head["os_version"] as? String,
                            exception: exc?["type"] as? String, signal: exc?["signal"] as? String,
                            termination: (term?["indicator"] as? String).map(clean), frames: frames)
    }

    /// No path survives (a user name lives in /Users/<name>), and long lines are cut.
    static func clean(_ s: String) -> String {
        let noPaths = s.replacingOccurrences(of: #"(/[^\s/]+)+/"#, with: "", options: .regularExpression)
        return String(noPaths.prefix(160))
    }

    static func parseStamp(_ s: String) -> Date? {
        // "2026-10-18 09:12:44.00 +0200"
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return f.date(from: s)
    }
}

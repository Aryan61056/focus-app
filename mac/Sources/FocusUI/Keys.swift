import Foundation
import FocusJudge

/// What a sense reports about the front window. Senses never see the task; the controller adds it.
public struct WindowSnapshot: Sendable, Equatable {
    public var app: String, title: String, url: String, documentPath: String, text: String
    /// The space (Arc) or profile (Dia) the tab sits in, for a browser that keeps several in one window. Empty everywhere else. Only ever
    /// part of a place's identity, never of the brain's keys.
    public var space: String
    public init(app: String, title: String, url: String = "", documentPath: String = "", text: String = "", space: String = "") {
        self.app = app; self.title = title; self.url = url; self.documentPath = documentPath; self.text = text; self.space = space
    }
}

/// Opaque identities the brain uses (docs/BRAIN-SPEC.md 2.1). siteKey = app plus host, windowKey adds path or title,
/// contentKey adds a digest of what was judged. Query strings and fragments are dropped so they cannot split a window.
public enum Keys {
    static func host(_ url: String) -> (host: String, path: String)? {
        guard !url.isEmpty else { return nil }
        let full = url.contains("://") ? url : "https://" + url
        guard let c = URLComponents(string: full), let h = c.host else { return nil }
        return (h.lowercased(), c.path)
    }

    public static func site(_ w: WindowSnapshot) -> String {
        if let h = host(w.url) { return w.app.lowercased() + "|" + h.host }
        return w.app.lowercased()
    }

    public static func window(_ w: WindowSnapshot) -> String {
        if let h = host(w.url) { return w.app.lowercased() + "|" + h.host + h.path }
        let title = w.title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        return w.app.lowercased() + "|" + title
    }

    public static func content(_ w: WindowSnapshot) -> String {
        window(w) + "#" + fnv(String(w.title.prefix(200)) + "\n" + String(String.UnicodeScalarView(w.text.unicodeScalars.prefix(Prompts.maxTextScalars))))
    }

    /// FNV-1a, 64 bit. Stable across runs and platforms, unlike Hasher.
    static func fnv(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16)
    }
}

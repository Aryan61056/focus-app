import Foundation

/// Stage 0 (sensitive windows) and stage 1 (deterministic project rules). Mirrors eval/focus_eval/rules.py.
/// The sensitive lists are illustrative, not a shipped policy.
public enum Rules {
    public static let sensitiveApps: Set<String> = [
        "1password", "1password 7", "bitwarden", "keychain access", "passwords", "dashlane", "lastpass",
        "keepassxc", "keepass", "keepassium", "enpass", "nordpass", "proton pass", "roboform", "keeper",
        "secrets", "authy", "microsoft authenticator", "yubico authenticator",
    ]
    public static let sensitiveDomains: Set<String> = [
        "chase.com", "bankofamerica.com", "wellsfargo.com", "paypal.com", "citi.com", "capitalone.com",
        "usbank.com", "schwab.com", "fidelity.com", "vanguard.com", "coinbase.com", "venmo.com",
        "wise.com", "revolut.com", "1password.com", "bitwarden.com", "lastpass.com", "proton.me",
    ]
    public static let privateTitleMarkers = ["private browsing", "incognito", "inprivate", "private window", "(private)"]

    static func hostAndPath(_ url: String) -> (host: String, path: String) {
        if url.isEmpty { return ("", "") }
        let full = url.contains("://") ? url : "https://" + url
        guard let comps = URLComponents(string: full) else { return ("", "") }
        var host = (comps.host ?? "").lowercased()
        while host.hasPrefix(".") { host.removeFirst() }
        return (host, comps.path)
    }

    static func hostMatches(_ host: String, _ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

    /// entry is "example.com" or "example.com/path/prefix".
    static func domainMatches(entry: String, url: String) -> Bool {
        let (host, path) = hostAndPath(url)
        if host.isEmpty { return false }
        let lowered = entry.lowercased()
        let parts = lowered.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let entryHost = String(parts[0])
        let entryPath = parts.count > 1 ? String(parts[1]) : ""
        if !hostMatches(host, entryHost) { return false }
        if entryPath.isEmpty { return true }
        var p = path.lowercased()
        while p.hasPrefix("/") { p.removeFirst() }
        return p.hasPrefix(entryPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    /// Like Python's os.path.normpath on a "~"-expanded absolute path.
    static func normPath(_ p: String) -> String {
        if p.isEmpty { return "" }
        let replaced = p.replacingOccurrences(of: "~", with: "/HOME")
        var out: [Substring] = []
        for comp in replaced.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." { if !out.isEmpty { out.removeLast() }; continue }
            out.append(comp)
        }
        return "/" + out.joined(separator: "/")
    }

    public static func isSensitive(_ m: Moment) -> Bool {
        if sensitiveApps.contains(m.app.lowercased()) { return true }
        let title = m.windowTitle.lowercased()
        if privateTitleMarkers.contains(where: { title.contains($0) }) { return true }
        let (host, _) = hostAndPath(m.url)
        return sensitiveDomains.contains { hostMatches(host, $0) }
    }

    /// Words that mean the screen shows a login, payment or secret. Text read from the screen is dropped, not judged, when it has one.
    /// Deliberately wide: a false hold only means Focus falls back to the window title for that window.
    static let privateTextMarkers = ["password", "passcode", "passphrase", "card number", "cvv", "cvc", "security code", "social security",
                                     "routing number", "account number", "recovery phrase", "seed phrase", "private key", "one-time code",
                                     "verification code", "2fa", "iban"]
    public static func looksPrivate(screenText t: String) -> Bool {
        let s = normalizedForScan(t).lowercased()
        return privateTextMarkers.contains { s.contains($0) }
    }

    /// Apps Focus does not judge by default: personal messaging and music. Neither is read nor counted as off task.
    /// Slack, Mail and similar can be work, so they are not here. The owner approved a default list on 2026-10-01; this exact
    /// list is a starting point the user can edit in Settings.
    public static let defaultNeverJudgedApps: [String] = [
        "Messages", "WhatsApp", "Telegram", "Signal", "Music", "Spotify", "Podcasts", "Tidal", "Pandora",
    ]
    static let blankPageTitles: Set<String> = ["new tab", "start page", "untitled", "favorites", "top sites", "new window"]

    /// True for a blank new-tab or start page, or an app on the list (matched by name, ignoring case).
    public static func isNeverJudged(_ m: Moment, apps: [String]) -> Bool {
        let app = m.app.lowercased()
        if apps.contains(where: { $0.lowercased() == app }) { return true }
        let title = m.windowTitle.trimmingCharacters(in: .whitespaces).lowercased()
        let (host, _) = hostAndPath(m.url)
        let blankURL = m.url.isEmpty || m.url.hasPrefix("about:blank") || m.url.hasPrefix("chrome://newtab") || m.url.hasPrefix("favorites://") || host == "newtab"
        return blankPageTitles.contains(title) && blankURL && m.documentPath.isEmpty
    }

    /// Patterns that mark on-screen text as instructions aimed at the AI (prompt injection). Matching windows are not judged: they come back
    /// `unsure` with a reason, so they can never advance to a nudge. A denylist, so it fails open against wording it does not know;
    /// tests/test_rules.py keeps this list identical to eval/focus_eval/rules.py. Measured in docs/T7-injection.md.
    public static let injectionPatterns: [String] = [
        #"\b(?:off|on)_task\b"#,
        #"\b(?:different_activity|directly_serves)\b"#,
        #"ignore\s+(?:all\s+|any\s+|the\s+|your\s+)*(?:previous|prior|above|earlier)\s+(?:instructions?|rules?|prompts?)"#,
        #"disregard\s+(?:all\s+|any\s+|the\s+|your\s+)*(?:previous\s+|prior\s+|above\s+|earlier\s+)?(?:instructions?|rules?)"#,
        #"ignore\s+the\s+task"#,
        #"note\s+to\s+(?:the\s+)?(?:ai|assistant|model|llm)"#,
        #"\[(?:system|assistant|developer)\]"#,
        #"(?:^|[.!?\n])\s*(?:system|assistant|developer)\s*:"#,
        #"classification\s+rules"#,
        #"</?window_text"#,
    ]
    static let injectionRegexes: [NSRegularExpression] = injectionPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// What the patterns are matched against: Unicode compatibility form (so full-width letters fold), zero-width characters removed
    /// (so they cannot split a phrase), and percent-escapes decoded (so a phrase in a URL cannot hide).
    static func normalizedForScan(_ s: String) -> String {
        let zeroWidth = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{200E}\u{200F}\u{2060}\u{FEFF}\u{00AD}")
        let folded = s.precomposedStringWithCompatibilityMapping.unicodeScalars.filter { !zeroWidth.contains($0) }
        let text = String(String.UnicodeScalarView(folded))
        return text.removingPercentEncoding ?? text
    }

    public static func looksInjected(_ m: Moment) -> Bool {
        let fields = [m.windowTitle, m.url, m.documentPath, m.windowText].map(normalizedForScan)
        return fields.contains { f in
            let r = NSRange(f.startIndex..., in: f)
            return injectionRegexes.contains { $0.firstMatch(in: f, options: [], range: r) != nil }
        }
    }

    public struct RuleHit: Equatable, Sendable { public var label: Label; public var rule: String }

    /// Deny beats allow. Returns nil when no project rule decides.
    public static func stage1(_ m: Moment) -> RuleHit? {
        let p = m.project
        if p.isEmpty { return nil }
        let app = m.app.lowercased()
        if p.alwaysOffApps.contains(where: { $0.lowercased() == app }) { return RuleHit(label: .offTask, rule: "always_off_app") }
        if p.alwaysOffDomains.contains(where: { domainMatches(entry: $0, url: m.url) }) { return RuleHit(label: .offTask, rule: "always_off_domain") }
        if p.alwaysAllowApps.contains(where: { $0.lowercased() == app }) { return RuleHit(label: .onTask, rule: "always_allow_app") }
        if p.alwaysAllowDomains.contains(where: { domainMatches(entry: $0, url: m.url) }) { return RuleHit(label: .onTask, rule: "always_allow_domain") }
        if p.linkedDomains.contains(where: { domainMatches(entry: $0, url: m.url) }) { return RuleHit(label: .onTask, rule: "linked_domain") }
        let doc = normPath(m.documentPath)
        if !doc.isEmpty {
            for link in p.linkedPaths {
                let base = normPath(link)
                var prefix = base
                while prefix.hasSuffix("/") && prefix.count > 1 { prefix.removeLast() }
                if doc == base || doc.hasPrefix(prefix + "/") { return RuleHit(label: .onTask, rule: "linked_path") }
            }
        }
        return nil
    }
}

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

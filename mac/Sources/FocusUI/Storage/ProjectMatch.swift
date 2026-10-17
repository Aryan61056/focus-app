import Foundation

/// Finding the project you probably mean when you type a task name, so a slightly different spelling continues the old project
/// (its description, its rules) instead of quietly starting a second one. Pure string work on this Mac: no model, no network.
public enum ProjectMatch {
    /// Lowercase letters and digits with single spaces: "Do AP  Euro-Vocab!" and "do ap euro vocab" are the same.
    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        var out = "", gap = false
        for ch in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) { if gap && !out.isEmpty { out.append(" ") }; gap = false; out.unicodeScalars.append(ch) } else { gap = true }
        }
        return out
    }

    /// Words, with a plural "s" dropped so "integrals" and "integral" count as one.
    static func tokens(_ norm: String) -> Set<String> {
        Set(norm.split(separator: " ").map { w -> String in
            let w = String(w)
            return w.count > 3 && w.hasSuffix("s") ? String(w.dropLast()) : w
        })
    }

    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }; if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count { cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)) }
            prev = cur
        }
        return prev[b.count]
    }

    /// The project with exactly this name, ignoring case, spacing and punctuation.
    public static func exact(_ text: String, in projects: [Project]) -> Project? {
        let n = normalize(text)
        guard !n.isEmpty else { return nil }
        return projects.first { normalize($0.name) == n }
    }

    /// How alike two names are, 0 to 1; 0 means "not close enough to ask about". Deliberately strict: a question that is wrong
    /// too often is worse than no question.
    static func score(_ typed: String, _ name: String) -> Double {
        let a = normalize(typed), b = normalize(name)
        guard a.count >= 3, b.count >= 3, a != b else { return 0 }
        // You are partway through typing a name you used before, or added a word to it.
        if b.hasPrefix(a) || a.hasPrefix(b) { return 0.95 }
        let ta = tokens(a), tb = tokens(b)
        let shared = ta.intersection(tb).filter { $0.count >= 3 }
        let jac = Double(ta.intersection(tb).count) / Double(max(1, ta.union(tb).count))
        if !shared.isEmpty, jac >= 0.5 { return 0.6 + 0.3 * jac }
        // A typo or a missing letter: "calc homwork" for "calc homework".
        let ca = Array(a), cb = Array(b)
        let limit = min(ca.count, cb.count) >= 9 ? 2 : 1
        if min(ca.count, cb.count) >= 5, abs(ca.count - cb.count) <= limit, distance(ca, cb) <= limit { return 0.85 }
        return 0
    }

    /// Projects that look like what was typed but are not an exact match, best first (ties go to the one listed first, the newest).
    public static func similar(to text: String, in projects: [Project], limit: Int = 2) -> [Project] {
        if exact(text, in: projects) != nil { return [] }
        var scored: [(index: Int, project: Project, score: Double)] = []
        for (i, p) in projects.enumerated() {
            let sc = score(text, p.name)
            if sc > 0 { scored.append((i, p, sc)) }
        }
        scored.sort { a, b in a.score != b.score ? a.score > b.score : a.index < b.index }
        return scored.prefix(limit).map { $0.project }
    }
}

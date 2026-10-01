import Foundation
import Observation
import FocusJudge

/// All app data, in one JSON file on this Mac (~/Library/Application Support/Focus/store.json).
/// Nothing is sent anywhere. Writes are atomic. A store with no URL is in memory only (tests, snapshots).
@MainActor @Observable
public final class DataStore {
    public private(set) var projects: [Project] = []
    public private(set) var sessions: [SessionRecord] = []
    public private(set) var review: [ReviewMoment] = []
    @ObservationIgnored private let url: URL?

    public init(url: URL? = nil) {
        self.url = url
        guard let url, let data = try? Data(contentsOf: url), let f = try? JSONDecoder.store.decode(StoreFile.self, from: data) else { return }
        projects = f.projects; sessions = f.sessions; review = f.review
    }

    public static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Focus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    func save() {
        guard let url else { return }
        guard let data = try? JSONEncoder.store.encode(StoreFile(projects: projects, sessions: sessions, review: review)) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    // MARK: projects
    @discardableResult
    public func addProject(name: String) -> Project { let p = Project(name: name); projects.insert(p, at: 0); save(); return p }
    public func project(_ id: UUID?) -> Project? { projects.first { $0.id == id } }
    public func update(_ p: Project) { if let i = projects.firstIndex(where: { $0.id == p.id }) { projects[i] = p; save() } }
    public func deleteProject(_ id: UUID) { projects.removeAll { $0.id == id }; save() }

    /// Find a project by its name (case-insensitive) or make one, so a typed task becomes a project the next session can reuse.
    public func projectNamed(_ name: String) -> Project {
        projects.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } ?? addProject(name: name)
    }

    // MARK: sessions
    public func record(_ s: SessionRecord) { sessions.insert(s, at: 0); save() }
    public func setNote(_ note: String, for id: UUID) { if let i = sessions.firstIndex(where: { $0.id == id }) { sessions[i].note = note; save() } }
    public func deleteSession(_ id: UUID) { sessions.removeAll { $0.id == id }; review.removeAll { $0.sessionId == id }; save() }
    public func sessions(for project: UUID) -> [SessionRecord] { sessions.filter { $0.projectId == project } }

    // MARK: review queue
    public func addReview(_ m: ReviewMoment) { review.insert(m, at: 0); if review.count > 200 { review.removeLast() }; save() }
    public func answerReview(_ id: UUID, _ answer: String) { if let i = review.firstIndex(where: { $0.id == id }) { review[i].answer = answer; review[i].reason = nil; save() } }
    public var openReviewCount: Int { review.filter { $0.answer == nil }.count }
    /// Of the moments you answered, how many you said Focus got right. Small samples are common; callers should say so.
    public var agreement: (agreed: Int, answered: Int) {
        let a = review.filter { $0.answer != nil }
        return (a.filter { $0.answer == "right" }.count, a.count)
    }
    /// Totals over every saved session that recorded reads.
    public var readTotals: ReadStats {
        var t = ReadStats()
        for r in sessions.compactMap(\.reads) { t.model += r.model; t.rule += r.rule; t.onTask += r.onTask; t.unsure += r.unsure; t.offTask += r.offTask }
        return t
    }

    // MARK: learned rules -> project profile
    /// "That was fine" and friends become rules the next session honours. Only rules that map onto a site or an app can be stored;
    /// a bare window title (no address) stays session-only, because allowing a whole app for one window would be too broad.
    public func apply(_ rule: LearnedRule, to projectId: UUID?) {
        guard rule.scope == "project", let pid = projectId, var p = project(pid) else { return }
        let parts = rule.key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let rest = parts.count > 1 ? parts[1] : ""
        let looksLikeAddress = rest.contains(".") && !rest.contains(" ")
        switch (rule.kind, rule.keyType) {
        case ("allow", _): if looksLikeAddress { Self.add(rest, to: &p.profile.alwaysAllowDomains) }
                           else if parts.count == 1, rule.keyType == "site" { Self.add(rule.key, to: &p.profile.alwaysAllowApps) }
        case ("deny", _): if looksLikeAddress { Self.add(rest, to: &p.profile.alwaysOffDomains) }
                          else if parts.count == 1 { Self.add(rule.key, to: &p.profile.alwaysOffApps) }
        default: break
        }
        update(p)
    }

    static func add(_ v: String, to list: inout [String]) { if !list.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) { list.append(v) } }

    // MARK: data ownership
    public func deleteEverything() { projects = []; sessions = []; review = []; save() }
    public func exportJSON() -> Data? { try? JSONEncoder.store.encode(StoreFile(projects: projects, sessions: sessions, review: review)) }
}

extension JSONEncoder { static var store: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e } }
extension JSONDecoder { static var store: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }

import Foundation

public enum Label: String, Codable, Sendable { case onTask = "on_task", unsure, offTask = "off_task" }

/// Project rules and context that feed stage 1 and the prompt. Mirrors the scenario JSON in eval/.
public struct ProjectProfile: Codable, Sendable, Equatable {
    public var context: String = ""
    public var linkedDomains: [String] = []
    public var linkedPaths: [String] = []
    public var alwaysAllowApps: [String] = []
    public var alwaysAllowDomains: [String] = []
    public var alwaysOffApps: [String] = []
    public var alwaysOffDomains: [String] = []
    public init() {}

    enum CodingKeys: String, CodingKey {
        case context
        case linkedDomains = "linked_domains", linkedPaths = "linked_paths"
        case alwaysAllowApps = "always_allow_apps", alwaysAllowDomains = "always_allow_domains"
        case alwaysOffApps = "always_off_apps", alwaysOffDomains = "always_off_domains"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        context = try c.decodeIfPresent(String.self, forKey: .context) ?? ""
        linkedDomains = try c.decodeIfPresent([String].self, forKey: .linkedDomains) ?? []
        linkedPaths = try c.decodeIfPresent([String].self, forKey: .linkedPaths) ?? []
        alwaysAllowApps = try c.decodeIfPresent([String].self, forKey: .alwaysAllowApps) ?? []
        alwaysAllowDomains = try c.decodeIfPresent([String].self, forKey: .alwaysAllowDomains) ?? []
        alwaysOffApps = try c.decodeIfPresent([String].self, forKey: .alwaysOffApps) ?? []
        alwaysOffDomains = try c.decodeIfPresent([String].self, forKey: .alwaysOffDomains) ?? []
    }

    public var isEmpty: Bool { self == ProjectProfile() }
}

/// One moment: the task and what the window looks like. In the app this is built from live signals.
public struct Moment: Sendable {
    public var task: String
    public var app: String
    public var windowTitle: String
    public var url: String
    public var documentPath: String
    public var windowText: String
    public var project: ProjectProfile

    public init(task: String, app: String, windowTitle: String, url: String = "", documentPath: String = "",
                windowText: String = "", project: ProjectProfile = ProjectProfile()) {
        self.task = task; self.app = app; self.windowTitle = windowTitle; self.url = url
        self.documentPath = documentPath; self.windowText = windowText; self.project = project
    }
}

/// An eval scenario: a moment plus its gold label and bookkeeping.
public struct Scenario: Codable, Sendable {
    public var id: String
    public var category: String
    public var difficulty: String
    public var task: String
    public var app: String
    public var windowTitle: String
    public var url: String
    public var documentPath: String
    public var windowText: String
    public var label: Label
    public var notes: String
    public var project: ProjectProfile
    public var tags: [String]

    enum CodingKeys: String, CodingKey {
        case id, category, difficulty, task, app, url, label, notes, project, tags
        case windowTitle = "window_title", documentPath = "document_path", windowText = "window_text"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decode(String.self, forKey: .category)
        difficulty = try c.decode(String.self, forKey: .difficulty)
        task = try c.decode(String.self, forKey: .task)
        app = try c.decode(String.self, forKey: .app)
        windowTitle = try c.decode(String.self, forKey: .windowTitle)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        documentPath = try c.decodeIfPresent(String.self, forKey: .documentPath) ?? ""
        windowText = try c.decodeIfPresent(String.self, forKey: .windowText) ?? ""
        label = try c.decode(Label.self, forKey: .label)
        notes = try c.decode(String.self, forKey: .notes)
        project = try c.decodeIfPresent(ProjectProfile.self, forKey: .project) ?? ProjectProfile()
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public var moment: Moment {
        Moment(task: task, app: app, windowTitle: windowTitle, url: url, documentPath: documentPath,
               windowText: windowText, project: project)
    }

    public static func loadAll(directory: URL) throws -> [Scenario] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.flatMap { try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: $0)) }
    }
}

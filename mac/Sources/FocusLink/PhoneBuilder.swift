import Foundation

/// Runs a program and hands back how it ended and the last few lines it said. The real one starts a process; tests use a stand-in.
public protocol ProgramRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], directory: URL?) async -> ProgramResult
}

public struct ProgramResult: Equatable, Sendable {
    public var status: Int32
    /// The last lines the program wrote (output and errors together), for a short reason when it fails.
    public var tail: String
    public init(status: Int32, tail: String = "") { self.status = status; self.tail = tail }
}

public struct ProcessProgramRunner: ProgramRunner {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], directory: URL?) async -> ProgramResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: Self.runSynchronously(executable, arguments, directory)) }
        }
    }

    static func runSynchronously(_ executable: String, _ arguments: [String], _ directory: URL?) -> ProgramResult {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("focus-build-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: log) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // The same environment the build script uses: Xcode's own SDK, not the command line tools' that a shell may export.
        var environment = ProcessInfo.processInfo.environment
        environment["SDKROOT"] = nil
        process.environment = environment
        let sink = try? FileHandle(forWritingTo: log)
        process.standardOutput = sink; process.standardError = sink
        do { try process.run() } catch { return ProgramResult(status: -1, tail: "Could not start \(URL(fileURLWithPath: executable).lastPathComponent).") }
        process.waitUntilExit()
        try? sink?.close()
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let tail = text.split(whereSeparator: \.isNewline).suffix(12).joined(separator: "\n")
        return ProgramResult(status: process.terminationStatus, tail: tail)
    }
}

/// Everything needed to build the iPhone app on this Mac, found without asking: where the project is, whether xcodegen is there, which
/// Apple team to sign with. Each lookup is a plain function so a test can feed it a made-up Mac.
public enum PhoneBuild {
    /// The repository folder this copy of Hushd was built from (the folder with `companion/project.yml`), or nil for a copy with no such folder.
    /// `tools/build_app.sh` stamps the app's own path (`<repo>/mac/.build/Hushd.app`) into it; FOCUS_REPO overrides.
    public static func sourceRoot(environment: [String: String] = ProcessInfo.processInfo.environment, bundle: Bundle = .main) -> URL? {
        func hasProject(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.appendingPathComponent("companion/project.yml").path) }
        if let path = environment["FOCUS_REPO"], !path.isEmpty { let u = URL(fileURLWithPath: path, isDirectory: true); return hasProject(u) ? u : nil }
        guard let stamped = bundle.infoDictionary?["FocusBuildSource"] as? String else { return nil }
        let repo = URL(fileURLWithPath: stamped).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return hasProject(repo) ? repo : nil
    }

    public static func xcodegen(fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        ["/opt/homebrew/bin/xcodegen", "/usr/local/bin/xcodegen"].first(where: fileExists)
    }

    public static func homebrew(fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: fileExists)
    }

    /// An Apple team id is ten letters and digits. Anything else is not one, so it is never passed to a build.
    public static func isTeamID(_ text: String) -> Bool {
        text.count == 10 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// The team to sign with: one typed in earlier or in FOCUS_TEAM_ID, else the first team Xcode knows from the Apple ID signed in under
    /// Settings > Accounts (a free Personal Team is enough). A paid team comes first when there are several.
    public static func team(saved: String?, environment: [String: String], xcodeTeams: [String: Any]?) -> String? {
        for candidate in [saved, environment["FOCUS_TEAM_ID"]] { if let c = candidate?.trimmingCharacters(in: .whitespaces), isTeamID(c) { return c } }
        let entries = (xcodeTeams ?? [:]).values.flatMap { ($0 as? [[String: Any]]) ?? [] }
        let ids = entries.compactMap { entry -> (id: String, free: Bool)? in
            guard let id = entry["teamID"] as? String, isTeamID(id) else { return nil }
            return (id, entry["isFreeProvisioningTeam"] as? Bool ?? false)
        }
        return (ids.first { !$0.free } ?? ids.first)?.id
    }

    /// What Xcode keeps about the signed-in accounts; empty or missing when nobody has signed in.
    public static func xcodeTeams() -> [String: Any]? { UserDefaults(suiteName: "com.apple.dt.Xcode")?.dictionary(forKey: "IDEProvisioningTeams") }

    public static func buildArguments(derivedData: URL, team: String) -> [String] {
        ["-project", "FocusCompanion.xcodeproj", "-scheme", "FocusCompanion", "-configuration", "Debug", "-destination", "generic/platform=iOS",
         "-derivedDataPath", derivedData.path, "-allowProvisioningUpdates", "DEVELOPMENT_TEAM=\(team)", "build"]
    }

    /// One short sentence for a failed build: the last line that says what went wrong, with the two fixable causes put in plain words.
    public static func reason(tail: String) -> String {
        let lines = tail.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = lines.last { $0.lowercased().contains("error") } ?? lines.last ?? ""
        let lower = tail.lowercased()
        if lower.contains("no account") || lower.contains("no profiles") || (lower.contains("signing") && lower.contains("team")) {
            return "Xcode could not sign the app. Sign in to your Apple ID in Xcode (Settings, Accounts), then try again."
        }
        if lower.contains("no such module") || (lower.contains("ios 26") && lower.contains("sdk")) {
            return "Xcode is missing the iOS platform. Open Xcode once and let it finish installing."
        }
        if text.isEmpty { return "The iPhone app did not build." }
        return "The iPhone app did not build: " + (text.count > 160 ? String(text.prefix(157)) + "..." : text)
    }
}

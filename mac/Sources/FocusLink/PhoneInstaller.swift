import Foundation
import Observation

/// An iPhone that Xcode's device tool can reach right now.
public struct InstallTarget: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// "iPhone 15 Pro", or empty when the tool did not say.
    public let model: String
    /// iOS refuses a development install until Developer Mode is on (Settings, Privacy & Security on the phone).
    public let needsDeveloperMode: Bool
    public init(id: String, name: String, model: String = "", needsDeveloperMode: Bool = false) {
        self.id = id; self.name = name; self.model = model; self.needsDeveloperMode = needsDeveloperMode
    }
}

public struct DeviceToolResult: Equatable, Sendable {
    public var status: Int32
    public var json: Data?
    public var errorText: String
    public init(status: Int32, json: Data? = nil, errorText: String = "") { self.status = status; self.json = json; self.errorText = errorText }
}

/// Runs `xcrun devicectl <arguments>` and hands back what it wrote. The real one starts a process; tests use a stand-in.
public protocol DeviceTool: Sendable {
    func run(_ arguments: [String], timeout: TimeInterval) async -> DeviceToolResult
}

/// What `devicectl` says, read defensively: a missing key means "skip it", never a crash.
public enum DeviceListing {
    /// The iPhones the tool can reach. Phones that are paired but away (tunnel unavailable) are left out, and so is anything that is not an iPhone.
    public static func targets(from json: Data) -> [InstallTarget] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let result = root["result"] as? [String: Any], let devices = result["devices"] as? [[String: Any]] else { return [] }
        return devices.compactMap { d in
            let hardware = d["hardwareProperties"] as? [String: Any] ?? [:]
            let props = d["deviceProperties"] as? [String: Any] ?? [:]
            let connection = d["connectionProperties"] as? [String: Any] ?? [:]
            guard let id = d["identifier"] as? String, !id.isEmpty,
                  hardware["platform"] as? String == "iOS", (hardware["deviceType"] as? String)?.lowercased() == "iphone" else { return nil }
            if connection["tunnelState"] as? String == "unavailable" { return nil }
            let name = (props["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "iPhone"
            return InstallTarget(id: id, name: name, model: hardware["marketingName"] as? String ?? "",
                                 needsDeveloperMode: props["developerModeStatus"] as? String == "disabled")
        }
    }

    /// One short sentence for a failed install: the most specific message the tool gave (the innermost error), tidied, with the two
    /// causes people can fix themselves put in plain words.
    public static func reason(json: Data?, errorText: String) -> String {
        var messages: [String] = []
        if let json, let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any], let error = root["error"] { collect(error, into: &messages) }
        let raw = messages.last ?? errorText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let lower = text.lowercased()
        if lower.contains("developer mode") { return "Turn on Developer Mode on the iPhone (Settings, Privacy & Security), then try again." }
        if lower.contains("locked") { return "Unlock the iPhone and try again." }
        if text.isEmpty { return "Hushd could not install on this iPhone." }
        return "Could not install: " + (text.count > 160 ? String(text.prefix(157)) + "..." : text)
    }

    private static func collect(_ node: Any, into out: inout [String]) {
        if let d = node as? [String: Any] {
            if let v = d["NSLocalizedDescription"] {
                if let s = v as? String { out.append(s) } else if let s = (v as? [String: Any])?["string"] as? String { out.append(s) }
            }
            for key in d.keys.sorted() { collect(d[key] as Any, into: &out) }
        } else if let a = node as? [Any] { for item in a { collect(item, into: &out) } }
    }
}

/// The real tool: Xcode's `devicectl`, through `xcrun`. Its JSON goes to a temporary file (the only output format Apple supports for
/// scripts) that is read and deleted at once. Nothing is kept.
public struct XcrunDeviceTool: DeviceTool {
    public init() {}
    public func run(_ arguments: [String], timeout: TimeInterval) async -> DeviceToolResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: Self.runSynchronously(arguments, timeout: timeout)) }
        }
    }

    static func runSynchronously(_ arguments: [String], timeout: TimeInterval) -> DeviceToolResult {
        let id = UUID().uuidString
        let jsonFile = FileManager.default.temporaryDirectory.appendingPathComponent("focus-devicectl-\(id).json")
        let errorFile = FileManager.default.temporaryDirectory.appendingPathComponent("focus-devicectl-\(id).err")
        FileManager.default.createFile(atPath: errorFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: jsonFile); try? FileManager.default.removeItem(at: errorFile) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["devicectl"] + arguments + ["--timeout", String(Int(timeout)), "--json-output", jsonFile.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = try? FileHandle(forWritingTo: errorFile)
        do { try process.run() } catch { return DeviceToolResult(status: -1, errorText: "Xcode's command line tools are not available.") }
        // The tool has its own timeout; this one only guards against a tool that never returns.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 10, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        let errorText = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
        return DeviceToolResult(status: process.terminationStatus, json: try? Data(contentsOf: jsonFile), errorText: errorText)
    }
}

/// Puts the Hushd iPhone app on a plugged-in iPhone, from the iPhone window. It needs Xcode's device tool, and either an iPhone build
/// inside this copy of Hushd (tools/build_iphone.sh) or this Mac's copy of the project, which Hushd then builds itself. With neither it
/// says nothing.
/// Nothing leaves the Mac except the app itself, to the phone that was picked, over the cable.
@MainActor @Observable
public final class PhoneInstaller {
    public enum State: Equatable {
        /// This copy of Hushd has no iPhone app inside it, so there is nothing to offer.
        case notIncluded
        /// Xcode's device tool is missing or failed to start.
        case needsXcode
        case idle
        case looking
        case noPhone
        case ready([InstallTarget])
        case installing(String)
        /// Making the iPhone app from this Mac's copy of the project, for the named phone. `step` says which part.
        case building(phone: String, step: String)
        /// Building needs xcodegen, which is not on this Mac. Installing it is the person's click.
        case needsXcodegen(InstallTarget)
        case installingXcodegen
        /// Building needs an Apple team to sign with and Xcode has none to offer: the person signs in to Xcode or types the id.
        case needsTeam(InstallTarget)
        case installed(String)
        case failed(String)
    }

    /// What building the iPhone app needs from this Mac. Live by default; a test hands in a made-up Mac.
    public struct BuildEnvironment: Sendable {
        public var source: @Sendable () -> URL?
        public var xcodegen: @Sendable () -> String?
        public var homebrew: @Sendable () -> String?
        public var team: @Sendable () -> String?
        public var saveTeam: @Sendable (String) -> Void
        public var runner: any ProgramRunner
        public init(source: @escaping @Sendable () -> URL?, xcodegen: @escaping @Sendable () -> String?, homebrew: @escaping @Sendable () -> String?,
                    team: @escaping @Sendable () -> String?, saveTeam: @escaping @Sendable (String) -> Void, runner: any ProgramRunner) {
            self.source = source; self.xcodegen = xcodegen; self.homebrew = homebrew; self.team = team; self.saveTeam = saveTeam; self.runner = runner
        }
        static let teamKey = "focus.iphoneTeamID"
        public static let live = BuildEnvironment(
            source: { PhoneBuild.sourceRoot() }, xcodegen: { PhoneBuild.xcodegen() }, homebrew: { PhoneBuild.homebrew() },
            team: { PhoneBuild.team(saved: UserDefaults.standard.string(forKey: teamKey), environment: ProcessInfo.processInfo.environment, xcodeTeams: PhoneBuild.xcodeTeams()) },
            saveTeam: { UserDefaults.standard.set($0, forKey: teamKey) }, runner: ProcessProgramRunner())
    }

    public private(set) var state: State = .idle
    @ObservationIgnored private let tool: DeviceTool
    @ObservationIgnored private let appURL: () -> URL?
    @ObservationIgnored private let build: BuildEnvironment
    /// The phone an install was started for, kept while a missing piece (xcodegen, a team) is sorted out so it carries on afterwards.
    @ObservationIgnored private var pending: InstallTarget?

    public init(tool: DeviceTool = XcrunDeviceTool(), appURL: @escaping () -> URL? = { PhoneInstaller.bundledApp() }, build: BuildEnvironment = .live) {
        self.tool = tool; self.appURL = appURL; self.build = build
    }

    /// The iPhone app inside this copy of Hushd (Contents/Resources/Hushd for iPhone.app), or the one FOCUS_IPHONE_APP names.
    public nonisolated static func bundledApp(environment: [String: String] = ProcessInfo.processInfo.environment, bundle: Bundle = .main) -> URL? {
        func app(at url: URL?) -> URL? {
            guard let url else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("Info.plist").path) else { return nil }
            return url
        }
        if let path = environment["FOCUS_IPHONE_APP"], !path.isEmpty { return app(at: URL(fileURLWithPath: path)) }
        return app(at: bundle.resourceURL?.appendingPathComponent("Hushd for iPhone.app"))
    }

    /// True when pressing Install will first make the iPhone app here (no build inside this copy of Hushd, but the project is on this Mac).
    public var buildsItself: Bool { appURL() == nil && build.source() != nil }

    /// Asks which iPhones are reachable. `quietly` keeps a settled answer on screen while it checks again, so a refresh does not flicker.
    public func look(quietly: Bool = false) async {
        switch state {
        case .installing, .installed, .looking, .building, .needsXcodegen, .installingXcodegen, .needsTeam: return
        case .failed where quietly: return   // a refresh must not wipe the reason an install just failed
        default: break
        }
        guard appURL() != nil || build.source() != nil else { state = .notIncluded; return }
        if !quietly { state = .looking }
        let result = await tool.run(["list", "devices"], timeout: 10)
        guard let json = result.json else { state = .needsXcode; return }
        let targets = DeviceListing.targets(from: json)
        let next: State = targets.isEmpty ? .noPhone : .ready(targets)
        if state != next { state = next }
    }

    /// Checks again every few seconds for as long as the caller's task lives (the window being open), so plugging the phone in is noticed.
    public func watch(every seconds: Double = 5) async {
        while !Task.isCancelled {
            await look(quietly: state != .idle && state != .notIncluded)
            if state == .notIncluded { return }   // nothing to offer, so nothing to keep checking
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    /// Puts the app on the phone. With an iPhone build inside this copy of Hushd that is just the install; otherwise Hushd makes the build
    /// itself from this Mac's copy of the project first (xcodegen, then xcodebuild signed with your team), so no one has to run a script.
    public func install(on target: InstallTarget) async {
        switch state {
        case .installing, .building, .installingXcodegen: return
        default: break
        }
        pending = target
        if let app = appURL() { await send(app, to: target); return }
        guard let root = build.source() else { state = .notIncluded; return }
        await buildAndSend(from: root, to: target)
    }

    private func send(_ app: URL, to target: InstallTarget) async {
        state = .installing(target.name)
        let result = await tool.run(["device", "install", "app", "--device", target.id, app.path], timeout: 240)
        if result.status == 0 {
            state = .installed(target.name)
            pending = nil
            // Best effort: open it on the phone. A locked phone or an untrusted developer profile refuses, and that is fine.
            if let id = Bundle(url: app)?.bundleIdentifier { _ = await tool.run(["device", "process", "launch", "--device", target.id, id], timeout: 20) }
        } else { state = .failed(DeviceListing.reason(json: result.json, errorText: result.errorText)) }
    }

    private func buildAndSend(from root: URL, to target: InstallTarget) async {
        guard let xcodegen = build.xcodegen() else { state = .needsXcodegen(target); return }
        guard let team = build.team() else { state = .needsTeam(target); return }
        let project = root.appendingPathComponent("companion", isDirectory: true)
        let out = project.appendingPathComponent(".build", isDirectory: true)
        let derived = out.appendingPathComponent("DerivedData", isDirectory: true)
        let finished = out.appendingPathComponent("Hushd for iPhone.app", isDirectory: true)
        let phone = target.name

        state = .building(phone: phone, step: "Preparing the project")
        let generated = await build.runner.run(xcodegen, ["generate"], directory: project)
        guard generated.status == 0 else { state = .failed("Could not prepare the iPhone project: " + (generated.tail.split(whereSeparator: \.isNewline).last.map(String.init) ?? "xcodegen failed")); return }

        state = .building(phone: phone, step: "Building the iPhone app. The first time takes a few minutes.")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let built = await build.runner.run("/usr/bin/xcodebuild", PhoneBuild.buildArguments(derivedData: derived, team: team), directory: project)
        guard built.status == 0 else { state = .failed(PhoneBuild.reason(tail: built.tail)); return }

        let product = derived.appendingPathComponent("Build/Products/Debug-iphoneos/FocusCompanion.app")
        try? FileManager.default.removeItem(at: finished)
        let copied = await build.runner.run("/usr/bin/ditto", [product.path, finished.path], directory: nil)
        guard copied.status == 0 else { state = .failed("The iPhone app built but could not be copied into place."); return }
        await send(finished, to: target)
    }

    /// The person agreed to install xcodegen with Homebrew; carries on with the install when it is done.
    public func installXcodegen() async {
        guard case .needsXcodegen(let target) = state else { return }
        guard let brew = build.homebrew() else {
            state = .failed("xcodegen is missing and Homebrew is not on this Mac. Install xcodegen (github.com/yonaskolb/XcodeGen), then try again."); return
        }
        state = .installingXcodegen
        let result = await build.runner.run(brew, ["install", "xcodegen"], directory: nil)
        guard result.status == 0, build.xcodegen() != nil else {
            state = .failed("Could not install xcodegen: " + (result.tail.split(whereSeparator: \.isNewline).last.map(String.init) ?? "Homebrew failed")); return
        }
        state = .idle   // out of "installing xcodegen", so the install it was waiting for can start
        await install(on: target)
    }

    /// A team id typed by the person, for a Mac where Xcode has no signed-in account to read one from. Carries on with the install.
    public func useTeam(_ id: String) async {
        let id = id.trimmingCharacters(in: .whitespaces).uppercased()
        guard case .needsTeam(let target) = state, PhoneBuild.isTeamID(id) else { return }
        build.saveTeam(id)
        await install(on: target)
    }

    /// Back to looking, after a failure or a finished install.
    public func again() async { pending = nil; state = .idle; await look() }
}

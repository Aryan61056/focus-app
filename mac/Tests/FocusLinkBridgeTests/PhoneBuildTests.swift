import XCTest
@testable import FocusLink

/// Building the iPhone app from the Mac's own copy of the project, then installing it. Everything here runs against stand-ins for the
/// programs (xcodegen, xcodebuild, ditto, brew, devicectl): no phone, signing team or Xcode build was involved, so none of it proves a real build.
@MainActor
final class PhoneBuildTests: XCTestCase {
    final class FakeRunner: ProgramRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var log: [[String]] = []
        var failing: Set<String> = []
        func run(_ executable: String, _ arguments: [String], directory: URL?) async -> ProgramResult {
            lock.lock(); defer { lock.unlock() }
            log.append([URL(fileURLWithPath: executable).lastPathComponent] + arguments)
            let name = URL(fileURLWithPath: executable).lastPathComponent
            return failing.contains(name) ? ProgramResult(status: 65, tail: "ld: something\nerror: Signing for \"FocusCompanion\" requires a development team.") : ProgramResult(status: 0)
        }
        var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return log }
    }

    final class Mac: @unchecked Sendable {
        private let lock = NSLock()
        private var _xcodegen: String?, _team: String?, _saved: String?
        init(xcodegen: String? = "/opt/homebrew/bin/xcodegen", team: String? = "ABCDE12345") { _xcodegen = xcodegen; _team = team }
        var xcodegen: String? { get { lock.lock(); defer { lock.unlock() }; return _xcodegen } set { lock.lock(); _xcodegen = newValue; lock.unlock() } }
        var team: String? { get { lock.lock(); defer { lock.unlock() }; return _team } set { lock.lock(); _team = newValue; lock.unlock() } }
        var saved: String? { lock.lock(); defer { lock.unlock() }; return _saved }
        func save(_ id: String) { lock.lock(); _saved = id; _team = id; lock.unlock() }
    }

    private let repo = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("focus-build-test-\(UUID().uuidString)", isDirectory: true)
    private let phone = PhoneInstallerTests.list(PhoneInstallerTests.device())

    override func tearDown() { try? FileManager.default.removeItem(at: repo) }

    private func installer(runner: FakeRunner, mac: Mac, tool: PhoneInstallerTests.FakeTool, embedded: URL? = nil, homebrew: String? = "/opt/homebrew/bin/brew") -> PhoneInstaller {
        let env = PhoneInstaller.BuildEnvironment(source: { self.repo }, xcodegen: { mac.xcodegen }, homebrew: { homebrew }, team: { mac.team },
                                                  saveTeam: { mac.save($0) }, runner: runner)
        return PhoneInstaller(tool: tool, appURL: { embedded }, build: env)
    }

    private func tool(_ extra: [DeviceToolResult] = []) -> PhoneInstallerTests.FakeTool {
        PhoneInstallerTests.FakeTool([DeviceToolResult(status: 0, json: phone)] + extra + [DeviceToolResult(status: 0), DeviceToolResult(status: 0)])
    }

    func testBuildsThenInstallsWhenNoBuildIsInsideThisCopy() async throws {
        let runner = FakeRunner(), device = tool()
        let installer = installer(runner: runner, mac: Mac(), tool: device)
        XCTAssertTrue(installer.buildsItself)
        await installer.look()
        guard case .ready(let targets) = installer.state, let target = targets.first else { return XCTFail("no phone offered: \(installer.state)") }
        await installer.install(on: target)

        XCTAssertEqual(installer.state, .installed("Sam's iPhone"))
        let calls = runner.calls
        XCTAssertEqual(calls.map { $0.first }, ["xcodegen", "xcodebuild", "ditto"])
        XCTAssertEqual(calls[0], ["xcodegen", "generate"])
        XCTAssertTrue(calls[1].contains("DEVELOPMENT_TEAM=ABCDE12345"))
        XCTAssertTrue(calls[1].contains("-allowProvisioningUpdates"))
        XCTAssertTrue(calls[1].contains("generic/platform=iOS"))
        XCTAssertTrue(calls[2].last?.hasSuffix("companion/.build/Focus for iPhone.app") == true)
        let install = device.calls.first { $0.starts(with: ["device", "install", "app"]) }
        XCTAssertEqual(install?.last, repo.appendingPathComponent("companion/.build/Focus for iPhone.app").path)
        XCTAssertEqual(install?[4], "AAAA-1111")
    }

    func testAnIncludedBuildIsInstalledWithoutBuilding() async {
        let runner = FakeRunner(), device = tool()
        let embedded = URL(fileURLWithPath: "/tmp/Focus for iPhone.app")
        let installer = installer(runner: runner, mac: Mac(), tool: device, embedded: embedded)
        XCTAssertFalse(installer.buildsItself)
        await installer.look()
        guard case .ready(let targets) = installer.state else { return XCTFail() }
        await installer.install(on: targets[0])
        XCTAssertTrue(runner.calls.isEmpty, "no build when one is already inside")
        XCTAssertEqual(installer.state, .installed("Sam's iPhone"))
    }

    func testMissingXcodegenAsksThenInstallsItAndCarriesOn() async {
        let runner = FakeRunner(), mac = Mac(xcodegen: nil), device = tool()
        let installer = installer(runner: runner, mac: mac, tool: device)
        await installer.look()
        guard case .ready(let targets) = installer.state else { return XCTFail() }
        await installer.install(on: targets[0])
        guard case .needsXcodegen = installer.state else { return XCTFail("expected to ask first, got \(installer.state)") }
        XCTAssertTrue(runner.calls.isEmpty, "nothing is installed without the click")

        mac.xcodegen = "/opt/homebrew/bin/xcodegen"   // what Homebrew leaves behind
        await installer.installXcodegen()
        XCTAssertEqual(runner.calls.first, ["brew", "install", "xcodegen"])
        XCTAssertEqual(runner.calls.dropFirst().first?.first, "xcodegen")
        XCTAssertEqual(installer.state, .installed("Sam's iPhone"))
    }

    func testNoHomebrewIsSaidPlainly() async {
        let installer = installer(runner: FakeRunner(), mac: Mac(xcodegen: nil), tool: tool(), homebrew: nil)
        await installer.look()
        guard case .ready(let targets) = installer.state else { return XCTFail() }
        await installer.install(on: targets[0])
        await installer.installXcodegen()
        guard case .failed(let why) = installer.state else { return XCTFail() }
        XCTAssertTrue(why.contains("Homebrew"))
    }

    func testNoTeamAsksAndATypedIdIsSavedAndUsed() async {
        let runner = FakeRunner(), mac = Mac(team: nil), device = tool()
        let installer = installer(runner: runner, mac: mac, tool: device)
        await installer.look()
        guard case .ready(let targets) = installer.state else { return XCTFail() }
        await installer.install(on: targets[0])
        guard case .needsTeam = installer.state else { return XCTFail("got \(installer.state)") }
        XCTAssertTrue(runner.calls.isEmpty)

        await installer.useTeam("not a team")
        guard case .needsTeam = installer.state else { return XCTFail("a bad id must not be used") }
        XCTAssertNil(mac.saved)

        await installer.useTeam(" abcde12345 ")
        XCTAssertEqual(mac.saved, "ABCDE12345")
        XCTAssertTrue(runner.calls[1].contains("DEVELOPMENT_TEAM=ABCDE12345"))
        XCTAssertEqual(installer.state, .installed("Sam's iPhone"))
    }

    func testAFailedBuildInstallsNothingAndSaysWhy() async {
        let runner = FakeRunner(), device = tool()
        runner.failing = ["xcodebuild"]
        let installer = installer(runner: runner, mac: Mac(), tool: device)
        await installer.look()
        guard case .ready(let targets) = installer.state else { return XCTFail() }
        await installer.install(on: targets[0])
        guard case .failed(let why) = installer.state else { return XCTFail() }
        XCTAssertTrue(why.contains("Sign in to your Apple ID"), why)
        XCTAssertFalse(device.calls.contains { $0.starts(with: ["device", "install"]) })
        XCTAssertFalse(runner.calls.contains { $0.first == "ditto" })
    }

    func testAScreenStillBuildingKeepsItsStateThroughARefresh() async {
        // The window checks for phones every few seconds; that must not wipe a question that is waiting for an answer.
        let installer = installer(runner: FakeRunner(), mac: Mac(xcodegen: nil), tool: tool())
        await installer.look()
        guard case .ready(let targets) = installer.state else { return XCTFail() }
        await installer.install(on: targets[0])
        await installer.look(quietly: true)
        guard case .needsXcodegen = installer.state else { return XCTFail("refresh replaced the question with \(installer.state)") }
    }

    // MARK: finding things on the Mac

    func testTeamPrefersWhatYouTypedThenTheEnvironmentThenAPaidXcodeTeam() {
        let xcode: [String: Any] = ["me@icloud.com": [["teamID": "FREE123456", "isFreeProvisioningTeam": true], ["teamID": "PAID123456", "isFreeProvisioningTeam": false]]]
        XCTAssertEqual(PhoneBuild.team(saved: "TYPED12345", environment: ["FOCUS_TEAM_ID": "ENVTEAM123"], xcodeTeams: xcode), "TYPED12345")
        XCTAssertEqual(PhoneBuild.team(saved: nil, environment: ["FOCUS_TEAM_ID": "ENVTEAM123"], xcodeTeams: xcode), "ENVTEAM123")
        XCTAssertEqual(PhoneBuild.team(saved: nil, environment: [:], xcodeTeams: xcode), "PAID123456")
        XCTAssertEqual(PhoneBuild.team(saved: "bad", environment: [:], xcodeTeams: ["a": [["teamID": "FREE123456", "isFreeProvisioningTeam": true]]]), "FREE123456")
        XCTAssertNil(PhoneBuild.team(saved: nil, environment: [:], xcodeTeams: nil), "nobody signed in to Xcode")
        XCTAssertNil(PhoneBuild.team(saved: nil, environment: [:], xcodeTeams: ["a": [["teamID": "short"]]]))
    }

    func testTeamIdShape() {
        XCTAssertTrue(PhoneBuild.isTeamID("ABCDE12345"))
        for bad in ["", "ABCDE1234", "ABCDE123456", "ABCDE 2345", "ABCDE-2345", "ÄBCDE12345"] { XCTAssertFalse(PhoneBuild.isTeamID(bad), bad) }
    }

    func testTheProjectIsFoundOnlyWhereItReallyIs() throws {
        XCTAssertNil(PhoneBuild.sourceRoot(environment: ["FOCUS_REPO": repo.path]), "no folder yet")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("companion"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: repo.appendingPathComponent("companion/project.yml").path, contents: Data("name: x".utf8))
        XCTAssertEqual(PhoneBuild.sourceRoot(environment: ["FOCUS_REPO": repo.path])?.path, repo.path)
        XCTAssertNil(PhoneBuild.sourceRoot(environment: [:]), "a test bundle carries no build source")
    }

    func testToolLookupsUseTheGivenFilesystem() {
        XCTAssertEqual(PhoneBuild.xcodegen(fileExists: { $0 == "/usr/local/bin/xcodegen" }), "/usr/local/bin/xcodegen")
        XCTAssertNil(PhoneBuild.xcodegen(fileExists: { _ in false }))
        XCTAssertEqual(PhoneBuild.homebrew(fileExists: { $0 == "/opt/homebrew/bin/brew" }), "/opt/homebrew/bin/brew")
    }

    func testBuildFailureReasons() {
        XCTAssertTrue(PhoneBuild.reason(tail: "error: No Account for Team \"X\"").contains("Sign in"))
        XCTAssertTrue(PhoneBuild.reason(tail: "error: Compile failed in Foo.swift").hasPrefix("The iPhone app did not build: error: Compile failed"))
        XCTAssertEqual(PhoneBuild.reason(tail: ""), "The iPhone app did not build.")
    }
}

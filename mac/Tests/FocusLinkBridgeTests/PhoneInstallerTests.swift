import XCTest
@testable import FocusLink

/// Puts the iPhone app on a phone: what the installer asks `devicectl`, what it makes of the answer, and what it shows.
/// The JSON here is the shape Apple's tool writes (the empty list is the tool's real output on a Mac with no phone plugged in);
/// a device entry was written from the documented fields, not captured from a phone, so no test here proves a real install.
@MainActor
final class PhoneInstallerTests: XCTestCase {
    /// A stand-in for `xcrun devicectl` that answers from a script and remembers what it was asked.
    final class FakeTool: DeviceTool, @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [DeviceToolResult]
        private var asked: [[String]] = []
        init(_ answers: [DeviceToolResult]) { self.answers = answers }
        var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return asked }
        func run(_ arguments: [String], timeout: TimeInterval) async -> DeviceToolResult {
            lock.lock(); defer { lock.unlock() }
            asked.append(arguments)
            return answers.isEmpty ? DeviceToolResult(status: 1) : answers.removeFirst()
        }
    }

    static let emptyList = Data(#"{"info":{"outcome":"success"},"result":{"devices":[]}}"#.utf8)

    static func device(id: String = "AAAA-1111", name: String = "Sam's iPhone", model: String = "iPhone 15 Pro", platform: String = "iOS", type: String = "iPhone",
                       tunnel: String = "connected", developerMode: String = "enabled") -> String {
        """
        {"identifier":"\(id)","hardwareProperties":{"platform":"\(platform)","deviceType":"\(type)","marketingName":"\(model)"},
         "deviceProperties":{"name":"\(name)","developerModeStatus":"\(developerMode)"},"connectionProperties":{"tunnelState":"\(tunnel)"}}
        """
    }
    static func list(_ devices: String...) -> Data { Data(#"{"result":{"devices":[\#(devices.joined(separator: ","))]}}"#.utf8) }

    private let appURL = URL(fileURLWithPath: "/tmp/Hushd for iPhone.app")

    func testNothingIsOfferedWhenThisCopyHasNoIPhoneApp() async {
        let tool = FakeTool([])
        let installer = PhoneInstaller(tool: tool, appURL: { nil })
        await installer.look()
        XCTAssertEqual(installer.state, .notIncluded)
        XCTAssertTrue(tool.calls.isEmpty, "without an app to install there is no reason to talk to the phone")
    }

    func testAMissingDeviceToolIsSaidPlainly() async {
        let installer = PhoneInstaller(tool: FakeTool([DeviceToolResult(status: 72, errorText: "xcrun: error: unable to find utility \"devicectl\"")]), appURL: { self.appURL })
        await installer.look()
        XCTAssertEqual(installer.state, .needsXcode)
    }

    func testNoPhoneAndThenAPhone() async {
        let tool = FakeTool([DeviceToolResult(status: 0, json: Self.emptyList), DeviceToolResult(status: 0, json: Self.list(Self.device()))])
        let installer = PhoneInstaller(tool: tool, appURL: { self.appURL })
        await installer.look()
        XCTAssertEqual(installer.state, .noPhone)
        await installer.look(quietly: true)
        XCTAssertEqual(installer.state, .ready([InstallTarget(id: "AAAA-1111", name: "Sam's iPhone", model: "iPhone 15 Pro")]))
        XCTAssertEqual(tool.calls.first, ["list", "devices"])
    }

    func testOnlyReachableIPhonesAreOffered() {
        let json = Self.list(Self.device(id: "ok"),
                             Self.device(id: "ipad", type: "iPad"),
                             Self.device(id: "mac", platform: "macOS", type: "Mac"),
                             Self.device(id: "away", tunnel: "unavailable"),
                             Self.device(id: "nodev", name: "Dev's iPhone", developerMode: "disabled"))
        let targets = DeviceListing.targets(from: json)
        XCTAssertEqual(targets.map(\.id), ["ok", "nodev"])
        XCTAssertEqual(targets.last?.needsDeveloperMode, true, "the window can warn before an install that iOS will refuse")
        XCTAssertTrue(DeviceListing.targets(from: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(DeviceListing.targets(from: Data(#"{"result":{}}"#.utf8)).isEmpty, "a missing list means no phones, not a crash")
    }

    func testInstallingAsksForTheChosenPhoneAndTheBundledApp() async {
        let tool = FakeTool([DeviceToolResult(status: 0, json: Self.list(Self.device())), DeviceToolResult(status: 0)])
        let installer = PhoneInstaller(tool: tool, appURL: { self.appURL })
        await installer.look()
        guard case .ready(let targets) = installer.state, let target = targets.first else { return XCTFail("expected a phone") }
        await installer.install(on: target)
        XCTAssertEqual(installer.state, .installed("Sam's iPhone"))
        XCTAssertEqual(tool.calls.last, ["device", "install", "app", "--device", "AAAA-1111", appURL.path])
        await installer.look(quietly: true)
        XCTAssertEqual(installer.state, .installed("Sam's iPhone"), "a finished install stays on screen until you leave")
    }

    func testAFailedInstallGivesTheInnermostReasonAndSurvivesARefresh() async {
        let nested = Data(#"""
        {"error":{"domain":"CoreDeviceError","userInfo":{"NSLocalizedDescription":{"string":"Failed to install the app."},
          "NSUnderlyingError":{"error":{"userInfo":{"NSLocalizedDescription":{"string":"The app's signature is not valid for this device."}}}}}}}
        """#.utf8)
        let tool = FakeTool([DeviceToolResult(status: 0, json: Self.list(Self.device())), DeviceToolResult(status: 1, json: nested)])
        let installer = PhoneInstaller(tool: tool, appURL: { self.appURL })
        await installer.look()
        await installer.install(on: InstallTarget(id: "AAAA-1111", name: "Sam's iPhone"))
        XCTAssertEqual(installer.state, .failed("Could not install: The app's signature is not valid for this device."))
        await installer.look(quietly: true)
        XCTAssertEqual(installer.state, .failed("Could not install: The app's signature is not valid for this device."), "polling must not wipe the reason")
    }

    func testTheTwoFixableCausesAreSaidInPlainWords() {
        func message(_ text: String) -> Data { Data(#"{"error":{"userInfo":{"NSLocalizedDescription":"\#(text)"}}}"#.utf8) }
        XCTAssertEqual(DeviceListing.reason(json: message("Developer Mode is disabled on this device."), errorText: ""),
                       "Turn on Developer Mode on the iPhone (Settings, Privacy & Security), then try again.")
        XCTAssertEqual(DeviceListing.reason(json: message("The device is locked."), errorText: ""), "Unlock the iPhone and try again.")
        XCTAssertEqual(DeviceListing.reason(json: nil, errorText: ""), "Hushd could not install on this iPhone.")
        XCTAssertEqual(DeviceListing.reason(json: nil, errorText: "line one\nline two"), "Could not install: line one", "falls back to the first line the tool printed")
        let long = String(repeating: "word ", count: 80)
        XCTAssertLessThanOrEqual(DeviceListing.reason(json: message(long), errorText: "").count, 180, "a long message is cut")
    }

    func testAnInstallIsNotStartedTwice() async {
        let tool = FakeTool([DeviceToolResult(status: 0)])
        let installer = PhoneInstaller(tool: tool, appURL: { self.appURL })
        async let first: Void = installer.install(on: InstallTarget(id: "a", name: "A"))
        async let second: Void = installer.install(on: InstallTarget(id: "a", name: "A"))
        _ = await (first, second)
        XCTAssertEqual(tool.calls.filter { $0.first == "device" }.count, 1)
    }

    func testTheBundledAppIsFoundInResourcesOrByTheDevelopmentOverride() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("focus-installer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = dir.appendingPathComponent("Hushd for iPhone.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertNil(PhoneInstaller.bundledApp(environment: ["FOCUS_IPHONE_APP": app.path]), "a folder without an Info.plist is not an app")
        try Data("<plist/>".utf8).write(to: app.appendingPathComponent("Info.plist"))
        XCTAssertEqual(PhoneInstaller.bundledApp(environment: ["FOCUS_IPHONE_APP": app.path])?.path, app.path)
        XCTAssertNil(PhoneInstaller.bundledApp(environment: ["FOCUS_IPHONE_APP": dir.appendingPathComponent("nope.app").path]))
        XCTAssertNil(PhoneInstaller.bundledApp(environment: [:], bundle: Bundle(for: PhoneInstallerTests.self)), "this test bundle carries no iPhone app")
    }

    /// The one test that runs the real tool, with no phone needed: on a Mac with Xcode it must answer and list nobody.
    func testTheRealDeviceToolAnswersAndParses() async throws {
        let result = await XcrunDeviceTool().run(["list", "devices"], timeout: 10)
        try XCTSkipUnless(result.status == 0, "Xcode's devicectl is not available on this Mac")
        let json = try XCTUnwrap(result.json, "devicectl wrote no JSON")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertNotNil((root["result"] as? [String: Any])?["devices"], "the list is where the installer looks for it")
        _ = DeviceListing.targets(from: json)   // whatever is plugged in must parse without trouble
    }
}

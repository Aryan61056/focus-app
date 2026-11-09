import AppKit
import CryptoKit
import FocusUI
import IOKit

/// The license's only way out of the app: one small JSON POST to hushd.store, kept here and not in the scanned engine modules
/// (tools/check_privacy.py). It sends the key, a code for this Mac and the app version, and nothing else: never a task, a window
/// or anything from a session.
enum LicenseClient {
    static let base = URL(string: "https://hushd.store/api/license/")!

    /// FOCUS_LICENSE_URL points the app at another server (a local test server); it must be an http(s) address.
    static var endpoint: URL {
        if let s = ProcessInfo.processInfo.environment["FOCUS_LICENSE_URL"], let u = URL(string: s), ["http", "https"].contains(u.scheme) { return u }
        return base
    }

    /// A stable code for this Mac that does not reveal it: SHA-256 of Apple's hardware UUID with a Hushd label. The raw UUID never leaves.
    static func deviceID() -> String {
        var uuid = "unknown"
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if service != 0 {
            if let v = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String { uuid = v }
            IOObjectRelease(service)
        }
        let digest = SHA256.hash(data: Data("hushd.device.v1:\(uuid)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func transport() -> LicenseTransport {
        let device = deviceID()
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") + "+" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0")
        let url = endpoint
        let session: URLSession = {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 12; c.timeoutIntervalForResource = 20; c.waitsForConnectivity = false
            c.httpCookieStorage = nil; c.urlCache = nil
            return URLSession(configuration: c)
        }()
        return { call, key in
            let action: String
            switch call { case .activate: action = "activate"; case .validate: action = "validate"; case .deactivate: action = "deactivate" }
            var req = URLRequest(url: url.appendingPathComponent(action))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.setValue("Hushd/\(version)", forHTTPHeaderField: "user-agent")
            let body: [String: String] = ["key": key, "device_id": device, "app_version": version]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (data, _) = try? await session.data(for: req) else { return .unreachable }
            return parse(data)
        }
    }

    /// The server's answer, from its JSON. Anything that is not the documented shape is "no answer", never a refusal of the key.
    static func parse(_ data: Data) -> LicenseReply {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let ok = o["ok"] as? Bool else { return .unreachable }
        let info = (o["license"] as? [String: Any]).flatMap(license(from:))
        if ok { return info.map { .ok($0) } ?? .unreachable }
        let code = (o["error"] as? String).flatMap(LicenseRefusal.init(rawValue:)) ?? .serverError
        return .refused(code, info)
    }

    static func license(from o: [String: Any]) -> LicenseInfo? {
        guard let plan = o["plan"] as? String, let hint = o["key_hint"] as? String else { return nil }
        var expires: Date?
        if let s = o["expires_at"] as? String {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expires = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        return LicenseInfo(plan: plan, expiresAt: expires, maxActivations: o["max_activations"] as? Int ?? 2, activations: o["activations"] as? Int ?? 1, keyHint: hint)
    }
}

/// Builds the license center for the running app and keeps it checked: at launch, when Hushd comes forward, and every few hours.
@MainActor enum LicenseSetup {
    static func make(demo: Bool, testFolder: String?) -> LicenseCenter? {
        let env = ProcessInfo.processInfo.environment
        // The scripted demo has no license (and so no key step); it must never call the server.
        if demo { return nil }
        let channel = BetaBuild.current.channel
        let enforced = channel != .dev || env["FOCUS_REQUIRE_LICENSE"] == "1"
        let vault: LicenseVault = (testFolder?.isEmpty == false)
            ? LicenseVault(url: URL(fileURLWithPath: testFolder!, isDirectory: true).appendingPathComponent("license.json"))
            : LicenseVault(url: LicenseVault.defaultURL)
        let center = LicenseCenter(transport: LicenseClient.transport(), vault: vault, enforced: enforced)
        // Only the Hushd site's key page, on a click.
        center.onGetKey = { if let url = URL(string: "https://hushd.store/beta") { NSWorkspace.shared.open(url) } }
        Task { await center.refreshIfDue() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await center.refreshIfDue() }
        }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in Task { @MainActor in await center.refreshIfDue() } }
        return center
    }
}

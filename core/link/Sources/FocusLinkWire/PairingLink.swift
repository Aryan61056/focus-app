import Foundation

/// What the QR code on the Mac says: `focuslink://pair?c=<code>&m=<mac id>`. Scanning it with the Camera app opens the phone app and pairs.
/// The code is the same one-time, five-minute code that can be typed; the Mac id lets the phone pick the right Mac when there are several.
public struct PairingLink: Equatable, Sendable {
    public static let scheme = "focuslink"
    public var code: PairingCode
    public var macID: UUID

    public init(code: PairingCode, macID: UUID) { self.code = code; self.macID = macID }

    public var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme; c.host = "pair"
        c.queryItems = [URLQueryItem(name: "c", value: code.display.replacingOccurrences(of: "-", with: "")), URLQueryItem(name: "m", value: macID.uuidString)]
        return c.url!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "c" })?.value, let code = PairingCode(entered: raw),
              let mac = items.first(where: { $0.name == "m" })?.value.flatMap(UUID.init(uuidString:)) else { return nil }
        self.code = code; self.macID = mac
    }
}

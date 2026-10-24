import Foundation

/// A link other tools can open to do one thing in Hushd: `focusapp://back` is "Back to task". Shortcuts ("Open URLs"), Raycast, Alfred, a
/// Stream Deck button or a bookmark can use it. Nothing else is accepted: no pause, no ending a session, nothing that takes data in or out.
/// (`focusapp` is a working name, like the app's: it changes with the product name.)
public enum FocusLink {
    public static let scheme = "focusapp"
    public enum Action: Equatable, Sendable { case backToTask }

    public static func action(from url: URL) -> Action? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        // focusapp://back, focusapp:///back and focusapp:back all mean the same thing.
        let host = url.host ?? ""
        // With a host, nothing may follow it ("focusapp://back/../end" is not "back").
        if !host.isEmpty, !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty { return nil }
        let word = (host.isEmpty ? url.path : host).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return word == "back" ? .backToTask : nil
    }
}

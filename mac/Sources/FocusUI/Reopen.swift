import Foundation

// When the place "Back to task" is heading for is gone (the document was closed, the tab shut, the app quit), it is opened again instead of
// only bringing the app forward. These are the rules for what may be opened. Pure, so they are tested; the opening itself is the app's
// (focus-app/Place.swift). Only things you had open yourself and Focus read as on task, and only after you pressed Back to task.

public enum ReopenPolicy {
    /// File types that run or install things. A document you were writing is never one of these.
    static let neverOpen: Set<String> = ["app", "command", "sh", "zsh", "bash", "tool", "pkg", "mpkg", "dmg", "workflow", "action", "scpt", "scptd",
                                         "terminal", "webloc", "url", "jar", "exe", "bat", "py", "pl", "rb", "js", "wflow", "osax", "plugin", "kext", "xpc"]

    /// The file or folder to open for a document place (a Finder window's folder, an editor's project), or nil when it is gone or runs code.
    public static func fileURL(documentPath: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                               isExecutable: (String) -> Bool = ReopenPolicy.runsAsProgram) -> URL? {
        let path = documentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), !path.contains("\0"), exists(path) else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        guard !neverOpen.contains(ext), !path.hasSuffix("/"), !isExecutable(path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// A plain file with the execute bit. A folder always has it, so folders are not counted.
    public static func runsAsProgram(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    /// The page to open for a browser place. Only ordinary web addresses: never a file, script or another app's scheme.
    public static func pageURL(_ address: String) -> URL? {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, a.count < 2048 else { return nil }
        let full = a.contains("://") ? a : "https://" + a
        guard let u = URLComponents(string: full), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = u.host, !host.isEmpty, u.user == nil, u.password == nil else { return nil }
        return u.url
    }

    /// Where an app of this name usually lives, for starting one that has quit.
    public static func appPaths(named name: String, home: String = NSHomeDirectory()) -> [String] {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !n.contains("/"), !n.contains("\0"), !n.hasPrefix(".") else { return [] }
        return ["/Applications/\(n).app", "/System/Applications/\(n).app", "/System/Applications/Utilities/\(n).app",
                "/Applications/Utilities/\(n).app", home + "/Applications/\(n).app"]
    }
}

import Foundation

/// A newer build of this app is sitting in the repo's build folder on this Mac. Local only: nothing is downloaded and no network is used.
public struct UpdateOffer: Equatable, Sendable {
    public var buildID: String
    public var sourcePath: String
    public init(buildID: String, sourcePath: String) { self.buildID = buildID; self.sourcePath = sourcePath }
}

/// Decides whether the build folder holds a newer, finished build than the one running. Pure file reads, so it is tested with temp folders.
/// `tools/build_app.sh` stamps every build with `FocusBuildID` (UTC timestamp, then the git hash), so a larger ID means a later build.
public enum UpdateCheck {
    /// A bundle still being written (the build script replaces it in several steps) is left alone until it has been still this long.
    public static let settleSeconds = 15.0

    public static func buildID(of app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["FocusBuildID"] as? String
    }

    public static func offer(ownID: String?, ownApp: URL, sourceApp: URL, now: Date = Date(), fm: FileManager = .default) -> UpdateOffer? {
        let own = ownApp.resolvingSymlinksInPath().standardizedFileURL.path, src = sourceApp.resolvingSymlinksInPath().standardizedFileURL.path
        guard own != src, let id = buildID(of: sourceApp), id > (ownID ?? "") else { return nil }
        let plist = sourceApp.appendingPathComponent("Contents/Info.plist").path
        guard fm.isExecutableFile(atPath: sourceApp.appendingPathComponent("Contents/MacOS/focus-app").path),
              let modified = (try? fm.attributesOfItem(atPath: plist))?[.modificationDate] as? Date,
              now.timeIntervalSince(modified) >= settleSeconds else { return nil }
        return UpdateOffer(buildID: id, sourcePath: src)
    }
}

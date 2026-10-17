import Foundation
import Observation
import FocusLinkWire
import FocusLinkCloud

/// The Insights the Mac keeps in the person's own iCloud (docs/ICLOUD-SYNC.md). The phone only reads them: they are what the Insights tab
/// shows when the Mac is off, asleep or on another network. A copy lives on the phone so the tab still opens offline.
@MainActor @Observable
final class CloudInsights {
    enum Status: Equatable {
        /// Nothing asked yet.
        case idle
        /// This build is not set up for iCloud, or no iCloud account is signed in. A plain sentence for Settings.
        case unavailable(String)
        case checking
        /// iCloud answered. `snapshot` is nil if the Mac has not turned this on.
        case ready
        case failed(String)
    }

    private(set) var snapshot: CloudSnapshot?
    private(set) var status = Status.idle

    @ObservationIgnored private let cloud: any InsightsSyncing
    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private var listening = false

    init(cloud: (any InsightsSyncing)? = nil, cacheURL: URL? = CloudInsights.defaultCacheURL) {
        self.cloud = cloud ?? InsightsCloud()
        self.cacheURL = cacheURL
        snapshot = Self.load(cacheURL)
    }

    static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("cloud-insights.json")
    }

    /// Reads iCloud now, and asks to be told when the Mac writes again. Cheap to call whenever the app comes forward.
    func refresh() async {
        if status == .checking { return }
        status = .checking
        switch await cloud.availability() {
        case .noAccount: status = .unavailable("Sign in to iCloud in Settings to see your Mac's Insights here."); return
        case .unavailable(let why): status = .unavailable(why); return
        case .available: break
        }
        if !listening {
            listening = true
            await cloud.listen { [weak self] in Task { await self?.refresh() } }
        }
        do {
            let latest = try await cloud.fetch()
            // The Mac turned this off or never turned it on: show nothing rather than something old.
            snapshot = latest
            Self.save(latest, to: cacheURL)
            status = .ready
        } catch { status = .failed((error as? LocalizedError)?.errorDescription ?? "Could not reach iCloud. Try again in a moment.") }
    }

    /// The app delegate got a push: true if it was this sync's.
    @discardableResult func receive(_ userInfo: [AnyHashable: Any]) -> Bool {
        (cloud as? InsightsCloud)?.receive(userInfo) ?? false
    }

    // MARK: the copy on the phone

    private static func load(_ url: URL?) -> CloudSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(CloudSnapshot.self, from: data)
    }

    private static func save(_ snapshot: CloudSnapshot?, to url: URL?) {
        guard let url else { return }
        guard let snapshot else { try? FileManager.default.removeItem(at: url); return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(snapshot).write(to: url, options: [.atomic])
    }
}

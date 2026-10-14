import Foundation
@_exported import FocusLinkWire

/// The phones a Mac has agreed to talk to. Main-actor only: the transport and the UI both live there.
@MainActor public protocol DeviceRegistry: AnyObject {
    var devices: [PairedDevice] { get }
    func device(_ id: UUID) -> PairedDevice?
    func add(_ device: PairedDevice)
    func remove(_ id: UUID)
}

public extension DeviceRegistry {
    func device(_ id: UUID) -> PairedDevice? { devices.first { $0.id == id } }
}

@MainActor public final class MemoryDeviceRegistry: DeviceRegistry {
    public private(set) var devices: [PairedDevice] = []
    public init() {}
    public func add(_ device: PairedDevice) { devices.append(device) }
    public func remove(_ id: UUID) { devices.removeAll { $0.id == id } }
}

/// Paired phones in one JSON file, readable only by this user. The keys in it are what let a phone control the session,
/// so the file is written atomically with mode 0600 and never logged.
@MainActor public final class FileDeviceRegistry: DeviceRegistry {
    public private(set) var devices: [PairedDevice] = []
    private let url: URL

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let d = try? LinkCoding.decode([PairedDevice].self, from: data) { devices = d }
    }

    public static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Focus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("paired-phones.json")
    }

    public func add(_ device: PairedDevice) { devices.append(device); save() }
    public func remove(_ id: UUID) { devices.removeAll { $0.id == id }; save() }

    private func save() {
        guard let data = try? LinkCoding.encode(devices) else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

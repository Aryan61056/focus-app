import Foundation
import Security
import FocusLinkNet

/// Where the phone keeps the key it shares with the Mac. The Keychain, so the key stays out of backups and other apps.
struct PairedMacStore {
    var load: () -> PairedMac?
    var save: (PairedMac) -> Void
    var clear: () -> Void

    static let keychain: PairedMacStore = {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.focusapp.companion.mac", kSecAttrAccount as String: "paired-mac"]
        return PairedMacStore(
            load: {
                var q = base; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
                var out: CFTypeRef?
                guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
                return try? LinkCoding.decode(PairedMac.self, from: data)
            },
            save: { mac in
                guard let data = try? LinkCoding.encode(mac) else { return }
                SecItemDelete(base as CFDictionary)
                var q = base; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(q as CFDictionary, nil)
            },
            clear: { SecItemDelete(base as CFDictionary) })
    }()

    /// For previews and tests.
    static func memory(_ initial: PairedMac? = nil) -> PairedMacStore {
        final class Box: @unchecked Sendable { var mac: PairedMac?; init(_ m: PairedMac?) { mac = m } }
        let box = Box(initial)
        return PairedMacStore(load: { box.mac }, save: { box.mac = $0 }, clear: { box.mac = nil })
    }
}

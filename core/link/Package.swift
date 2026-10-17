// swift-tools-version: 6.0
import PackageDescription

// FocusLinkKit: how the iPhone companion and the Mac app talk to each other. No servers, no accounts.
// FocusLinkWire is pure (messages, pairing code, encrypted handshake) and is tested without a network.
// FocusLinkNet is the thin Network.framework transport on top of it (Bonjour on the local network).
let package = Package(
    name: "FocusLinkKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FocusLinkWire", targets: ["FocusLinkWire"]),
        .library(name: "FocusLinkNet", targets: ["FocusLinkNet"]),
        // Insights through the person's own iCloud (docs/ICLOUD-SYNC.md). Kept apart so the local link never imports CloudKit.
        .library(name: "FocusLinkCloud", targets: ["FocusLinkCloud"]),
    ],
    targets: [
        .target(name: "FocusLinkWire"),
        .target(name: "FocusLinkNet", dependencies: ["FocusLinkWire"]),
        .target(name: "FocusLinkCloud", dependencies: ["FocusLinkWire"]),
        .testTarget(name: "FocusLinkTests", dependencies: ["FocusLinkWire", "FocusLinkNet", "FocusLinkCloud"]),
    ]
)

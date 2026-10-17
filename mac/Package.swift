// swift-tools-version: 6.0
import Foundation
import PackageDescription

// FocusJudge: the Mac port of the S1 detection pipeline (stage 0 sensitive windows, stage 1 project rules,
// stage 3 two-judge text verdict on Apple's on-device model). No UI, no capture, no network.
// The Rust brain (core/brain-rs) is linked only into brain-ffi-check, as a check that Swift can call it over a C ABI.
let rustLib = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("core/brain-rs/target/release").path

let package = Package(
    name: "FocusKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FocusJudge", targets: ["FocusJudge"]),
        .library(name: "FocusBrain", targets: ["FocusBrain"]),
        .executable(name: "focus-judge", targets: ["focus-judge"]),
        .executable(name: "brain-trace", targets: ["brain-trace"]),
        .executable(name: "brain-sim", targets: ["brain-sim"]),
        .executable(name: "brain-ffi-check", targets: ["brain-ffi-check"]),
        .library(name: "FocusUI", targets: ["FocusUI"]),
        .library(name: "FocusSense", targets: ["FocusSense"]),
        .executable(name: "focus-sense-check", targets: ["focus-sense-check"]),
        .library(name: "FocusLink", targets: ["FocusLink"]),
        .library(name: "FocusSocial", targets: ["FocusSocial"]),
        .executable(name: "focus-app", targets: ["focus-app"]),
        .executable(name: "focus-snapshot", targets: ["focus-snapshot"]),
    ],
    dependencies: [
        // How the iPhone companion talks to this app: local network only, see ../core/link and docs/COMPANION.md.
        .package(path: "../core/link"),
    ],
    targets: [
        .target(name: "FocusJudge", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "focus-judge", dependencies: ["FocusJudge"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "FocusBrain", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "BrainTraces", dependencies: ["FocusBrain"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "brain-trace", dependencies: ["BrainTraces"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CFocusBrain"),
        .executableTarget(name: "brain-ffi-check", dependencies: ["BrainTraces", "CFocusBrain"],
                          swiftSettings: [.swiftLanguageMode(.v5)], linkerSettings: [.unsafeFlags(["-L", rustLib, "-lfocus_brain"])]),
        .target(name: "BrainSim", dependencies: ["FocusBrain"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "brain-sim", dependencies: ["BrainSim"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "FocusUI", dependencies: ["FocusBrain", "FocusJudge"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "FocusSense", dependencies: ["FocusUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "FocusLink", dependencies: ["FocusUI", "FocusBrain", .product(name: "FocusLinkNet", package: "link")], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Friends over iCloud (docs/SOCIAL.md): the only CloudKit code, kept out of the engine modules check_privacy.py scans.
        .target(name: "FocusSocial", dependencies: ["FocusUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "focus-sense-check", dependencies: ["FocusSense"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "focus-app", dependencies: ["FocusUI", "FocusSense", "FocusLink", "FocusSocial"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "focus-snapshot", dependencies: ["FocusUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FocusUITests", dependencies: ["FocusUI", "FocusBrain", "FocusJudge"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FocusSenseTests", dependencies: ["FocusSense", "FocusUI", "FocusJudge"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FocusLinkBridgeTests", dependencies: ["FocusLink", "FocusUI", "FocusJudge", .product(name: "FocusLinkNet", package: "link")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FocusSocialTests", dependencies: ["FocusSocial", "FocusUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FocusBrainTests", dependencies: ["FocusBrain", "BrainTraces", "BrainSim"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FocusJudgeTests", dependencies: ["FocusJudge"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

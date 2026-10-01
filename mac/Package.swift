// swift-tools-version: 6.0
import PackageDescription

// FocusJudge: the Mac port of the S1 detection pipeline (stage 0 sensitive windows, stage 1 project rules,
// stage 3 two-judge text verdict on Apple's on-device model). No UI, no capture, no network.
let package = Package(
    name: "FocusKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FocusJudge", targets: ["FocusJudge"]),
        .library(name: "FocusBrain", targets: ["FocusBrain"]),
        .executable(name: "focus-judge", targets: ["focus-judge"]),
        .executable(name: "brain-trace", targets: ["brain-trace"]),
        .executable(name: "brain-sim", targets: ["brain-sim"]),
    ],
    targets: [
        .target(name: "FocusJudge", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "focus-judge", dependencies: ["FocusJudge"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "FocusBrain", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "BrainTraces", dependencies: ["FocusBrain"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "brain-trace", dependencies: ["BrainTraces"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "BrainSim", dependencies: ["FocusBrain"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "brain-sim", dependencies: ["BrainSim"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FocusBrainTests", dependencies: ["FocusBrain", "BrainTraces", "BrainSim"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FocusJudgeTests", dependencies: ["FocusJudge"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

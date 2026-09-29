// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillHanger",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AgentAwakeCore", targets: ["AgentAwakeCore"]),
        .executable(name: "agent-awake", targets: ["AgentAwakeCLI"]),
        .executable(name: "agent-awake-lid-probe", targets: ["AgentAwakeLidProbe"]),
        .executable(name: "agent-awake-closed-lid", targets: ["AgentAwakeClosedLid"]),
        .executable(name: "SkillHanger", targets: ["AgentAwakeApp"])
    ],
    targets: [
        .target(name: "AgentAwakeCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "AgentAwakeCLI", dependencies: ["AgentAwakeCore"]),
        .executableTarget(name: "AgentAwakeLidProbe", dependencies: ["AgentAwakeCore"]),
        .executableTarget(name: "AgentAwakeClosedLid", dependencies: ["AgentAwakeCore"]),
        .target(name: "UsageCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "AgentAwakeApp", dependencies: ["AgentAwakeCore", "UsageCore"], resources: [.process("Assets")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AgentAwakeCoreTests", dependencies: ["AgentAwakeCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SkillHangerAppTests", dependencies: ["AgentAwakeApp", "UsageCore"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)

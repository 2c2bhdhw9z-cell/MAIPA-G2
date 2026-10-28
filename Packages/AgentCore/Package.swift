// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AgentCore",
            targets: ["AgentCore"]
        ),
        .executable(
            name: "maipa-g-runner",
            targets: ["MAIPAGRunner"]
        )
    ],
    targets: [
        .target(
            name: "AgentCore",
            dependencies: [],
            path: "Sources/AgentCore"
        ),
        .executableTarget(
            name: "MAIPAGRunner",
            dependencies: ["AgentCore"],
            path: "Sources/MAIPAGRunner"
        ),
        .testTarget(
            name: "AgentCoreTests",
            dependencies: ["AgentCore"],
            path: "Tests/AgentCoreTests"
        )
    ]
)

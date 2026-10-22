// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchClaude",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchClaude",
            path: "Sources/NotchClaude"
        ),
        .testTarget(
            name: "NotchClaudeTests",
            dependencies: ["NotchClaude"],
            path: "Tests/NotchClaudeTests"
        )
    ]
)

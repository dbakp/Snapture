// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snapture",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Snapture",
            path: "Sources/Snapture",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SnaptureTests",
            dependencies: ["Snapture"],
            path: "Tests/SnaptureTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

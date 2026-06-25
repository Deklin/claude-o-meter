// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeCostBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeCostBar",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClaudeCostBarTests",
            dependencies: ["ClaudeCostBar"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

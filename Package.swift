// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Batteri",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
    ],
    targets: [
        // Everything that does not need a window: models, the engine client and text.
        .target(name: "BatteriCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Batteri",
            dependencies: ["BatteriCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BatteriCoreTests",
            dependencies: ["BatteriCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

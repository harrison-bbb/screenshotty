// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Screenshotty",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Screenshotty", targets: ["Screenshotty"]),
    ],
    dependencies: [
        // Auto-updates. Updates are verified with our own EdDSA key, so no paid Apple account is needed.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(
            name: "ScreenshottyCore",
            path: "Sources/ScreenshottyCore"
        ),
        .executableTarget(
            name: "Screenshotty",
            dependencies: ["ScreenshottyCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Screenshotty"
        ),
        .testTarget(
            name: "ScreenshottyTests",
            dependencies: ["ScreenshottyCore"],
            path: "Tests/ScreenshottyTests"
        ),
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Screenshotty",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Screenshotty", targets: ["Screenshotty"]),
    ],
    targets: [
        .target(
            name: "ScreenshottyCore",
            path: "Sources/ScreenshottyCore"
        ),
        .executableTarget(
            name: "Screenshotty",
            dependencies: ["ScreenshottyCore"],
            path: "Sources/Screenshotty"
        ),
        .testTarget(
            name: "ScreenshottyTests",
            dependencies: ["ScreenshottyCore"],
            path: "Tests/ScreenshottyTests"
        ),
    ]
)

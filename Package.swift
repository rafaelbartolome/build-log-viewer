// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BuildLogViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BuildLogViewer", targets: ["BuildLogViewer"])
    ],
    targets: [
        .executableTarget(
            name: "BuildLogViewer"
        ),
        .testTarget(
            name: "BuildLogViewerTests",
            dependencies: ["BuildLogViewer"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

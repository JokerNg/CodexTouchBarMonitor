// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "CodexTouchBarMonitor",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "CodexTouchBarMonitor", targets: ["CodexTouchBarMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "CodexTouchBarMonitor",
            path: "Sources"
        )
    ]
)

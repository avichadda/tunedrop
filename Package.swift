// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TuneDropMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TuneDrop", targets: ["TuneDropMac"])
    ],
    targets: [
        .executableTarget(name: "TuneDropMac")
    ]
)

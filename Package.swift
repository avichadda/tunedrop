// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TuneDropMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TuneDrop", targets: ["TuneDropMac"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.10.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "TuneDropMac",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ]
        )
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OverheadCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "OverheadCore", targets: ["OverheadCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gavineadie/SatelliteKit.git", from: "2.1.2"),
    ],
    targets: [
        .target(
            name: "OverheadCore",
            dependencies: [
                .product(name: "SatelliteKit", package: "SatelliteKit"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "OverheadCoreTests",
            dependencies: ["OverheadCore"]
        ),
    ]
)

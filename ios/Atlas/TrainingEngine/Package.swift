// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TrainingEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TrainingEngine",
            targets: ["TrainingEngine"]
        ),
    ],
    targets: [
        .target(
            name: "TrainingEngine",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "TrainingEngineTests",
            dependencies: ["TrainingEngine"]
        ),
    ]
)

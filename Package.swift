// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftOOT",
    products: [
        .library(
            name: "OOTDataModel",
            targets: ["OOTDataModel"]
        ),
        .executable(
            name: "OOTExtractCLI",
            targets: ["OOTExtractCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "OOTDataModel"
        ),
        .executableTarget(
            name: "OOTExtractCLI",
            dependencies: [
                "OOTDataModel",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "OOTDataModelTests",
            dependencies: ["OOTDataModel"]
        ),
        .testTarget(
            name: "OOTExtractCLITests",
            dependencies: ["OOTExtractCLI", "OOTDataModel"]
        ),
    ]
)

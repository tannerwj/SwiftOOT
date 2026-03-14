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
        .library(
            name: "OOTRender",
            targets: ["OOTRender"]
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
        .target(
            name: "OOTRender",
            dependencies: ["OOTDataModel"],
            exclude: ["OOTShaders.metal"]
        ),
        .testTarget(
            name: "OOTDataModelTests",
            dependencies: ["OOTDataModel"]
        ),
        .testTarget(
            name: "OOTExtractCLITests",
            dependencies: ["OOTExtractCLI", "OOTDataModel"]
        ),
        .testTarget(
            name: "OOTRenderTests",
            dependencies: ["OOTRender", "OOTDataModel"]
        ),
    ]
)

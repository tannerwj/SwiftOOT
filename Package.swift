// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftOOT",
    products: [
        .library(
            name: "OOTDataModel",
            targets: ["OOTDataModel"]
        ),
        .library(
            name: "OOTContent",
            targets: ["OOTContent"]
        ),
        .library(
            name: "OOTExtractSupport",
            targets: ["OOTExtractSupport"]
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
        .target(
            name: "OOTContent",
            dependencies: ["OOTDataModel"]
        ),
        .target(
            name: "OOTExtractSupport",
            dependencies: ["OOTDataModel"]
        ),
        .executableTarget(
            name: "OOTExtractCLI",
            dependencies: [
                "OOTExtractSupport",
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
            name: "OOTContentTests",
            dependencies: ["OOTContent", "OOTDataModel"]
        ),
        .testTarget(
            name: "OOTExtractCLITests",
            dependencies: ["OOTExtractSupport", "OOTDataModel"]
        ),
        .testTarget(
            name: "OOTRenderTests",
            dependencies: ["OOTRender", "OOTDataModel"]
        ),
    ]
)

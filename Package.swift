// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftOOT",
    products: [
        .library(name: "OOTDataModel", targets: ["OOTDataModel"]),
        .library(name: "OOTRender", targets: ["OOTRender"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "OOTDataModel",
            path: "Sources/OOTDataModel"
        ),
        .target(
            name: "OOTRender",
            dependencies: ["OOTDataModel"],
            path: "Sources/OOTRender",
            exclude: ["OOTShaders.metal"]
        ),
        .testTarget(
            name: "OOTDataModelTests",
            dependencies: ["OOTDataModel"],
            path: "Tests/OOTDataModelTests"
        ),
        .testTarget(
            name: "OOTRenderTests",
            dependencies: ["OOTRender", "OOTDataModel"],
            path: "Tests/OOTRenderTests"
        ),
    ]
)

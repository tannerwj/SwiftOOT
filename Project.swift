import ProjectDescription

private let baseSettings: SettingsDictionary = [
    "MACOSX_DEPLOYMENT_TARGET": "26.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_VERSION": "6.0",
]

let project = Project(
    name: "SwiftOOT",
    settings: .settings(base: baseSettings),
    targets: [
        staticFrameworkTarget(name: "OOTDataModel"),
        staticFrameworkTarget(
            name: "OOTExtractSupport",
            dependencies: [.target(name: "OOTDataModel")]
        ),
        staticFrameworkTarget(
            name: "OOTContent",
            dependencies: [.target(name: "OOTDataModel")],
            resources: ["Sources/OOTContent/Resources/**"]
        ),
        staticFrameworkTarget(
            name: "OOTCore",
            dependencies: [
                .target(name: "OOTContent"),
                .target(name: "OOTDataModel"),
                .target(name: "OOTTelemetry"),
            ]
        ),
        staticFrameworkTarget(
            name: "OOTRender",
            dependencies: [.target(name: "OOTDataModel")]
        ),
        staticFrameworkTarget(
            name: "OOTUI",
            dependencies: [
                .target(name: "OOTCore"),
                .target(name: "OOTRender"),
                .target(name: "OOTContent"),
                .target(name: "OOTDataModel"),
                .target(name: "OOTTelemetry"),
            ]
        ),
        staticFrameworkTarget(
            name: "OOTTelemetry",
            dependencies: [.target(name: "OOTDataModel")]
        ),
        appTarget(
            name: "OOTMac",
            dependencies: [
                .target(name: "OOTDataModel"),
                .target(name: "OOTContent"),
                .target(name: "OOTCore"),
                .target(name: "OOTRender"),
                .target(name: "OOTUI"),
                .target(name: "OOTTelemetry"),
            ]
        ),
        commandLineTarget(
            name: "OOTExtractCLI",
            dependencies: [
                .target(name: "OOTExtractSupport"),
                .external(name: "ArgumentParser"),
            ]
        ),
        unitTestTarget(name: "OOTDataModelTests", testedTarget: "OOTDataModel"),
        unitTestTarget(name: "OOTExtractCLITests", testedTarget: "OOTExtractSupport"),
        unitTestTarget(name: "OOTContentTests", testedTarget: "OOTContent"),
        unitTestTarget(name: "OOTCoreTests", testedTarget: "OOTCore"),
        unitTestTarget(name: "OOTRenderTests", testedTarget: "OOTRender"),
        unitTestTarget(
            name: "OOTUITests",
            testedTarget: "OOTUI",
            dependencies: [.target(name: "OOTCore")]
        ),
        unitTestTarget(name: "OOTTelemetryTests", testedTarget: "OOTTelemetry"),
    ]
)

private func staticFrameworkTarget(
    name: String,
    dependencies: [TargetDependency] = [],
    resources: ResourceFileElements? = nil
) -> Target {
    .target(
        name: name,
        destinations: .macOS,
        product: .staticFramework,
        bundleId: "com.tannerwj.SwiftOOT.\(name)",
        infoPlist: .default,
        sources: .sourceFilesList(globs: ["Sources/\(name)/**"]),
        resources: resources,
        dependencies: dependencies
    )
}

private func appTarget(
    name: String,
    dependencies: [TargetDependency]
) -> Target {
    .target(
        name: name,
        destinations: .macOS,
        product: .app,
        bundleId: "com.tannerwj.SwiftOOT.\(name)",
        infoPlist: .default,
        sources: .sourceFilesList(globs: ["Sources/\(name)/**"]),
        dependencies: dependencies
    )
}

private func commandLineTarget(
    name: String,
    dependencies: [TargetDependency]
) -> Target {
    .target(
        name: name,
        destinations: .macOS,
        product: .commandLineTool,
        bundleId: "com.tannerwj.SwiftOOT.\(name)",
        infoPlist: .default,
        sources: .sourceFilesList(globs: ["Sources/\(name)/**"]),
        dependencies: dependencies
    )
}

private func unitTestTarget(
    name: String,
    testedTarget: String,
    dependencies: [TargetDependency] = []
) -> Target {
    .target(
        name: name,
        destinations: .macOS,
        product: .unitTests,
        bundleId: "com.tannerwj.SwiftOOT.\(name)",
        infoPlist: .default,
        sources: .sourceFilesList(globs: ["Tests/\(name)/**"]),
        dependencies: [.target(name: testedTarget)] + dependencies
    )
}

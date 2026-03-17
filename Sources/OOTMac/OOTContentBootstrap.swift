import AppKit
import Foundation
import Observation
import OOTContent
import OOTCore
import OOTUI
import SwiftUI

@MainActor
@Observable
final class OOTContentBootstrapModel {
    private static let storedContentRootDefaultsKey = "OOTMac.StoredContentRootPath"

    private let userDefaults: UserDefaults
    private let environment: [String: String]
    private let developerHarnessConfigurationResult: Result<DeveloperHarnessConfiguration?, Error>
    private var startupTask: Task<Void, Never>?

    var configuredContentRoot: URL?
    var runtime: GameRuntime?
    var errorMessage: String?
    var startupHint: String?

    var developerHarnessConfiguration: DeveloperHarnessConfiguration? {
        try? developerHarnessConfigurationResult.get()
    }

    init(
        userDefaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.userDefaults = userDefaults
        self.environment = environment
        developerHarnessConfigurationResult = Result {
            try DeveloperHarnessConfiguration.load(from: environment)
        }
        restoreConfiguration()
    }

    func restoreConfiguration() {
        startupTask?.cancel()
        startupTask = nil
        runtime = nil
        configuredContentRoot = nil
        errorMessage = nil
        startupHint = nil

        if case .failure(let error) = developerHarnessConfigurationResult {
            errorMessage = error.localizedDescription
            return
        }

        if let configuredPath = environment[ContentRootConfiguration.contentRootEnvironmentVariable] {
            let configuredURL = URL(fileURLWithPath: configuredPath, isDirectory: true)
            if applyConfiguredRoot(configuredURL, persistSelection: false) {
                startupHint = "Using content root from \(ContentRootConfiguration.contentRootEnvironmentVariable)."
                if developerHarnessConfiguration?.isEnabled == true {
                    startupHint?.append(" Developer harness enabled.")
                }
                return
            }

            errorMessage = """
            The configured \(ContentRootConfiguration.contentRootEnvironmentVariable) path is invalid.
            Choose a directory containing extracted SwiftOOT content.
            """
            return
        }

        guard let storedPath = userDefaults.string(forKey: Self.storedContentRootDefaultsKey) else {
            return
        }

        let storedURL = URL(fileURLWithPath: storedPath, isDirectory: true)
        if applyConfiguredRoot(storedURL, persistSelection: false) {
            startupHint = "Using saved content root."
            if developerHarnessConfiguration?.isEnabled == true {
                startupHint?.append(" Developer harness enabled.")
            }
            return
        }

        userDefaults.removeObject(forKey: Self.storedContentRootDefaultsKey)
        errorMessage = """
        The previously saved content directory is no longer valid.
        Choose a directory containing extracted SwiftOOT content.
        """
    }

    @discardableResult
    func applyConfiguredRoot(
        _ selectedURL: URL,
        persistSelection: Bool = true
    ) -> Bool {
        startupTask?.cancel()
        startupTask = nil

        if case .failure(let error) = developerHarnessConfigurationResult {
            errorMessage = error.localizedDescription
            return false
        }

        guard let resolvedContentRoot = ContentRootConfiguration.resolveConfiguredContentRoot(from: selectedURL) else {
            errorMessage = """
            SwiftOOT could not find extracted content there.
            Choose either the extracted content root or a repo root that contains Content/OOT.
            """
            return false
        }

        let sceneLoader = SceneLoader(contentRoot: resolvedContentRoot)
        configuredContentRoot = resolvedContentRoot
        runtime = GameRuntime(
            contentLoader: ContentLoader(sceneLoader: sceneLoader),
            sceneLoader: sceneLoader
        )
        errorMessage = nil
        startRuntimeIfNeeded()

        if persistSelection {
            userDefaults.set(resolvedContentRoot.path, forKey: Self.storedContentRootDefaultsKey)
        }

        return true
    }

    func startRuntimeIfNeeded() {
        guard startupTask == nil, let runtime else {
            return
        }

        let harness = developerHarnessConfiguration
        startupTask = Task { @MainActor [weak self] in
            defer {
                self?.startupTask = nil
            }

            do {
                if let harness, harness.isEnabled {
                    try await DeveloperHarnessRunner.run(
                        configuration: harness,
                        runtime: runtime,
                        log: { [weak self] message in
                            self?.writeHarnessNoteToStderr(message, harness: harness)
                        }
                    )
                    if harness.captureRequested {
                        NSApplication.shared.terminate(nil)
                    }
                } else {
                    await runtime.start()
                }
            } catch is CancellationError {
                return
            } catch {
                runtime.errorMessage = error.localizedDescription
                if let harness {
                    self?.writeHarnessFailureToStderr(error.localizedDescription, harness: harness)
                    if harness.captureRequested {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
    }

    func clearConfiguration() {
        startupTask?.cancel()
        startupTask = nil
        userDefaults.removeObject(forKey: Self.storedContentRootDefaultsKey)
        configuredContentRoot = nil
        runtime = nil
        errorMessage = nil
        startupHint = nil
    }
    private func writeHarnessFailureToStderr(
        _ message: String,
        harness: DeveloperHarnessConfiguration
    ) {
        let line = "SwiftOOT harness failed: \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        try? FileHandle.standardError.write(contentsOf: data)
        appendHarnessTrace(line, harness: harness)
    }

    private func writeHarnessNoteToStderr(
        _ message: String,
        harness: DeveloperHarnessConfiguration
    ) {
        let line = "SwiftOOT harness: \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        try? FileHandle.standardError.write(contentsOf: data)
        appendHarnessTrace(line, harness: harness)
    }

    private func appendHarnessTrace(
        _ line: String,
        harness: DeveloperHarnessConfiguration
    ) {
        guard let directory = (harness.captureStateURL ?? harness.captureFrameURL)?.deletingLastPathComponent() else {
            return
        }

        let fileManager = FileManager.default
        let logURL = directory.appendingPathComponent("harness.log")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
            return
        }

        try? Data(line.utf8).write(to: logURL, options: .atomic)
    }
}

struct OOTContentBootstrapView: View {
    let model: OOTContentBootstrapModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.10, green: 0.13, blue: 0.20),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Text("SwiftOOT Setup")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Choose extracted SwiftOOT content before launching the runtime.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Supported choices")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("• An extracted content root containing Manifests/tables/scene-table.json")
                    Text("• A repo root that contains Content/OOT")
                }
                .font(.body)
                .foregroundStyle(.white.opacity(0.78))

                if let configuredContentRoot = model.configuredContentRoot {
                    Text("Current content root: \(configuredContentRoot.path)")
                        .font(.callout.monospaced())
                        .foregroundStyle(Color(red: 0.91, green: 0.96, blue: 1.0))
                        .textSelection(.enabled)
                }

                if let startupHint = model.startupHint {
                    Text(startupHint)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(red: 0.75, green: 0.92, blue: 0.73))
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(red: 0.98, green: 0.77, blue: 0.72))
                }

                HStack(spacing: 14) {
                    Button("Choose Content Directory") {
                        chooseContentDirectory()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Clear Saved Selection") {
                        model.clearConfiguration()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("If you have not extracted content yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("1. Provide your own ROM in Vendor/oot/baseroms/<version>/baserom.{z64,n64,v64}")
                    Text("2. Run Vendor/oot setup")
                    Text("3. Run OOTExtractCLI to generate local SwiftOOT content")
                }
                .font(.callout)
                .foregroundStyle(.white.opacity(0.74))

                Spacer()
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func chooseContentDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Use Content Directory"
        panel.message = "Choose extracted SwiftOOT content or a repo root containing Content/OOT."

        if panel.runModal() == .OK, let selectedURL = panel.url {
            _ = model.applyConfiguredRoot(selectedURL)
        }
    }
}

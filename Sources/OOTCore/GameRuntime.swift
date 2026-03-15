import Observation
import Foundation
import OOTContent
import OOTDataModel
import OOTTelemetry

@MainActor
@Observable
public final class GameRuntime {
    public enum State: Sendable, Equatable {
        case idle
        case loadingContent
        case running
    }

    public var state: State
    public var availableScenes: [SceneTableEntry]
    public var selectedSceneID: Int?
    public var loadedScene: LoadedScene?
    public var textureAssetURLs: [UInt32: URL]
    public var errorMessage: String?

    @ObservationIgnored
    public let contentLoader: any ContentLoading

    @ObservationIgnored
    public let sceneLoader: any SceneLoading

    @ObservationIgnored
    public let telemetryPublisher: any TelemetryPublishing

    public init(
        state: State = .idle,
        availableScenes: [SceneTableEntry] = [],
        selectedSceneID: Int? = nil,
        loadedScene: LoadedScene? = nil,
        textureAssetURLs: [UInt32: URL] = [:],
        errorMessage: String? = nil,
        contentLoader: any ContentLoading = ContentLoader(),
        sceneLoader: any SceneLoading = SceneLoader(),
        telemetryPublisher: any TelemetryPublishing = TelemetryPublisher()
    ) {
        self.state = state
        self.availableScenes = availableScenes
        self.selectedSceneID = selectedSceneID
        self.loadedScene = loadedScene
        self.textureAssetURLs = textureAssetURLs
        self.errorMessage = errorMessage
        self.contentLoader = contentLoader
        self.sceneLoader = sceneLoader
        self.telemetryPublisher = telemetryPublisher
    }

    public func bootstrapSceneViewer() async {
        guard availableScenes.isEmpty || loadedScene == nil else {
            return
        }

        let previousScene = loadedScene
        state = .loadingContent
        errorMessage = nil

        do {
            let snapshot = try await loadSceneViewerSnapshot(defaultSceneID: nil)
            apply(snapshot)

            if loadedScene == nil {
                state = .idle
                errorMessage = "No extracted scenes were found under the configured content root."
            } else {
                state = .running
            }
        } catch {
            loadedScene = previousScene
            state = previousScene == nil ? .idle : .running
            errorMessage = error.localizedDescription
        }
    }

    public func selectScene(id: Int) async {
        guard selectedSceneID != id || loadedScene?.manifest.id != id else {
            return
        }

        let previousScene = loadedScene
        let previousTextureAssetURLs = textureAssetURLs
        let previousSelectedSceneID = selectedSceneID

        state = .loadingContent
        errorMessage = nil

        do {
            let snapshot = try await loadSceneViewerSnapshot(defaultSceneID: id)
            apply(snapshot)
            state = loadedScene == nil ? .idle : .running
        } catch {
            loadedScene = previousScene
            textureAssetURLs = previousTextureAssetURLs
            selectedSceneID = previousSelectedSceneID
            state = previousScene == nil ? .idle : .running
            errorMessage = error.localizedDescription
        }
    }
}

private extension GameRuntime {
    struct SceneViewerSnapshot: Sendable {
        let availableScenes: [SceneTableEntry]
        let selectedSceneID: Int?
        let loadedScene: LoadedScene?
        let textureAssetURLs: [UInt32: URL]
    }

    func apply(_ snapshot: SceneViewerSnapshot) {
        availableScenes = snapshot.availableScenes
        selectedSceneID = snapshot.selectedSceneID
        loadedScene = snapshot.loadedScene
        textureAssetURLs = snapshot.textureAssetURLs
    }

    func loadSceneViewerSnapshot(defaultSceneID: Int?) async throws -> SceneViewerSnapshot {
        let sceneLoader = self.sceneLoader
        return try await Task.detached(priority: .userInitiated) {
            let sceneTableEntries = try sceneLoader.loadSceneTableEntries()
            let availableScenes = sceneTableEntries.filter { entry in
                (try? sceneLoader.resolveSceneDirectory(for: entry.index)) != nil
            }

            let selectedSceneID =
                defaultSceneID ??
                availableScenes.first(where: { Self.sceneName(for: $0) == "spot04" })?.index ??
                availableScenes.first?.index

            guard let selectedSceneID else {
                return SceneViewerSnapshot(
                    availableScenes: availableScenes,
                    selectedSceneID: nil,
                    loadedScene: nil,
                    textureAssetURLs: [:]
                )
            }

            let loadedScene = try sceneLoader.loadScene(id: selectedSceneID)
            let textureAssetURLs = try sceneLoader.loadTextureAssetURLs(for: loadedScene)

            return SceneViewerSnapshot(
                availableScenes: availableScenes,
                selectedSceneID: selectedSceneID,
                loadedScene: loadedScene,
                textureAssetURLs: textureAssetURLs
            )
        }.value
    }

    nonisolated static func sceneName(for entry: SceneTableEntry) -> String {
        if entry.segmentName.hasSuffix("_scene") {
            return String(entry.segmentName.dropLast("_scene".count))
        }
        return entry.segmentName
    }
}

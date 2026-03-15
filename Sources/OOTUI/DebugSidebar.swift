import SwiftUI
import OOTContent
import OOTDataModel
import OOTRender

public struct DebugSidebar: View {
    private let availableScenes: [SceneTableEntry]
    private let selectedSceneID: Int?
    private let loadedScene: LoadedScene?
    private let isLoading: Bool
    private let errorMessage: String?
    private let drawCallCount: Int
    private let onSelectScene: @Sendable (Int) -> Void

    public init(
        availableScenes: [SceneTableEntry] = [],
        selectedSceneID: Int? = nil,
        loadedScene: LoadedScene? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        drawCallCount: Int = 0,
        onSelectScene: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.availableScenes = availableScenes
        self.selectedSceneID = selectedSceneID
        self.loadedScene = loadedScene
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.drawCallCount = drawCallCount
        self.onSelectScene = onSelectScene
    }

    public var body: some View {
        List {
            Section("Scene") {
                if availableScenes.isEmpty {
                    Text("No extracted scenes found.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Selected Scene",
                        selection: Binding(
                            get: { selectedSceneID ?? availableScenes[0].index },
                            set: onSelectScene
                        )
                    ) {
                        ForEach(availableScenes, id: \.index) { scene in
                            Text(sceneLabel(for: scene))
                                .tag(scene.index)
                        }
                    }
                    .labelsHidden()
                    .disabled(isLoading)
                }
            }

            Section("Info") {
                LabeledContent("Name", value: loadedScene?.manifest.name ?? "Unavailable")
                LabeledContent("Rooms", value: "\(loadedScene?.rooms.count ?? 0)")
                LabeledContent("Vertices", value: "\(vertexCount)")
                LabeledContent("Draw Calls", value: "\(drawCallCount)")
            }

            Section("Status") {
                Text(statusText)
                    .foregroundStyle(isLoading ? .secondary : .primary)

                if let errorMessage, errorMessage.isEmpty == false {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Scenes")
    }

    private var vertexCount: Int {
        loadedScene?.rooms.reduce(0) { partialResult, room in
            partialResult + (room.vertexData.count / MemoryLayout<N64Vertex>.stride)
        } ?? 0
    }

    private var statusText: String {
        if isLoading {
            return "Loading scene..."
        }
        if loadedScene != nil {
            return "Ready"
        }
        return "Waiting for content"
    }

    private func sceneLabel(for scene: SceneTableEntry) -> String {
        let shortName: String
        if scene.segmentName.hasSuffix("_scene") {
            shortName = String(scene.segmentName.dropLast("_scene".count))
        } else {
            shortName = scene.segmentName
        }
        return "\(shortName) • \(scene.enumName)"
    }
}

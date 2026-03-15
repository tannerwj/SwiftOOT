import Foundation
import OOTDataModel

public protocol ContentLoading: Sendable {
    func loadInitialContent() async throws
    func loadScene(id: Int) async throws -> LoadedScene
    func loadActorTable() async throws -> [ActorTableEntry]
}

public struct ContentLoader: ContentLoading {
    private let sceneLoader: any SceneLoading

    public init(
        contentRoot: URL? = nil,
        sceneLoader: (any SceneLoading)? = nil
    ) {
        self.sceneLoader = sceneLoader ?? SceneLoader(contentRoot: contentRoot)
    }

    public func loadInitialContent() async throws {}

    public func loadScene(id: Int) async throws -> LoadedScene {
        try sceneLoader.loadScene(id: id)
    }

    public func loadActorTable() async throws -> [ActorTableEntry] {
        try sceneLoader.loadActorTable()
    }
}

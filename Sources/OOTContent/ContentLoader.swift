import Foundation
import OOTDataModel

public protocol ContentLoading: Sendable {
    func loadInitialContent() async throws
    func loadScene(id: Int) throws -> LoadedScene
    func loadActorTable() throws -> [ActorTableEntry]
}

public enum ContentLoaderError: Error, LocalizedError, Sendable, Equatable {
    case sceneLoadingUnavailable

    public var errorDescription: String? {
        switch self {
        case .sceneLoadingUnavailable:
            "Scene-backed gameplay content is unavailable in the current content loader."
        }
    }
}

public extension ContentLoading {
    func loadScene(id: Int) throws -> LoadedScene {
        throw ContentLoaderError.sceneLoadingUnavailable
    }

    func loadActorTable() throws -> [ActorTableEntry] {
        throw ContentLoaderError.sceneLoadingUnavailable
    }
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

    public func loadScene(id: Int) throws -> LoadedScene {
        try sceneLoader.loadScene(id: id)
    }

    public func loadActorTable() throws -> [ActorTableEntry] {
        try sceneLoader.loadActorTable()
    }
}

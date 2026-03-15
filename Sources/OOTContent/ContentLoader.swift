import Foundation
import OOTDataModel

public protocol ContentLoading: Sendable {
    func loadInitialContent() async throws
    func loadScene(id: Int) throws -> LoadedScene
    func loadActorTable() throws -> [ActorTableEntry]
    func loadMessageCatalog() throws -> MessageCatalog
    func loadObjectTable() throws -> [ObjectTableEntry]
    func loadObject(named name: String) throws -> LoadedObject
}

public enum ContentLoaderError: Error, LocalizedError, Sendable, Equatable {
    case sceneLoadingUnavailable
    case messageLoadingUnavailable

    public var errorDescription: String? {
        switch self {
        case .sceneLoadingUnavailable:
            "Scene-backed gameplay content is unavailable in the current content loader."
        case .messageLoadingUnavailable:
            "Message-backed gameplay content is unavailable in the current content loader."
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

    func loadMessageCatalog() throws -> MessageCatalog {
        throw ContentLoaderError.messageLoadingUnavailable
    }

    func loadObjectTable() throws -> [ObjectTableEntry] {
        throw ContentLoaderError.sceneLoadingUnavailable
    }

    func loadObject(named name: String) throws -> LoadedObject {
        throw ContentLoaderError.sceneLoadingUnavailable
    }
}

public struct ContentLoader: ContentLoading {
    private let sceneLoader: any SceneLoading
    private let messageLoader: any MessageLoading

    public init(
        contentRoot: URL? = nil,
        sceneLoader: (any SceneLoading)? = nil,
        messageLoader: (any MessageLoading)? = nil
    ) {
        self.sceneLoader = sceneLoader ?? SceneLoader(contentRoot: contentRoot)
        self.messageLoader = messageLoader ?? MessageLoader(contentRoot: contentRoot)
    }

    public func loadInitialContent() async throws {}

    public func loadScene(id: Int) throws -> LoadedScene {
        try sceneLoader.loadScene(id: id)
    }

    public func loadActorTable() throws -> [ActorTableEntry] {
        try sceneLoader.loadActorTable()
    }

    public func loadMessageCatalog() throws -> MessageCatalog {
        try messageLoader.loadMessageCatalog()
    }

    public func loadObjectTable() throws -> [ObjectTableEntry] {
        try sceneLoader.loadObjectTable()
    }

    public func loadObject(named name: String) throws -> LoadedObject {
        try sceneLoader.loadObject(named: name)
    }
}

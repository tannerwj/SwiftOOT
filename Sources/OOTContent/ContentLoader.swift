import Foundation
import OSLog
import OOTDataModel

public protocol ContentLoading: Sendable {
    func loadInitialContent() async throws
    func loadScene(id: Int) throws -> LoadedScene
    func loadActorTable() throws -> [ActorTableEntry]
    func loadAudioTrackCatalog() throws -> AudioTrackCatalog
    func loadMessageCatalog() throws -> MessageCatalog
    func loadSoundEffectCatalog() throws -> SoundEffectCatalog
    func loadObjectTable() throws -> [ObjectTableEntry]
    func loadObject(named name: String) throws -> LoadedObject
    func loadEntranceTable() throws -> [EntranceTableEntry]
    func resolveContentURL(relativePath: String) throws -> URL
}

public enum ContentLoaderError: Error, LocalizedError, Sendable, Equatable {
    case sceneLoadingUnavailable
    case messageLoadingUnavailable
    case audioLoadingUnavailable
    case invalidReferencedPath(String)

    public var errorDescription: String? {
        switch self {
        case .sceneLoadingUnavailable:
            "Scene-backed gameplay content is unavailable in the current content loader."
        case .messageLoadingUnavailable:
            "Message-backed gameplay content is unavailable in the current content loader."
        case .audioLoadingUnavailable:
            "Audio-backed gameplay content is unavailable in the current content loader."
        case .invalidReferencedPath(let path):
            "Content path escapes the configured content root: \(path)."
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

    func loadAudioTrackCatalog() throws -> AudioTrackCatalog {
        throw ContentLoaderError.audioLoadingUnavailable
    }

    func loadMessageCatalog() throws -> MessageCatalog {
        throw ContentLoaderError.messageLoadingUnavailable
    }

    func loadSoundEffectCatalog() throws -> SoundEffectCatalog {
        throw ContentLoaderError.audioLoadingUnavailable
    }

    func loadObjectTable() throws -> [ObjectTableEntry] {
        throw ContentLoaderError.sceneLoadingUnavailable
    }

    func loadObject(named name: String) throws -> LoadedObject {
        throw ContentLoaderError.sceneLoadingUnavailable
    }

    func loadEntranceTable() throws -> [EntranceTableEntry] {
        throw ContentLoaderError.sceneLoadingUnavailable
    }

    func resolveContentURL(relativePath: String) throws -> URL {
        throw ContentLoaderError.audioLoadingUnavailable
    }
}

public struct ContentLoader: ContentLoading {
    private let sceneLoader: any SceneLoading
    private let audioTrackCatalogLoader: any AudioTrackCatalogLoading
    private let messageLoader: any MessageLoading
    private let soundEffectLoader: any SoundEffectLoading
    private let contentRoot: URL?

    public init(
        contentRoot: URL? = nil,
        sceneLoader: (any SceneLoading)? = nil,
        audioTrackCatalogLoader: (any AudioTrackCatalogLoading)? = nil,
        messageLoader: (any MessageLoading)? = nil,
        soundEffectLoader: (any SoundEffectLoading)? = nil
    ) {
        let resolvedSceneLoader = sceneLoader ?? SceneLoader(contentRoot: contentRoot)
        let resolvedAudioTrackCatalogLoader = audioTrackCatalogLoader ?? AudioTrackCatalogLoader(contentRoot: contentRoot)
        let resolvedMessageLoader = messageLoader ?? MessageLoader(contentRoot: contentRoot)
        let resolvedSoundEffectLoader = soundEffectLoader ?? SoundEffectLoader(contentRoot: contentRoot)

        self.sceneLoader = resolvedSceneLoader
        self.audioTrackCatalogLoader = resolvedAudioTrackCatalogLoader
        self.messageLoader = resolvedMessageLoader
        self.soundEffectLoader = resolvedSoundEffectLoader
        self.contentRoot = contentRoot?.standardizedFileURL ??
            (resolvedSceneLoader as? SceneLoader)?.contentRoot ??
            (resolvedAudioTrackCatalogLoader as? AudioTrackCatalogLoader)?.contentRoot ??
            (resolvedMessageLoader as? MessageLoader)?.contentRoot ??
            (resolvedSoundEffectLoader as? SoundEffectLoader)?.contentRoot
    }

    public func loadInitialContent() async throws {}

    public func loadScene(id: Int) throws -> LoadedScene {
        do {
            return try sceneLoader.loadScene(id: id)
        } catch SceneLoaderError.unresolvedSceneDirectory(let sceneID) {
            os_log(
                .error,
                log: contentLoaderLog,
                "%{public}@",
                "Unable to resolve a scene directory for scene id \(sceneID)."
            )
            throw SceneLoaderError.unresolvedSceneDirectory(sceneID)
        } catch SceneLoaderError.missingFile(let path) {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            if filename == "SceneManifest.json" || filename == "scene_manifest.json" || filename == "Scenes" {
                os_log(
                    .error,
                    log: contentLoaderLog,
                    "%{public}@",
                    "Missing scene content while loading scene id \(id) at \(path)."
                )
            }
            throw SceneLoaderError.missingFile(path)
        }
    }

    public func loadActorTable() throws -> [ActorTableEntry] {
        try sceneLoader.loadActorTable()
    }

    public func loadAudioTrackCatalog() throws -> AudioTrackCatalog {
        try audioTrackCatalogLoader.loadAudioTrackCatalog()
    }

    public func loadMessageCatalog() throws -> MessageCatalog {
        try messageLoader.loadMessageCatalog()
    }

    public func loadSoundEffectCatalog() throws -> SoundEffectCatalog {
        try soundEffectLoader.loadSoundEffectCatalog()
    }

    public func loadObjectTable() throws -> [ObjectTableEntry] {
        try sceneLoader.loadObjectTable()
    }

    public func loadObject(named name: String) throws -> LoadedObject {
        try sceneLoader.loadObject(named: name)
    }

    public func loadEntranceTable() throws -> [EntranceTableEntry] {
        try sceneLoader.loadEntranceTable()
    }

    public func resolveContentURL(relativePath: String) throws -> URL {
        guard let contentRoot else {
            throw ContentLoaderError.audioLoadingUnavailable
        }

        let resolvedURL = contentRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let contentRootPath = contentRoot.standardizedFileURL.path

        guard resolvedURL.path == contentRootPath || resolvedURL.path.hasPrefix(contentRootPath + "/") else {
            throw ContentLoaderError.invalidReferencedPath(relativePath)
        }

        return resolvedURL
    }
}

private let contentLoaderLog = OSLog(subsystem: "com.swiftoot", category: "OOTContent")

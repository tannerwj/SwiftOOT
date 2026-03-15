import Foundation
import OOTDataModel

public protocol SceneLoading: Sendable {
    func resolveSceneDirectory(for sceneID: Int) throws -> URL
    func loadScene(id: Int) throws -> LoadedScene
    func loadScene(named name: String) throws -> LoadedScene
    func loadSceneManifest(id: Int) throws -> SceneManifest
    func loadSceneManifest(named name: String) throws -> SceneManifest
    func loadRoomDisplayList(for room: RoomManifest) throws -> [F3DEX2Command]
    func loadRoomVertexData(for room: RoomManifest) throws -> Data
}

public struct LoadedScene: Sendable, Equatable {
    public var manifest: SceneManifest
    public var actors: SceneActorsFile?
    public var environment: SceneEnvironmentFile?
    public var paths: ScenePathsFile?
    public var rooms: [LoadedSceneRoom]

    public init(
        manifest: SceneManifest,
        actors: SceneActorsFile? = nil,
        environment: SceneEnvironmentFile? = nil,
        paths: ScenePathsFile? = nil,
        rooms: [LoadedSceneRoom]
    ) {
        self.manifest = manifest
        self.actors = actors
        self.environment = environment
        self.paths = paths
        self.rooms = rooms
    }
}

public struct LoadedSceneRoom: Sendable, Equatable {
    public var manifest: RoomManifest
    public var displayList: [F3DEX2Command]
    public var vertexData: Data

    public init(
        manifest: RoomManifest,
        displayList: [F3DEX2Command],
        vertexData: Data
    ) {
        self.manifest = manifest
        self.displayList = displayList
        self.vertexData = vertexData
    }
}

public struct SceneLoader: SceneLoading {
    public let contentRoot: URL

    public init(contentRoot: URL? = nil) {
        self.contentRoot = (contentRoot ?? Self.defaultContentRoot()).standardizedFileURL
    }

    public func resolveSceneDirectory(for sceneID: Int) throws -> URL {
        let table = try loadSceneTable()
        guard let entry = table.first(where: { $0.index == sceneID }) else {
            throw SceneLoaderError.unknownSceneID(sceneID)
        }

        for candidate in sceneNameCandidates(for: entry) {
            let directory = scenesRoot.appendingPathComponent(candidate, isDirectory: true)
            if try manifestURL(in: directory) != nil {
                return directory
            }
        }

        guard let scannedDirectory = try resolveSceneDirectoryByScanning(for: sceneID) else {
            throw SceneLoaderError.unresolvedSceneDirectory(sceneID)
        }

        return scannedDirectory
    }

    public func loadScene(id: Int) throws -> LoadedScene {
        let directory = try resolveSceneDirectory(for: id)
        return try loadScene(from: directory)
    }

    public func loadScene(named name: String) throws -> LoadedScene {
        let directory = scenesRoot.appendingPathComponent(name, isDirectory: true)
        return try loadScene(from: directory)
    }

    public func loadSceneManifest(id: Int) throws -> SceneManifest {
        let directory = try resolveSceneDirectory(for: id)
        return try loadSceneManifest(from: directory)
    }

    public func loadSceneManifest(named name: String) throws -> SceneManifest {
        let directory = scenesRoot.appendingPathComponent(name, isDirectory: true)
        return try loadSceneManifest(from: directory)
    }

    public func loadRoomDisplayList(for room: RoomManifest) throws -> [F3DEX2Command] {
        try loadJSON(
            [F3DEX2Command].self,
            from: try roomFileURL(room, filename: "dl.json")
        )
    }

    public func loadRoomVertexData(for room: RoomManifest) throws -> Data {
        try readData(from: try roomFileURL(room, filename: "vtx.bin"))
    }

    public func loadActors(for manifest: SceneManifest) throws -> SceneActorsFile? {
        try loadOptionalJSON(SceneActorsFile.self, fromRelativePath: manifest.actorsPath)
    }

    public func loadEnvironment(for manifest: SceneManifest) throws -> SceneEnvironmentFile? {
        try loadOptionalJSON(SceneEnvironmentFile.self, fromRelativePath: manifest.environmentPath)
    }

    public func loadPaths(for manifest: SceneManifest) throws -> ScenePathsFile? {
        try loadOptionalJSON(ScenePathsFile.self, fromRelativePath: manifest.pathsPath)
    }
}

public enum SceneLoaderError: Error, LocalizedError, Equatable, Sendable {
    case unknownSceneID(Int)
    case unresolvedSceneDirectory(Int)
    case missingFile(String)
    case invalidReferencedPath(String)
    case unreadableFile(String, String)
    case invalidJSON(String, String)

    public var errorDescription: String? {
        switch self {
        case .unknownSceneID(let sceneID):
            "No scene table entry exists for scene id \(sceneID)."
        case .unresolvedSceneDirectory(let sceneID):
            "Unable to resolve a scene directory for scene id \(sceneID)."
        case .missingFile(let path):
            "Missing required scene content file at \(path)."
        case .invalidReferencedPath(let path):
            "Scene content path escapes the configured content root: \(path)."
        case .unreadableFile(let path, let message):
            "Unable to read scene content file at \(path): \(message)"
        case .invalidJSON(let path, let message):
            "Invalid JSON at \(path): \(message)"
        }
    }
}

private extension SceneLoader {
    static let legacyManifestFilename = "scene_manifest.json"
    static let manifestFilename = "SceneManifest.json"

    static func defaultContentRoot() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Content", isDirectory: true)
            .appendingPathComponent("OOT", isDirectory: true)
    }

    var scenesRoot: URL {
        contentRoot.appendingPathComponent("Scenes", isDirectory: true)
    }

    var sceneTableURL: URL {
        contentRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("tables", isDirectory: true)
            .appendingPathComponent("scene-table.json")
    }

    func loadScene(from directory: URL) throws -> LoadedScene {
        let manifest = try loadSceneManifest(from: directory)

        return try LoadedScene(
            manifest: manifest,
            actors: loadActors(for: manifest),
            environment: loadEnvironment(for: manifest),
            paths: loadPaths(for: manifest),
            rooms: manifest.rooms.map { room in
                try LoadedSceneRoom(
                    manifest: room,
                    displayList: loadRoomDisplayList(for: room),
                    vertexData: loadRoomVertexData(for: room)
                )
            }
        )
    }

    func loadSceneManifest(from directory: URL) throws -> SceneManifest {
        guard let manifestURL = try manifestURL(in: directory) else {
            throw SceneLoaderError.missingFile(
                directory.appendingPathComponent(Self.manifestFilename).path
            )
        }

        return try loadJSON(SceneManifest.self, from: manifestURL)
    }

    func manifestURL(in directory: URL) throws -> URL? {
        let candidates = [
            directory.appendingPathComponent(Self.manifestFilename),
            directory.appendingPathComponent(Self.legacyManifestFilename),
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    func resolveSceneDirectoryByScanning(for sceneID: Int) throws -> URL? {
        guard FileManager.default.fileExists(atPath: scenesRoot.path) else {
            throw SceneLoaderError.missingFile(scenesRoot.path)
        }

        let directories = try FileManager.default.contentsOfDirectory(
            at: scenesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for directory in directories {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                continue
            }

            guard let manifestURL = try manifestURL(in: directory) else {
                continue
            }

            let manifest = try loadJSON(SceneManifest.self, from: manifestURL)
            if manifest.id == sceneID {
                return directory
            }
        }

        return nil
    }

    func loadSceneTable() throws -> [SceneTableEntry] {
        try loadJSON([SceneTableEntry].self, from: sceneTableURL)
    }

    func loadOptionalJSON<T: Decodable>(_ type: T.Type, fromRelativePath relativePath: String?) throws -> T? {
        guard let relativePath, relativePath.isEmpty == false else {
            return nil
        }

        return try loadJSON(T.self, from: try referencedURL(for: relativePath))
    }

    func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try readData(from: url)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SceneLoaderError.invalidJSON(url.path, error.localizedDescription)
        }
    }

    func readData(from url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SceneLoaderError.missingFile(url.path)
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw SceneLoaderError.unreadableFile(url.path, error.localizedDescription)
        }
    }

    func roomFileURL(_ room: RoomManifest, filename: String) throws -> URL {
        try referencedURL(for: room.directory).appendingPathComponent(filename)
    }

    func referencedURL(for relativePath: String) throws -> URL {
        let rootPath = contentRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let target = contentRoot
            .appendingPathComponent(relativePath, isDirectory: false)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let targetPath = target.path

        if targetPath == rootPath {
            return target
        }

        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(prefix) else {
            throw SceneLoaderError.invalidReferencedPath(relativePath)
        }

        return target
    }

    func sceneNameCandidates(for entry: SceneTableEntry) -> [String] {
        let strippedSegmentName: String
        if entry.segmentName.hasSuffix("_scene") {
            strippedSegmentName = String(entry.segmentName.dropLast("_scene".count))
        } else {
            strippedSegmentName = entry.segmentName
        }

        var candidates: [String] = []
        var seen: Set<String> = []

        for candidate in [strippedSegmentName, entry.segmentName] where seen.insert(candidate).inserted {
            candidates.append(candidate)
        }

        return candidates
    }
}

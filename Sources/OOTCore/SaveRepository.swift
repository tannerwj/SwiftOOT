import CryptoKit
import Foundation

public struct SaveSpawnLocation: Codable, Sendable, Equatable {
    public var sceneID: Int?
    public var sceneName: String
    public var entranceIndex: Int?
    public var spawnIndex: Int?

    public init(
        sceneID: Int? = nil,
        sceneName: String = "Unused",
        entranceIndex: Int? = nil,
        spawnIndex: Int? = nil
    ) {
        self.sceneID = sceneID
        self.sceneName = sceneName
        self.entranceIndex = entranceIndex
        self.spawnIndex = spawnIndex
    }
}

public struct SaveRuntimeState: Codable, Sendable, Equatable {
    public var currentMagic: Int
    public var maximumMagic: Int
    public var rupees: Int
    public var globalEventFlags: Set<Int>
    public var sceneEventFlags: [SceneIdentity: Set<Int>]
    public var spawnLocation: SaveSpawnLocation
    public var playTimeFrames: Int
    public var deathCount: Int
    public var goldSkulltulaFlags: Set<TreasureFlagKey>

    public init(
        currentMagic: Int = 0,
        maximumMagic: Int = 0,
        rupees: Int = 0,
        globalEventFlags: Set<Int> = [],
        sceneEventFlags: [SceneIdentity: Set<Int>] = [:],
        spawnLocation: SaveSpawnLocation = SaveSpawnLocation(),
        playTimeFrames: Int = 0,
        deathCount: Int = 0,
        goldSkulltulaFlags: Set<TreasureFlagKey> = []
    ) {
        let normalizedMaximumMagic = max(0, maximumMagic)
        self.currentMagic = min(max(0, currentMagic), normalizedMaximumMagic)
        self.maximumMagic = normalizedMaximumMagic
        self.rupees = max(0, rupees)
        self.globalEventFlags = globalEventFlags
        self.sceneEventFlags = sceneEventFlags
        self.spawnLocation = spawnLocation
        self.playTimeFrames = max(0, playTimeFrames)
        self.deathCount = max(0, deathCount)
        self.goldSkulltulaFlags = goldSkulltulaFlags
    }

    public static func starter(sceneName: String) -> Self {
        SaveRuntimeState(
            currentMagic: 48,
            maximumMagic: 96,
            rupees: 0,
            spawnLocation: SaveSpawnLocation(sceneName: sceneName)
        )
    }
}

public struct SaveRepository: Sendable {
    public enum Error: LocalizedError {
        case checksumMismatch
        case invalidFormat
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .checksumMismatch:
                return "The save data checksum did not match the stored payload."
            case .invalidFormat:
                return "The save data file could not be decoded."
            case .unsupportedVersion(let version):
                return "The save data schema version \(version) is not supported."
            }
        }
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupportRepository(
        bundleIdentifier: String = "com.tannerwj.SwiftOOT",
        fileManager: FileManager = .default
    ) throws -> SaveRepository {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let saveDirectory = applicationSupportURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Saves", isDirectory: true)
        return SaveRepository(
            fileURL: saveDirectory.appendingPathComponent("save-context.json", isDirectory: false)
        )
    }

    public func loadSaveContextIfPresent() throws -> SaveContext? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()

        if let envelope = try? decoder.decode(SaveFileEnvelope.self, from: data) {
            return try migrateSaveContext(
                payload: envelope.payload,
                checksum: envelope.checksum,
                version: envelope.version
            )
        }

        if let legacyContext = try? decoder.decode(SaveContext.self, from: data) {
            return legacyContext
        }

        throw Error.invalidFormat
    }

    public func save(_ saveContext: SaveContext) throws {
        let payloadEncoder = JSONEncoder()
        payloadEncoder.outputFormatting = [.sortedKeys]
        let payload = try payloadEncoder.encode(saveContext)

        let envelope = SaveFileEnvelope(
            version: SaveFileEnvelope.currentVersion,
            checksum: Self.checksum(for: payload),
            payload: payload
        )

        let fileEncoder = JSONEncoder()
        fileEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try fileEncoder.encode(envelope)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private func migrateSaveContext(
        payload: Data,
        checksum: String,
        version: Int
    ) throws -> SaveContext {
        guard Self.checksum(for: payload) == checksum else {
            throw Error.checksumMismatch
        }

        let decoder = JSONDecoder()
        switch version {
        case SaveFileEnvelope.currentVersion:
            return try decoder.decode(SaveContext.self, from: payload)
        default:
            throw Error.unsupportedVersion(version)
        }
    }

    private static func checksum(for payload: Data) -> String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }
}

private struct SaveFileEnvelope: Codable, Sendable, Equatable {
    static let currentVersion = 1

    let version: Int
    let checksum: String
    let payload: Data
}

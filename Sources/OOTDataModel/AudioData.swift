public enum AudioTrackKind: String, Codable, Sendable, Equatable {
    case bgm
    case fanfare
}

public struct AudioTrackManifest: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var kind: AudioTrackKind
    public var sequenceID: Int
    public var sequenceEnumName: String
    public var assetDirectory: String
    public var sequencePath: String
    public var sequenceMetadataPath: String
    public var soundfontPaths: [String]
    public var sampleBankPaths: [String]
    public var samplePaths: [String]

    public init(
        id: String,
        title: String,
        kind: AudioTrackKind,
        sequenceID: Int,
        sequenceEnumName: String,
        assetDirectory: String,
        sequencePath: String,
        sequenceMetadataPath: String,
        soundfontPaths: [String],
        sampleBankPaths: [String],
        samplePaths: [String]
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.sequenceID = sequenceID
        self.sequenceEnumName = sequenceEnumName
        self.assetDirectory = assetDirectory
        self.sequencePath = sequencePath
        self.sequenceMetadataPath = sequenceMetadataPath
        self.soundfontPaths = soundfontPaths
        self.sampleBankPaths = sampleBankPaths
        self.samplePaths = samplePaths
    }
}

public struct AudioSceneBinding: Codable, Sendable, Equatable {
    public var sceneName: String
    public var sceneID: Int?
    public var sequenceID: Int
    public var sequenceEnumName: String
    public var trackID: String

    public init(
        sceneName: String,
        sceneID: Int? = nil,
        sequenceID: Int,
        sequenceEnumName: String,
        trackID: String
    ) {
        self.sceneName = sceneName
        self.sceneID = sceneID
        self.sequenceID = sequenceID
        self.sequenceEnumName = sequenceEnumName
        self.trackID = trackID
    }
}

public struct AudioTrackCatalog: Codable, Sendable, Equatable {
    public var version: Int
    public var tracks: [AudioTrackManifest]
    public var sceneBindings: [AudioSceneBinding]

    public init(
        version: Int = 1,
        tracks: [AudioTrackManifest],
        sceneBindings: [AudioSceneBinding]
    ) {
        self.version = version
        self.tracks = tracks
        self.sceneBindings = sceneBindings
    }
}

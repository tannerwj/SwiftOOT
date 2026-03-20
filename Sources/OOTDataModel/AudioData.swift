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

public enum NamedSoundEffect: String, Codable, CaseIterable, Sendable, Equatable {
    case uiConfirm = "ui-confirm"
    case uiCancel = "ui-cancel"
    case talkConfirm = "talk-confirm"
    case swordSlash = "sword-slash"
    case chestOpen = "chest-open"
    case itemGet = "item-get"
    case ambientRiver = "ambient-river"
}

public enum SoundEffectCategory: String, Codable, Sendable, Equatable {
    case ui
    case player
    case environment
}

public enum SoundEffectWaveform: String, Codable, Sendable, Equatable {
    case sine
    case square
    case sawtooth
    case triangle
}

public struct SoundEffectLayerManifest: Codable, Sendable, Equatable {
    public var samplePath: String?
    public var waveform: SoundEffectWaveform?
    public var frequencyHz: Double?
    public var delayFrames: Int
    public var durationFrames: Int
    public var gain: Float
    public var pan: Float

    public init(
        samplePath: String? = nil,
        waveform: SoundEffectWaveform? = nil,
        frequencyHz: Double? = nil,
        delayFrames: Int = 0,
        durationFrames: Int,
        gain: Float = 1,
        pan: Float = 0
    ) {
        self.samplePath = samplePath
        self.waveform = waveform
        self.frequencyHz = frequencyHz
        self.delayFrames = max(0, delayFrames)
        self.durationFrames = max(1, durationFrames)
        self.gain = gain
        self.pan = max(-1, min(1, pan))
    }
}

public struct SoundEffectManifest: Codable, Sendable, Equatable {
    public var id: String
    public var event: NamedSoundEffect
    public var title: String
    public var category: SoundEffectCategory
    public var assetDirectory: String
    public var sourceSfxEnumName: String
    public var sourceChannelName: String
    public var concurrencyLimit: Int
    public var playbackDurationFrames: Int
    public var layers: [SoundEffectLayerManifest]

    public init(
        id: String,
        event: NamedSoundEffect,
        title: String,
        category: SoundEffectCategory,
        assetDirectory: String,
        sourceSfxEnumName: String,
        sourceChannelName: String,
        concurrencyLimit: Int,
        playbackDurationFrames: Int,
        layers: [SoundEffectLayerManifest]
    ) {
        self.id = id
        self.event = event
        self.title = title
        self.category = category
        self.assetDirectory = assetDirectory
        self.sourceSfxEnumName = sourceSfxEnumName
        self.sourceChannelName = sourceChannelName
        self.concurrencyLimit = max(1, concurrencyLimit)
        self.playbackDurationFrames = max(1, playbackDurationFrames)
        self.layers = layers
    }
}

public struct SoundEffectCatalog: Codable, Sendable, Equatable {
    public var version: Int
    public var effects: [SoundEffectManifest]

    public init(
        version: Int = 1,
        effects: [SoundEffectManifest]
    ) {
        self.version = version
        self.effects = effects
    }
}

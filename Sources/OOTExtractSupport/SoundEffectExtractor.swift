import Foundation
import OOTDataModel

extension SoundEffectExtractor {
    public func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let audioRoot = context.output
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent("SFX", isDirectory: true)
        try fileManager.createDirectory(at: audioRoot, withIntermediateDirectories: true)

        try Self.validateUpstreamAudioRoots(in: context.source, fileManager: fileManager)

        var manifests: [SoundEffectManifest] = []

        for definition in Self.effectDefinitions {
            let assetDirectoryURL = audioRoot.appendingPathComponent(definition.id, isDirectory: true)
            try fileManager.createDirectory(at: assetDirectoryURL, withIntermediateDirectories: true)

            var layers: [SoundEffectLayerManifest] = []

            for layer in definition.layers {
                switch layer.source {
                case .sample(let sampleFileName):
                    let relativeSamplePath = "Audio/SFX/\(definition.id)/samples/SampleBank_0/\(sampleFileName)"
                    let sourceURL = Self.sampleSourceRoot(in: context.source)
                        .appendingPathComponent(sampleFileName)
                    let destinationURL = context.output.appendingPathComponent(relativeSamplePath)

                    guard fileManager.fileExists(atPath: sourceURL.path) else {
                        throw SoundEffectExtractorError.missingSampleSource(sourceURL.path)
                    }

                    try fileManager.createDirectory(
                        at: destinationURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)

                    layers.append(
                        SoundEffectLayerManifest(
                            samplePath: relativeSamplePath,
                            delayFrames: layer.delayFrames,
                            durationFrames: layer.durationFrames,
                            gain: layer.gain,
                            pan: layer.pan
                        )
                    )
                case .synth(let waveform, let frequencyHz):
                    layers.append(
                        SoundEffectLayerManifest(
                            waveform: waveform,
                            frequencyHz: frequencyHz,
                            delayFrames: layer.delayFrames,
                            durationFrames: layer.durationFrames,
                            gain: layer.gain,
                            pan: layer.pan
                        )
                    )
                }
            }

            manifests.append(
                SoundEffectManifest(
                    id: definition.id,
                    event: definition.event,
                    title: definition.title,
                    category: definition.category,
                    assetDirectory: "Audio/SFX/\(definition.id)",
                    sourceSfxEnumName: definition.sourceSfxEnumName,
                    sourceChannelName: definition.sourceChannelName,
                    concurrencyLimit: definition.concurrencyLimit,
                    playbackDurationFrames: definition.playbackDurationFrames,
                    layers: layers
                )
            )
        }

        try Self.writeJSON(
            SoundEffectCatalog(
                effects: manifests.sorted { $0.id < $1.id }
            ),
            to: context.output
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent(Self.catalogFilename),
            fileManager: fileManager
        )

        print("[\(name)] wrote \(manifests.count) sound effect bundle(s)")
    }

    public func verify(using context: OOTVerificationContext) throws {
        let fileManager = FileManager.default
        let catalogURL = context.content
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(Self.catalogFilename)
        let catalog: SoundEffectCatalog = try Self.readJSON(from: catalogURL)
        let events = Set(catalog.effects.map(\.event))

        guard events.count == catalog.effects.count else {
            throw SoundEffectExtractorError.duplicateNamedEvent
        }

        for effect in catalog.effects {
            try Self.verifyDirectory(path: effect.assetDirectory, contentRoot: context.content)
            guard effect.layers.isEmpty == false else {
                throw SoundEffectExtractorError.missingEffectLayers(effect.id)
            }

            for layer in effect.layers {
                if let samplePath = layer.samplePath {
                    try Self.verifyFile(path: samplePath, contentRoot: context.content)
                }
                if layer.samplePath == nil, layer.waveform == nil {
                    throw SoundEffectExtractorError.invalidLayer(effect.id)
                }
            }
        }

        let sfxRoot = context.content.appendingPathComponent("Audio/SFX", isDirectory: true)
        guard fileManager.fileExists(atPath: sfxRoot.path) else {
            throw SoundEffectExtractorError.missingManifest(sfxRoot.path)
        }

        print("[\(name)] verified \(catalog.effects.count) sound effect bundle(s)")
    }
}

private extension SoundEffectExtractor {
    static let catalogFilename = "sfx.json"

    enum SoundLayerSource {
        case sample(String)
        case synth(SoundEffectWaveform, Double)
    }

    struct LayerDefinition {
        let source: SoundLayerSource
        let delayFrames: Int
        let durationFrames: Int
        let gain: Float
        let pan: Float

        init(
            source: SoundLayerSource,
            delayFrames: Int = 0,
            durationFrames: Int,
            gain: Float = 1,
            pan: Float = 0
        ) {
            self.source = source
            self.delayFrames = delayFrames
            self.durationFrames = durationFrames
            self.gain = gain
            self.pan = pan
        }
    }

    struct EffectDefinition {
        let id: String
        let event: NamedSoundEffect
        let title: String
        let category: SoundEffectCategory
        let sourceSfxEnumName: String
        let sourceChannelName: String
        let concurrencyLimit: Int
        let playbackDurationFrames: Int
        let layers: [LayerDefinition]
    }

    static let effectDefinitions: [EffectDefinition] = [
        EffectDefinition(
            id: "ui-confirm",
            event: .uiConfirm,
            title: "UI Confirm",
            category: .ui,
            sourceSfxEnumName: "NA_SE_SY_DECIDE",
            sourceChannelName: "CHAN_58E9",
            concurrencyLimit: 2,
            playbackDurationFrames: 27,
            layers: [
                LayerDefinition(
                    source: .sample("Sample110.wav"),
                    durationFrames: 27
                ),
            ]
        ),
        EffectDefinition(
            id: "ui-cancel",
            event: .uiCancel,
            title: "UI Cancel",
            category: .ui,
            sourceSfxEnumName: "NA_SE_SY_CANCEL",
            sourceChannelName: "CHAN_5948",
            concurrencyLimit: 2,
            playbackDurationFrames: 48,
            layers: [
                LayerDefinition(source: .synth(.triangle, 440.0), durationFrames: 6, gain: 0.75),
                LayerDefinition(source: .synth(.triangle, 329.6276), delayFrames: 6, durationFrames: 6, gain: 0.75),
                LayerDefinition(source: .synth(.triangle, 293.6648), delayFrames: 12, durationFrames: 6, gain: 0.75),
                LayerDefinition(source: .synth(.triangle, 246.9417), delayFrames: 18, durationFrames: 6, gain: 0.75),
                LayerDefinition(source: .synth(.triangle, 220.0), delayFrames: 24, durationFrames: 9, gain: 0.75),
                LayerDefinition(source: .synth(.triangle, 246.9417), delayFrames: 33, durationFrames: 6, gain: 0.25),
                LayerDefinition(source: .synth(.triangle, 220.0), delayFrames: 39, durationFrames: 9, gain: 0.25),
            ]
        ),
        EffectDefinition(
            id: "talk-confirm",
            event: .talkConfirm,
            title: "Talk Confirm",
            category: .ui,
            sourceSfxEnumName: "NA_SE_SY_MESSAGE_WOMAN",
            sourceChannelName: "CHAN_5880",
            concurrencyLimit: 1,
            playbackDurationFrames: 6,
            layers: [
                LayerDefinition(source: .synth(.triangle, 440.0), durationFrames: 6, gain: 0.6),
            ]
        ),
        EffectDefinition(
            id: "sword-slash",
            event: .swordSlash,
            title: "Sword Slash",
            category: .player,
            sourceSfxEnumName: "NA_SE_IT_SWORD_SWING",
            sourceChannelName: "CHAN_0F8D",
            concurrencyLimit: 1,
            playbackDurationFrames: 42,
            layers: [
                LayerDefinition(
                    source: .sample("Sample047.wav"),
                    durationFrames: 42
                ),
            ]
        ),
        EffectDefinition(
            id: "chest-open",
            event: .chestOpen,
            title: "Chest Open",
            category: .environment,
            sourceSfxEnumName: "NA_SE_EV_TBOX_OPEN",
            sourceChannelName: "CHAN_1B7D",
            concurrencyLimit: 1,
            playbackDurationFrames: 96,
            layers: [
                LayerDefinition(
                    source: .sample("Sample088.wav"),
                    durationFrames: 96
                ),
            ]
        ),
        EffectDefinition(
            id: "item-get",
            event: .itemGet,
            title: "Item Get",
            category: .ui,
            sourceSfxEnumName: "NA_SE_SY_GET_ITEM",
            sourceChannelName: "CHAN_5B9C",
            concurrencyLimit: 1,
            playbackDurationFrames: 80,
            layers: [
                LayerDefinition(source: .synth(.triangle, 415.3047), durationFrames: 10, gain: 0.75),
                LayerDefinition(source: .synth(.triangle, 349.2282), delayFrames: 10, durationFrames: 10, gain: 0.75),
                LayerDefinition(source: .synth(.triangle, 311.1270), delayFrames: 20, durationFrames: 10, gain: 0.75),
                LayerDefinition(source: .synth(.triangle, 415.3047), delayFrames: 30, durationFrames: 10, gain: 0.75),
                LayerDefinition(source: .synth(.triangle, 415.3047), delayFrames: 40, durationFrames: 20, gain: 0.55),
                LayerDefinition(source: .synth(.triangle, 415.3047), delayFrames: 60, durationFrames: 20, gain: 0.35),
            ]
        ),
        EffectDefinition(
            id: "ambient-river",
            event: .ambientRiver,
            title: "Ambient River",
            category: .environment,
            sourceSfxEnumName: "NA_SE_EV_RIVER_STREAM",
            sourceChannelName: "CHAN_1915",
            concurrencyLimit: 1,
            playbackDurationFrames: 180,
            layers: [
                LayerDefinition(
                    source: .sample("Sample075.wav"),
                    durationFrames: 180
                ),
            ]
        ),
    ]

    static func validateUpstreamAudioRoots(
        in sourceRoot: URL,
        fileManager: FileManager
    ) throws {
        let requiredPaths = [
            sourceRoot.appendingPathComponent("assets/audio/sequences/seq_0.prg.seq"),
            sourceRoot.appendingPathComponent("extracted/ntsc-1.2/assets/audio/soundfonts/Soundfont_0.xml"),
            sourceRoot.appendingPathComponent("extracted/ntsc-1.2/assets/audio/samplebanks/SampleBank_0.xml"),
            sampleSourceRoot(in: sourceRoot),
        ]

        for requiredPath in requiredPaths where !fileManager.fileExists(atPath: requiredPath.path) {
            throw SoundEffectExtractorError.missingSourceAudio(requiredPath.path)
        }
    }

    static func sampleSourceRoot(in sourceRoot: URL) -> URL {
        sourceRoot
            .appendingPathComponent("extracted", isDirectory: true)
            .appendingPathComponent("ntsc-1.2", isDirectory: true)
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("samples", isDirectory: true)
            .appendingPathComponent("SampleBank_0", isDirectory: true)
    }

    static func writeJSON<T: Encodable>(
        _ value: T,
        to url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url)
    }

    static func readJSON<T: Decodable>(from url: URL) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SoundEffectExtractorError.missingManifest(url.path)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SoundEffectExtractorError.invalidManifest(url.path, error.localizedDescription)
        }
    }

    static func verifyDirectory(path: String, contentRoot: URL) throws {
        let url = try resolveURL(for: path, contentRoot: contentRoot)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SoundEffectExtractorError.missingReferencedAsset(url.path)
        }
    }

    static func verifyFile(path: String, contentRoot: URL) throws {
        let url = try resolveURL(for: path, contentRoot: contentRoot)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SoundEffectExtractorError.missingReferencedAsset(url.path)
        }
    }

    static func resolveURL(for relativePath: String, contentRoot: URL) throws -> URL {
        let url = contentRoot.appendingPathComponent(relativePath).standardizedFileURL
        let contentRootPath = contentRoot.standardizedFileURL.path

        guard url.path == contentRootPath || url.path.hasPrefix(contentRootPath + "/") else {
            throw SoundEffectExtractorError.invalidReferencedPath(relativePath)
        }

        return url
    }
}

private enum SoundEffectExtractorError: LocalizedError {
    case missingSourceAudio(String)
    case missingSampleSource(String)
    case missingManifest(String)
    case invalidManifest(String, String)
    case invalidReferencedPath(String)
    case missingReferencedAsset(String)
    case duplicateNamedEvent
    case missingEffectLayers(String)
    case invalidLayer(String)

    var errorDescription: String? {
        switch self {
        case .missingSourceAudio(let path):
            "Missing required upstream audio source at \(path)."
        case .missingSampleSource(let path):
            "Missing required upstream sample asset at \(path)."
        case .missingManifest(let path):
            "Missing sound effect manifest at \(path)."
        case .invalidManifest(let path, let message):
            "Invalid sound effect manifest at \(path): \(message)"
        case .invalidReferencedPath(let path):
            "Sound effect content path escapes the configured content root: \(path)."
        case .missingReferencedAsset(let path):
            "Missing referenced sound effect asset at \(path)."
        case .duplicateNamedEvent:
            "Sound effect manifest contains duplicate named events."
        case .missingEffectLayers(let effectID):
            "Sound effect \(effectID) did not include any playable layers."
        case .invalidLayer(let effectID):
            "Sound effect \(effectID) included a layer with neither a sample nor a waveform."
        }
    }
}

import Foundation
import OOTDataModel

extension AudioExtractor {
    public func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let extractedAudioRoot = try Self.resolveExtractedAudioRoot(
            sourceRoot: context.source,
            fileManager: fileManager
        )
        let sceneTableEntries = try Self.loadSceneTableEntries(from: context.output)
        let sceneIDsByName = Self.sceneIDsByName(sceneTableEntries)

        let audioRoot = context.output
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent("BGM", isDirectory: true)
        try fileManager.createDirectory(at: audioRoot, withIntermediateDirectories: true)

        var tracks: [AudioTrackManifest] = []
        var sceneBindings: [AudioSceneBinding] = []

        for definition in Self.trackDefinitions {
            let bundle = try Self.copyBundle(
                for: definition,
                extractedAudioRoot: extractedAudioRoot,
                sourceRoot: context.source,
                outputRoot: context.output,
                bundleRoot: audioRoot,
                fileManager: fileManager
            )
            tracks.append(bundle)

            for sceneName in definition.sceneNames {
                sceneBindings.append(
                    AudioSceneBinding(
                        sceneName: sceneName,
                        sceneID: sceneIDsByName[sceneName],
                        sequenceID: definition.sequenceID,
                        sequenceEnumName: definition.sequenceEnumName,
                        trackID: definition.id
                    )
                )
            }
        }

        let catalog = AudioTrackCatalog(
            tracks: tracks.sorted { $0.id < $1.id },
            sceneBindings: sceneBindings.sorted {
                if $0.sceneName == $1.sceneName {
                    return $0.trackID < $1.trackID
                }
                return $0.sceneName < $1.sceneName
            }
        )

        try Self.writeJSON(
            catalog,
            to: context.output
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("audio", isDirectory: true)
                .appendingPathComponent(Self.catalogFilename),
            fileManager: fileManager
        )

        print("[\(name)] wrote \(tracks.count) audio track bundle(s)")
    }

    public func verify(using context: OOTVerificationContext) throws {
        let catalogURL = context.content
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(Self.catalogFilename)
        let catalog: AudioTrackCatalog = try Self.readJSON(from: catalogURL)
        let trackIDs = Set(catalog.tracks.map(\.id))

        guard trackIDs.count == catalog.tracks.count else {
            throw AudioExtractorError.duplicateTrackID
        }

        for track in catalog.tracks {
            try Self.verifyDirectory(path: track.assetDirectory, contentRoot: context.content)
            try Self.verifyFile(path: track.sequencePath, contentRoot: context.content)
            try Self.verifyFile(path: track.sequenceMetadataPath, contentRoot: context.content)
            guard track.samplePaths.isEmpty == false else {
                throw AudioExtractorError.missingTrackSamples(track.id)
            }

            for soundfontPath in track.soundfontPaths {
                try Self.verifyFile(path: soundfontPath, contentRoot: context.content)
            }
            for sampleBankPath in track.sampleBankPaths {
                try Self.verifyFile(path: sampleBankPath, contentRoot: context.content)
            }
            for samplePath in track.samplePaths {
                try Self.verifyFile(path: samplePath, contentRoot: context.content)
            }
        }

        for binding in catalog.sceneBindings {
            guard let track = catalog.tracks.first(where: { $0.id == binding.trackID }) else {
                throw AudioExtractorError.missingTrackReference(binding.trackID)
            }
            guard track.sequenceID == binding.sequenceID else {
                throw AudioExtractorError.mismatchedSequenceBinding(
                    sceneName: binding.sceneName,
                    trackID: binding.trackID
                )
            }
        }

        print("[\(name)] verified \(catalog.tracks.count) audio track bundle(s)")
    }
}

private extension AudioExtractor {
    static let catalogFilename = "bgm-tracks.json"

    struct TrackDefinition {
        let id: String
        let title: String
        let kind: AudioTrackKind
        let sequenceID: Int
        let sequenceEnumName: String
        let sceneNames: [String]
    }

    struct SoundfontDependency {
        let fileName: String
        let sampleBankFileName: String
        let sampleNames: [String]
    }

    struct SampleDefinition {
        let name: String
        let fileName: String
    }

    static let trackDefinitions: [TrackDefinition] = [
        TrackDefinition(
            id: "kokiri-forest",
            title: "Kokiri Forest",
            kind: .bgm,
            sequenceID: 60,
            sequenceEnumName: "NA_BGM_KOKIRI",
            sceneNames: ["spot04"]
        ),
        TrackDefinition(
            id: "inside-deku-tree",
            title: "Inside the Deku Tree",
            kind: .bgm,
            sequenceID: 28,
            sequenceEnumName: "NA_BGM_INSIDE_DEKU_TREE",
            sceneNames: ["ydan"]
        ),
        TrackDefinition(
            id: "title-theme",
            title: "Title Theme",
            kind: .bgm,
            sequenceID: 30,
            sequenceEnumName: "NA_BGM_TITLE",
            sceneNames: []
        ),
        TrackDefinition(
            id: "item-get",
            title: "Item Get",
            kind: .fanfare,
            sequenceID: 34,
            sequenceEnumName: "NA_BGM_ITEM_GET",
            sceneNames: []
        ),
        TrackDefinition(
            id: "heart-get",
            title: "Heart Get",
            kind: .fanfare,
            sequenceID: 36,
            sequenceEnumName: "NA_BGM_HEART_GET",
            sceneNames: []
        ),
        TrackDefinition(
            id: "open-treasure-chest",
            title: "Open Treasure Chest",
            kind: .fanfare,
            sequenceID: 43,
            sequenceEnumName: "NA_BGM_OPEN_TRE_BOX",
            sceneNames: []
        ),
    ]

    static func resolveExtractedAudioRoot(
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> URL {
        let preferred = sourceRoot
            .appendingPathComponent("extracted", isDirectory: true)
            .appendingPathComponent("ntsc-1.2", isDirectory: true)
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
        if fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }

        let extractedRoot = sourceRoot.appendingPathComponent("extracted", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: extractedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AudioExtractorError.missingExtractedAudio(preferred.path)
        }

        for case let candidate as URL in enumerator {
            guard candidate.lastPathComponent == "audio" else {
                continue
            }
            let sequencesDirectory = candidate.appendingPathComponent("sequences", isDirectory: true)
            guard fileManager.fileExists(atPath: sequencesDirectory.path) else {
                continue
            }
            return candidate
        }

        throw AudioExtractorError.missingExtractedAudio(preferred.path)
    }

    static func loadSceneTableEntries(from outputRoot: URL) throws -> [SceneTableEntry] {
        let tableURL = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("tables", isDirectory: true)
            .appendingPathComponent("scene-table.json")
        return try readJSON(from: tableURL)
    }

    static func sceneIDsByName(_ entries: [SceneTableEntry]) -> [String: Int] {
        Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                guard entry.segmentName.hasSuffix("_scene") else {
                    return nil
                }
                let sceneName = String(entry.segmentName.dropLast("_scene".count))
                return (sceneName, entry.index)
            }
        )
    }

    static func copyBundle(
        for definition: TrackDefinition,
        extractedAudioRoot: URL,
        sourceRoot: URL,
        outputRoot: URL,
        bundleRoot: URL,
        fileManager: FileManager
    ) throws -> AudioTrackManifest {
        let trackDirectory = bundleRoot.appendingPathComponent(definition.id, isDirectory: true)
        try fileManager.createDirectory(at: trackDirectory, withIntermediateDirectories: true)

        let sequenceSourceURL = extractedAudioRoot
            .appendingPathComponent("sequences", isDirectory: true)
            .appendingPathComponent("seq_\(definition.sequenceID).seq")
        let sequenceMetadataURL = sourceRoot
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("xml", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("sequences", isDirectory: true)
            .appendingPathComponent("seq_\(definition.sequenceID).xml")

        guard fileManager.fileExists(atPath: sequenceSourceURL.path) else {
            throw AudioExtractorError.missingSequenceSource(sequenceSourceURL.path)
        }
        guard fileManager.fileExists(atPath: sequenceMetadataURL.path) else {
            throw AudioExtractorError.missingSequenceMetadata(sequenceMetadataURL.path)
        }

        let soundfontFileNames = try referencedSoundfontFileNames(fromSequenceAt: sequenceSourceURL)
        let dependencies = try soundfontFileNames.map {
            try soundfontDependency(
                named: $0,
                extractedAudioRoot: extractedAudioRoot
            )
        }

        let sampleBankURLs = uniquePreservingOrder(
            dependencies.map {
                extractedAudioRoot
                    .appendingPathComponent("samplebanks", isDirectory: true)
                    .appendingPathComponent($0.sampleBankFileName)
            }
        )
        let sampleURLs = uniquePreservingOrder(
            try dependencies.flatMap { dependency -> [URL] in
                let sampleBankURL = extractedAudioRoot
                    .appendingPathComponent("samplebanks", isDirectory: true)
                    .appendingPathComponent(dependency.sampleBankFileName)
                let samplesByName = try sampleDefinitionsByName(from: sampleBankURL)
                let bankName = sampleBankURL.deletingPathExtension().lastPathComponent

                return dependency.sampleNames.compactMap { sampleName -> URL? in
                    guard let sample = samplesByName[sampleName] else {
                        return nil
                    }
                    return extractedAudioRoot
                        .appendingPathComponent("samples", isDirectory: true)
                        .appendingPathComponent(bankName, isDirectory: true)
                        .appendingPathComponent("\(sample.fileName).wav")
                }
            }
        )

        let copiedSequenceURL = try copyFile(
            from: sequenceSourceURL,
            to: trackDirectory.appendingPathComponent("sequence.seq"),
            fileManager: fileManager
        )
        let copiedMetadataURL = try copyFile(
            from: sequenceMetadataURL,
            to: trackDirectory.appendingPathComponent("sequence.xml"),
            fileManager: fileManager
        )

        let copiedSoundfontURLs = try soundfontFileNames.map { soundfontFileName in
            let sourceURL = extractedAudioRoot
                .appendingPathComponent("soundfonts", isDirectory: true)
                .appendingPathComponent(soundfontFileName)
            let destinationURL = trackDirectory
                .appendingPathComponent("soundfonts", isDirectory: true)
                .appendingPathComponent(soundfontFileName)
            return try copyFile(from: sourceURL, to: destinationURL, fileManager: fileManager)
        }

        let copiedSampleBankURLs = try sampleBankURLs.map { sampleBankURL in
            let destinationURL = trackDirectory
                .appendingPathComponent("samplebanks", isDirectory: true)
                .appendingPathComponent(sampleBankURL.lastPathComponent)
            return try copyFile(from: sampleBankURL, to: destinationURL, fileManager: fileManager)
        }

        let copiedSampleURLs = try sampleURLs.map { sampleURL in
            let bankName = sampleURL.deletingLastPathComponent().lastPathComponent
            let destinationURL = trackDirectory
                .appendingPathComponent("samples", isDirectory: true)
                .appendingPathComponent(bankName, isDirectory: true)
                .appendingPathComponent(sampleURL.lastPathComponent)
            return try copyFile(from: sampleURL, to: destinationURL, fileManager: fileManager)
        }

        return AudioTrackManifest(
            id: definition.id,
            title: definition.title,
            kind: definition.kind,
            sequenceID: definition.sequenceID,
            sequenceEnumName: definition.sequenceEnumName,
            assetDirectory: try relativePath(from: outputRoot, to: trackDirectory),
            sequencePath: try relativePath(from: outputRoot, to: copiedSequenceURL),
            sequenceMetadataPath: try relativePath(from: outputRoot, to: copiedMetadataURL),
            soundfontPaths: try copiedSoundfontURLs.map { try relativePath(from: outputRoot, to: $0) }.sorted(),
            sampleBankPaths: try copiedSampleBankURLs.map { try relativePath(from: outputRoot, to: $0) }.sorted(),
            samplePaths: try copiedSampleURLs.map { try relativePath(from: outputRoot, to: $0) }.sorted()
        )
    }

    static func referencedSoundfontFileNames(fromSequenceAt url: URL) throws -> [String] {
        let source = try String(contentsOf: url, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"#include\s+"(Soundfont_[^"]+\.h)""#)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source))
        let fileNames = matches.compactMap { match -> String? in
            guard
                let range = Range(match.range(at: 1), in: source)
            else {
                return nil
            }
            return String(source[range]).replacingOccurrences(of: ".h", with: ".xml")
        }
        guard fileNames.isEmpty == false else {
            throw AudioExtractorError.missingSoundfontInclude(url.path)
        }
        return uniquePreservingOrder(fileNames)
    }

    static func soundfontDependency(
        named soundfontFileName: String,
        extractedAudioRoot: URL
    ) throws -> SoundfontDependency {
        let soundfontURL = extractedAudioRoot
            .appendingPathComponent("soundfonts", isDirectory: true)
            .appendingPathComponent(soundfontFileName)
        let source = try String(contentsOf: soundfontURL, encoding: .utf8)
        let sampleBankRegex = try NSRegularExpression(pattern: #"SampleBank(?:DD)?="([^"]+)""#)
        let sampleNameRegex = try NSRegularExpression(pattern: #"<Sample\s+Name="([^"]+)""#)

        guard
            let sampleBankMatch = sampleBankRegex.firstMatch(
                in: source,
                range: NSRange(source.startIndex..<source.endIndex, in: source)
            ),
            let sampleBankRange = Range(sampleBankMatch.range(at: 1), in: source)
        else {
            throw AudioExtractorError.missingSampleBankReference(soundfontURL.path)
        }

        let sampleBankFileName = URL(fileURLWithPath: String(source[sampleBankRange])).lastPathComponent
        let sampleNames = sampleNameRegex.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
        .compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return String(source[range])
        }

        return SoundfontDependency(
            fileName: soundfontFileName,
            sampleBankFileName: sampleBankFileName,
            sampleNames: uniquePreservingOrder(sampleNames)
        )
    }

    static func sampleDefinitionsByName(from sampleBankURL: URL) throws -> [String: SampleDefinition] {
        let source = try String(contentsOf: sampleBankURL, encoding: .utf8)
        let fileNameRegex = try NSRegularExpression(pattern: #"<Sample\s+Name="([^"]+)"\s+FileName="([^"]+)""#)
        let pathRegex = try NSRegularExpression(pattern: #"<Sample\s+Name="([^"]+)"\s+Path="([^"]+)""#)

        let fileNameDefinitions = fileNameRegex.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
        .compactMap { match -> (String, SampleDefinition)? in
            guard
                let nameRange = Range(match.range(at: 1), in: source),
                let fileRange = Range(match.range(at: 2), in: source)
            else {
                return nil
            }

            let definition = SampleDefinition(
                name: String(source[nameRange]),
                fileName: String(source[fileRange])
            )
            return (definition.name, definition)
        }

        let pathDefinitions = pathRegex.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        )
        .compactMap { match -> (String, SampleDefinition)? in
            guard
                let nameRange = Range(match.range(at: 1), in: source),
                let pathRange = Range(match.range(at: 2), in: source)
            else {
                return nil
            }

            let fileName = URL(fileURLWithPath: String(source[pathRange]))
                .deletingPathExtension()
                .lastPathComponent
            let definition = SampleDefinition(
                name: String(source[nameRange]),
                fileName: fileName
            )
            return (definition.name, definition)
        }

        return Dictionary(
            uniqueKeysWithValues: fileNameDefinitions + pathDefinitions
        )
    }

    static func copyFile(from sourceURL: URL, to destinationURL: URL, fileManager: FileManager) throws -> URL {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AudioExtractorError.missingReferencedAsset(sourceURL.path)
        }

        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func uniquePreservingOrder<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        var result: [T] = []
        result.reserveCapacity(values.count)

        for value in values where seen.insert(value).inserted {
            result.append(value)
        }

        return result
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL, fileManager: FileManager) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func readJSON<T: Decodable>(from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioExtractorError.missingManifest(url.path)
        }

        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            throw AudioExtractorError.invalidManifest(url.path, error.localizedDescription)
        }
    }

    static func relativePath(from root: URL, to target: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"

        guard targetPath.hasPrefix(prefix) else {
            throw AudioExtractorError.invalidReferencedPath(targetPath)
        }

        return String(targetPath.dropFirst(prefix.count))
    }

    static func referencedURL(path: String, contentRoot: URL) throws -> URL {
        let url = contentRoot.appendingPathComponent(path, isDirectory: false)
        _ = try relativePath(from: contentRoot, to: url)
        return url
    }

    static func verifyFile(path: String, contentRoot: URL) throws {
        let url = try referencedURL(path: path, contentRoot: contentRoot)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioExtractorError.missingReferencedAsset(url.path)
        }
    }

    static func verifyDirectory(path: String, contentRoot: URL) throws {
        let url = try referencedURL(path: path, contentRoot: contentRoot)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AudioExtractorError.missingReferencedAsset(url.path)
        }
    }
}

private enum AudioExtractorError: LocalizedError {
    case missingExtractedAudio(String)
    case missingSequenceSource(String)
    case missingSequenceMetadata(String)
    case missingSoundfontInclude(String)
    case missingSampleBankReference(String)
    case missingReferencedAsset(String)
    case missingManifest(String)
    case invalidManifest(String, String)
    case invalidReferencedPath(String)
    case duplicateTrackID
    case missingTrackSamples(String)
    case missingTrackReference(String)
    case mismatchedSequenceBinding(sceneName: String, trackID: String)

    var errorDescription: String? {
        switch self {
        case .missingExtractedAudio(let path):
            "Missing extracted audio root at \(path)."
        case .missingSequenceSource(let path):
            "Missing extracted sequence source at \(path)."
        case .missingSequenceMetadata(let path):
            "Missing sequence metadata XML at \(path)."
        case .missingSoundfontInclude(let path):
            "No soundfont include directives were found in sequence source \(path)."
        case .missingSampleBankReference(let path):
            "Unable to resolve a sample bank reference from soundfont \(path)."
        case .missingReferencedAsset(let path):
            "Missing referenced audio asset at \(path)."
        case .missingManifest(let path):
            "Missing audio manifest at \(path)."
        case .invalidManifest(let path, let message):
            "Invalid audio manifest at \(path): \(message)"
        case .invalidReferencedPath(let path):
            "Audio content path escapes the configured content root: \(path)."
        case .duplicateTrackID:
            "Audio manifest contains duplicate track ids."
        case .missingTrackSamples(let trackID):
            "Audio track \(trackID) did not include any extracted sample paths."
        case .missingTrackReference(let trackID):
            "Audio scene binding references unknown track id \(trackID)."
        case .mismatchedSequenceBinding(let sceneName, let trackID):
            "Audio scene binding for \(sceneName) does not match track \(trackID)."
        }
    }
}

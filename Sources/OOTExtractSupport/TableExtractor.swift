import Foundation
import OOTDataModel

struct TableManifestCounts: Sendable, Equatable {
    let scenes: Int
    let actors: Int
    let objects: Int
    let entrances: Int

    static let pinnedOOT = TableManifestCounts(scenes: 101, actors: 471, objects: 402, entrances: 1557)
}

public struct TableExtractor: OOTExtractionPipelineComponent {
    public let name = "TableExtractor"

    private let parser: CHeaderParser
    private let expectedCounts: TableManifestCounts

    init(
        parser: CHeaderParser = CHeaderParser(),
        expectedCounts: TableManifestCounts = .pinnedOOT
    ) {
        self.parser = parser
        self.expectedCounts = expectedCounts
    }

    public func extract(using context: OOTExtractionContext) throws {
        let sceneEntries = try loadSceneEntries(from: context.source)
        let actorEntries = try loadActorEntries(from: context.source)
        let objectEntries = try loadObjectEntries(from: context.source)
        let entranceEntries = try loadEntranceEntries(from: context.source, sceneEntries: sceneEntries)

        try validateCounts(
            scenes: sceneEntries.count,
            actors: actorEntries.count,
            objects: objectEntries.count,
            entrances: entranceEntries.count
        )

        let tablesDirectory = manifestsDirectory(in: context.output)
        try FileManager.default.createDirectory(at: tablesDirectory, withIntermediateDirectories: true)

        try writeJSON(sceneEntries, to: tablesDirectory.appendingPathComponent("scene-table.json"))
        try writeJSON(actorEntries, to: tablesDirectory.appendingPathComponent("actor-table.json"))
        try writeJSON(objectEntries, to: tablesDirectory.appendingPathComponent("object-table.json"))
        try writeJSON(entranceEntries, to: tablesDirectory.appendingPathComponent("entrance-table.json"))

        print(
            "[\(name)] wrote \(sceneEntries.count) scenes, \(actorEntries.count) actors, " +
                "\(objectEntries.count) objects, \(entranceEntries.count) entrances"
        )
    }

    public func verify(using context: OOTVerificationContext) throws {
        let tablesDirectory = manifestsDirectory(in: context.content)

        let sceneEntries: [SceneTableEntry] = try readJSON(
            from: tablesDirectory.appendingPathComponent("scene-table.json")
        )
        let actorEntries: [ActorTableEntry] = try readJSON(
            from: tablesDirectory.appendingPathComponent("actor-table.json")
        )
        let objectEntries: [ObjectTableEntry] = try readJSON(
            from: tablesDirectory.appendingPathComponent("object-table.json")
        )
        let entranceEntries: [EntranceTableEntry] = try readJSON(
            from: tablesDirectory.appendingPathComponent("entrance-table.json")
        )

        try validateCounts(
            scenes: sceneEntries.count,
            actors: actorEntries.count,
            objects: objectEntries.count,
            entrances: entranceEntries.count
        )

        print(
            "[\(name)] verified \(sceneEntries.count) scenes, \(actorEntries.count) actors, " +
                "\(objectEntries.count) objects, \(entranceEntries.count) entrances"
        )
    }

    private func loadSceneEntries(from sourceRoot: URL) throws -> [SceneTableEntry] {
        let sceneTableURL = sourceRoot
            .appendingPathComponent("include")
            .appendingPathComponent("tables")
            .appendingPathComponent("scene_table.h")
        let sceneHeaderURL = sourceRoot
            .appendingPathComponent("include")
            .appendingPathComponent("scene.h")

        let drawConfigs = try loadSceneDrawConfigMap(from: sceneHeaderURL)
        let macros = try parser.parseMacros(at: sceneTableURL, matching: ["DEFINE_SCENE"])

        return try macros.enumerated().map { offset, macro in
            try expectArgumentCount(for: macro, expected: 6, path: sceneTableURL.path)

            let drawConfigName = macro.arguments[3]
            guard let drawConfig = drawConfigs[drawConfigName] else {
                throw TableExtractorError.unresolvedSceneDrawConfig(drawConfigName)
            }

            return SceneTableEntry(
                index: macro.tableIndex ?? offset,
                segmentName: macro.arguments[0],
                enumName: macro.arguments[2],
                title: sanitizeOptionalIdentifier(macro.arguments[1]),
                drawConfig: drawConfig
            )
        }
    }

    private func loadActorEntries(from sourceRoot: URL) throws -> [ActorTableEntry] {
        let actorTableURL = sourceRoot
            .appendingPathComponent("include")
            .appendingPathComponent("tables")
            .appendingPathComponent("actor_table.h")
        let macros = try parser.parseMacros(
            at: actorTableURL,
            matching: ["DEFINE_ACTOR", "DEFINE_ACTOR_INTERNAL", "DEFINE_ACTOR_UNSET"]
        )

        return try macros.enumerated().map { offset, macro in
            let id = macro.tableIndex ?? offset
            switch macro.name {
            case "DEFINE_ACTOR", "DEFINE_ACTOR_INTERNAL":
                try expectArgumentCount(for: macro, expected: 4, path: actorTableURL.path)
                return ActorTableEntry(
                    id: id,
                    enumName: macro.arguments[1],
                    profile: placeholderProfile(for: id),
                    overlayName: macro.arguments[0]
                )
            case "DEFINE_ACTOR_UNSET":
                try expectArgumentCount(for: macro, expected: 1, path: actorTableURL.path)
                return ActorTableEntry(
                    id: id,
                    enumName: macro.arguments[0],
                    profile: placeholderProfile(for: id),
                    overlayName: nil
                )
            default:
                throw TableExtractorError.unsupportedMacro(macro.name)
            }
        }
    }

    private func loadObjectEntries(from sourceRoot: URL) throws -> [ObjectTableEntry] {
        let objectTableURL = sourceRoot
            .appendingPathComponent("include")
            .appendingPathComponent("tables")
            .appendingPathComponent("object_table.h")
        let macros = try parser.parseMacros(
            at: objectTableURL,
            matching: ["DEFINE_OBJECT", "DEFINE_OBJECT_EMPTY", "DEFINE_OBJECT_UNSET"]
        )

        return try macros.enumerated().map { offset, macro in
            let id = macro.tableIndex ?? offset
            switch macro.name {
            case "DEFINE_OBJECT", "DEFINE_OBJECT_EMPTY":
                try expectArgumentCount(for: macro, expected: 2, path: objectTableURL.path)
                return ObjectTableEntry(
                    id: id,
                    enumName: macro.arguments[1],
                    assetPath: "objects/\(macro.arguments[0])"
                )
            case "DEFINE_OBJECT_UNSET":
                try expectArgumentCount(for: macro, expected: 1, path: objectTableURL.path)
                return ObjectTableEntry(
                    id: id,
                    enumName: macro.arguments[0],
                    assetPath: ""
                )
            default:
                throw TableExtractorError.unsupportedMacro(macro.name)
            }
        }
    }

    private func loadEntranceEntries(
        from sourceRoot: URL,
        sceneEntries: [SceneTableEntry]
    ) throws -> [EntranceTableEntry] {
        let entranceTableURL = sourceRoot
            .appendingPathComponent("include")
            .appendingPathComponent("tables")
            .appendingPathComponent("entrance_table.h")
        let macros = try parser.parseMacros(at: entranceTableURL, matching: ["DEFINE_ENTRANCE"])
        let sceneIDByEnumName = Dictionary(uniqueKeysWithValues: sceneEntries.map { ($0.enumName, $0.index) })

        return try macros.enumerated().map { offset, macro in
            try expectArgumentCount(for: macro, expected: 7, path: entranceTableURL.path)

            let sceneEnumName = macro.arguments[1]
            guard let sceneID = sceneIDByEnumName[sceneEnumName] else {
                throw TableExtractorError.unresolvedSceneEnum(sceneEnumName)
            }

            return EntranceTableEntry(
                index: macro.tableIndex ?? offset,
                name: macro.arguments[0],
                sceneID: sceneID,
                spawnIndex: try parseIntegerLiteral(macro.arguments[2]),
                continueBGM: try parseBooleanLiteral(macro.arguments[3]),
                displayTitleCard: try parseBooleanLiteral(macro.arguments[4]),
                transitionIn: normalizeTransitionEffect(macro.arguments[5]),
                transitionOut: normalizeTransitionEffect(macro.arguments[6])
            )
        }
    }

    private func loadSceneDrawConfigMap(from url: URL) throws -> [String: Int] {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw TableExtractorError.unreadableFile(url.path, error)
        }

        var configs: [String: Int] = [:]
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

        for match in sceneDrawConfigRegex.matches(in: text, options: [], range: nsRange) {
            let rawIndex = substring(in: text, range: match.range(at: 1))
            let name = substring(in: text, range: match.range(at: 2))

            guard let index = Int(rawIndex) else {
                continue
            }

            configs[name] = index
        }

        return configs
    }

    private func manifestsDirectory(in root: URL) -> URL {
        root
            .appendingPathComponent("Manifests")
            .appendingPathComponent("tables")
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    private func readJSON<T: Decodable>(from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TableExtractorError.missingManifest(url.lastPathComponent)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TableExtractorError.unreadableFile(url.path, error)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TableExtractorError.invalidManifest(url.lastPathComponent, error)
        }
    }

    private func validateCounts(scenes: Int, actors: Int, objects: Int, entrances: Int) throws {
        try validateCount(kind: "scene", actual: scenes, expected: expectedCounts.scenes)
        try validateCount(kind: "actor", actual: actors, expected: expectedCounts.actors)
        try validateCount(kind: "object", actual: objects, expected: expectedCounts.objects)
        try validateCount(kind: "entrance", actual: entrances, expected: expectedCounts.entrances)
    }

    private func validateCount(kind: String, actual: Int, expected: Int) throws {
        guard actual == expected else {
            throw TableExtractorError.countMismatch(kind: kind, expected: expected, actual: actual)
        }
    }

    private func expectArgumentCount(for macro: CMacroInvocation, expected: Int, path: String) throws {
        guard macro.arguments.count == expected else {
            throw TableExtractorError.invalidArgumentCount(
                macro: macro.name,
                expected: expected,
                actual: macro.arguments.count,
                lineNumber: macro.lineNumber,
                path: path
            )
        }
    }

    private func sanitizeOptionalIdentifier(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "none" ? nil : trimmed
    }

    private func placeholderProfile(for id: Int) -> ActorProfile {
        // Actor profile metadata is extracted from actor source later; table manifests
        // only have enough data to preserve stable ids and names at this stage.
        ActorProfile(id: id, category: 0, flags: 0, objectID: 0)
    }

    private func parseIntegerLiteral(_ rawValue: String) throws -> Int {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            guard let value = Int(trimmed.dropFirst(2), radix: 16) else {
                throw TableExtractorError.invalidLiteral(trimmed)
            }
            return value
        }

        guard let value = Int(trimmed) else {
            throw TableExtractorError.invalidLiteral(trimmed)
        }
        return value
    }

    private func parseBooleanLiteral(_ rawValue: String) throws -> Bool {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true", "TRUE", "1":
            true
        case "false", "FALSE", "0":
            false
        default:
            throw TableExtractorError.invalidLiteral(rawValue)
        }
    }

    private func normalizeTransitionEffect(_ rawValue: String) -> SceneTransitionEffect {
        let normalized = rawValue.uppercased()
        if normalized.contains("WIPE") {
            return .wipe
        }
        if normalized.contains("CIRCLE") || normalized.contains("IRIS") {
            return .circleIris
        }
        return .fade
    }

    private func substring(in text: String, range: NSRange) -> String {
        guard
            range.location != NSNotFound,
            let swiftRange = Range(range, in: text)
        else {
            return ""
        }
        return String(text[swiftRange])
    }
}

enum TableExtractorError: LocalizedError {
    case unreadableFile(String, Error)
    case invalidArgumentCount(macro: String, expected: Int, actual: Int, lineNumber: Int, path: String)
    case invalidLiteral(String)
    case unresolvedSceneEnum(String)
    case unresolvedSceneDrawConfig(String)
    case unsupportedMacro(String)
    case countMismatch(kind: String, expected: Int, actual: Int)
    case missingManifest(String)
    case invalidManifest(String, Error)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let path, let error):
            return "Failed to read \(path): \(error.localizedDescription)"
        case .invalidArgumentCount(let macro, let expected, let actual, let lineNumber, let path):
            return "Expected \(expected) arguments for \(macro) at \(path):\(lineNumber), got \(actual)"
        case .invalidLiteral(let literal):
            return "Unable to parse literal \(literal)"
        case .unresolvedSceneEnum(let name):
            return "Unable to resolve scene enum symbol \(name)"
        case .unresolvedSceneDrawConfig(let name):
            return "Unable to resolve scene draw config symbol \(name)"
        case .unsupportedMacro(let name):
            return "Unsupported table macro \(name)"
        case .countMismatch(let kind, let expected, let actual):
            return "Expected \(expected) \(kind) entries, got \(actual)"
        case .missingManifest(let name):
            return "Missing required table manifest \(name)"
        case .invalidManifest(let name, let error):
            return "Failed to decode \(name): \(error.localizedDescription)"
        }
    }
}

private let sceneDrawConfigRegex = try! NSRegularExpression(
    pattern: #"^\s*/\*\s*(\d+)\s*\*/\s*(SDC_[A-Z0-9_]+),"#,
    options: [.anchorsMatchLines]
)

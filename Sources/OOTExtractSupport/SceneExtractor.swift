import Foundation
import OOTDataModel

extension SceneExtractor {
    public func extract(using context: OOTExtractionContext) throws {
        let actorIDByName = try Self.loadActorIDs(from: context.output)
        let entranceIndexByName = try Self.loadEntranceIndices(from: context.source)
        let groups = try Self.sceneAssetGroups(in: context.source, fileManager: .default)
        var emittedScenes = 0

        for group in groups {
            guard let sceneFile = group.sceneFile else {
                continue
            }

            let sceneSource = try Self.readSource(at: sceneFile)
            let sceneCommands = try Self.primaryCommands(in: sceneSource)
            let actors = try group.roomFiles.map { roomFile in
                let roomSource = try Self.readSource(at: roomFile.fileURL)
                return try Self.parseRoomActors(
                    roomName: roomFile.roomName,
                    source: roomSource,
                    actorIDByName: actorIDByName
                )
            }

            let environment = try Self.parseEnvironment(
                sceneName: group.sceneName,
                source: sceneSource,
                commands: sceneCommands
            )
            let paths = try Self.parsePaths(
                sceneName: group.sceneName,
                source: sceneSource,
                commands: sceneCommands
            )
            let exits = try Self.parseExits(
                sceneName: group.sceneName,
                source: sceneSource,
                commands: sceneCommands,
                entranceIndexByName: entranceIndexByName
            )

            let baseDirectory = context.output
                .appendingPathComponent("Manifests")
                .appendingPathComponent("scenes")
            let directory = group.outputRelativePath
                .split(separator: "/")
                .reduce(baseDirectory) { partialURL, component in
                    partialURL.appendingPathComponent(String(component), isDirectory: true)
                }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            try Self.writeJSON(
                SceneActorsFile(sceneName: group.sceneName, rooms: actors),
                to: directory.appendingPathComponent("actors.json")
            )
            try Self.writeJSON(environment, to: directory.appendingPathComponent("environment.json"))
            try Self.writeJSON(paths, to: directory.appendingPathComponent("paths.json"))
            try Self.writeJSON(exits, to: directory.appendingPathComponent("exits.json"))
            emittedScenes += 1
        }

        print("[\(name)] extracted \(emittedScenes) scene metadata bundle(s)")
    }

    public func verify(using context: OOTVerificationContext) throws {
        let scenesRoot = context.content
            .appendingPathComponent("Manifests")
            .appendingPathComponent("scenes")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: scenesRoot.path) else {
            print("[\(name)] verified 0 scene metadata bundle(s)")
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: scenesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[\(name)] verified 0 scene metadata bundle(s)")
            return
        }

        var verifiedScenes = 0

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, fileURL.lastPathComponent == "actors.json" else {
                continue
            }

            let directory = fileURL.deletingLastPathComponent()
            let _: SceneActorsFile = try Self.readJSON(from: directory.appendingPathComponent("actors.json"))
            let _: SceneEnvironmentFile = try Self.readJSON(from: directory.appendingPathComponent("environment.json"))
            let _: ScenePathsFile = try Self.readJSON(from: directory.appendingPathComponent("paths.json"))
            let _: SceneExitsFile = try Self.readJSON(from: directory.appendingPathComponent("exits.json"))
            verifiedScenes += 1
        }

        print("[\(name)] verified \(verifiedScenes) scene metadata bundle(s)")
    }
}

private extension SceneExtractor {
    struct SceneAssetGroup {
        let sceneName: String
        let outputRelativePath: String
        let sceneFile: URL?
        let roomFiles: [RoomAssetFile]
    }

    struct RoomAssetFile {
        let roomName: String
        let fileURL: URL
    }

    enum AssetKind {
        case scene(name: String, outputRelativePath: String)
        case room(sceneName: String, roomName: String, outputRelativePath: String)
    }

    struct ParsedArray {
        let name: String
        let body: String
    }

    struct ParsedCommand {
        let name: String
        let arguments: [String]

        func requireCount(_ expected: Int) throws {
            guard arguments.count == expected else {
                throw SceneExtractorError.invalidCommand("\(name) expected \(expected) arguments, found \(arguments.count)")
            }
        }
    }

    static func loadActorIDs(from outputRoot: URL) throws -> [String: Int] {
        let actorsURL = outputRoot
            .appendingPathComponent("Manifests")
            .appendingPathComponent("tables")
            .appendingPathComponent("actor-table.json")
        let actors: [ActorTableEntry] = try readJSON(from: actorsURL)
        return Dictionary(uniqueKeysWithValues: actors.map { ($0.enumName, $0.id) })
    }

    static func loadEntranceIndices(from sourceRoot: URL) throws -> [String: Int] {
        let tableURL = sourceRoot
            .appendingPathComponent("include")
            .appendingPathComponent("tables")
            .appendingPathComponent("entrance_table.h")
        let macros = try CHeaderParser().parseMacros(at: tableURL, matching: ["DEFINE_ENTRANCE"])
        return Dictionary(uniqueKeysWithValues: macros.compactMap { macro in
            guard let tableIndex = macro.tableIndex, let name = macro.arguments.first else {
                return nil
            }
            return (name, tableIndex)
        })
    }

    static func sceneAssetGroups(in root: URL, fileManager: FileManager) throws -> [SceneAssetGroup] {
        var sceneFiles: [String: URL] = [:]
        var roomFiles: [String: [RoomAssetFile]] = [:]
        var sceneNamesByKey: [String: String] = [:]

        if let sourceFiles = try sceneAssetSourceFiles(in: root, fileManager: fileManager) {
            for fileURL in sourceFiles {
                let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                guard let assetKind = classifyAsset(relativePath: relativePath) else {
                    continue
                }
                register(
                    assetKind: assetKind,
                    fileURL: fileURL,
                    sceneNamesByKey: &sceneNamesByKey,
                    sceneFiles: &sceneFiles,
                    roomFiles: &roomFiles
                )
            }
        } else {
            for assetRoot in sceneAssetRoots(in: root, fileManager: fileManager) {
                guard let enumerator = fileManager.enumerator(
                    at: assetRoot,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }

                for case let fileURL as URL in enumerator {
                    let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    guard values.isRegularFile == true else {
                        continue
                    }

                    let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
                    guard let assetKind = classifyAsset(relativePath: relativePath) else {
                        continue
                    }

                    register(
                        assetKind: assetKind,
                        fileURL: fileURL,
                        sceneNamesByKey: &sceneNamesByKey,
                        sceneFiles: &sceneFiles,
                        roomFiles: &roomFiles
                    )
                }
            }
        }

        let allKeys = Set(sceneFiles.keys).union(roomFiles.keys)
        return allKeys.sorted().map { key in
            SceneAssetGroup(
                sceneName: sceneNamesByKey[key] ?? key.components(separatedBy: "/").last ?? key,
                outputRelativePath: key,
                sceneFile: sceneFiles[key],
                roomFiles: (roomFiles[key] ?? []).sorted { $0.roomName < $1.roomName }
            )
        }
    }

    static func register(
        assetKind: AssetKind,
        fileURL: URL,
        sceneNamesByKey: inout [String: String],
        sceneFiles: inout [String: URL],
        roomFiles: inout [String: [RoomAssetFile]]
    ) {
        switch assetKind {
        case .scene(let name, let outputRelativePath):
            sceneNamesByKey[outputRelativePath] = name
            sceneFiles[outputRelativePath] = fileURL
        case .room(let sceneName, let roomName, let outputRelativePath):
            sceneNamesByKey[outputRelativePath] = sceneName
            roomFiles[outputRelativePath, default: []].append(
                RoomAssetFile(roomName: roomName, fileURL: fileURL)
            )
        }
    }

    static func sceneAssetSourceFiles(in root: URL, fileManager: FileManager) throws -> [URL]? {
        let sourceListURL = root
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("extract", isDirectory: true)
            .appendingPathComponent("write_source.txt")
        guard fileManager.fileExists(atPath: sourceListURL.path) else {
            return nil
        }

        let sourceList = try readSource(at: sourceListURL)
        let canonicalRelativePaths = sourceList
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("assets/scenes/") }
            .filter { $0.hasSuffix("_scene.c") || firstMatch(of: try! NSRegularExpression(pattern: #"_room_\d+\.c$"#), in: $0) != nil }

        var resolvedFiles: [URL] = []
        var seenPaths: Set<String> = []

        for relativePath in canonicalRelativePaths {
            let directURL = root.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: directURL.path), seenPaths.insert(directURL.path).inserted {
                resolvedFiles.append(directURL)
            }
        }

        let extractedRoot = root.appendingPathComponent("extracted", isDirectory: true)
        if
            fileManager.fileExists(atPath: extractedRoot.path),
            let versions = try? fileManager.contentsOfDirectory(
                at: extractedRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        {
            for versionRoot in versions {
                for relativePath in canonicalRelativePaths {
                    let extractedURL = versionRoot.appendingPathComponent(relativePath)
                    if fileManager.fileExists(atPath: extractedURL.path), seenPaths.insert(extractedURL.path).inserted {
                        resolvedFiles.append(extractedURL)
                    }
                }
            }
        }

        return resolvedFiles
    }

    static func sceneAssetRoots(in root: URL, fileManager: FileManager) -> [URL] {
        var roots: [URL] = []

        let directAssetsScenes = root
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
        if fileManager.fileExists(atPath: directAssetsScenes.path) {
            roots.append(directAssetsScenes)
        }

        let extractedRoot = root.appendingPathComponent("extracted", isDirectory: true)
        if
            fileManager.fileExists(atPath: extractedRoot.path),
            let versions = try? fileManager.contentsOfDirectory(
                at: extractedRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        {
            for versionRoot in versions {
                let scenesRoot = versionRoot
                    .appendingPathComponent("assets", isDirectory: true)
                    .appendingPathComponent("scenes", isDirectory: true)
                if fileManager.fileExists(atPath: scenesRoot.path) {
                    roots.append(scenesRoot)
                }
            }
        }

        return roots
    }

    static func classifyAsset(relativePath: String) -> AssetKind? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let fileName = components.last else {
            return nil
        }

        if let sceneName = captureFirst(in: fileName, pattern: #"^([A-Za-z0-9_]+)_scene(?:\.[^.]+)?\.c$"#) {
            return .scene(name: sceneName, outputRelativePath: makeOutputRelativePath(from: components.dropLast()))
        }

        if
            let sceneName = captureFirst(in: fileName, pattern: #"^([A-Za-z0-9_]+)_room_\d+(?:\.[^.]+)?\.c$"#),
            let roomSuffix = captureFirst(in: fileName, pattern: #"^[A-Za-z0-9_]+_(room_\d+)(?:\.[^.]+)?\.c$"#)
        {
            return .room(
                sceneName: sceneName,
                roomName: "\(sceneName)_\(roomSuffix)",
                outputRelativePath: makeOutputRelativePath(from: components.dropLast())
            )
        }

        guard fileName.hasSuffix(".inc.c"), components.count >= 3 else {
            return nil
        }

        let parent = components[components.count - 2]
        let sceneDirectoryName = components[components.count - 3]
        if parent == "scene" {
            return .scene(
                name: sceneDirectoryName,
                outputRelativePath: makeOutputRelativePath(from: components.dropLast(2))
            )
        }
        if let roomSuffix = captureFirst(in: parent, pattern: #"^(room_\d+)$"#) {
            return .room(
                sceneName: sceneDirectoryName,
                roomName: "\(sceneDirectoryName)_\(roomSuffix)",
                outputRelativePath: makeOutputRelativePath(from: components.dropLast(2))
            )
        }

        return nil
    }

    static func makeOutputRelativePath(from components: ArraySlice<String>) -> String {
        let values = Array(components)
        if let extractedIndex = values.firstIndex(of: "extracted"), values.count > extractedIndex + 3 {
            let version = values[extractedIndex + 1]
            let assetsIndex = extractedIndex + 2
            if values[assetsIndex] == "assets", values.count > assetsIndex + 1, values[assetsIndex + 1] == "scenes" {
                return ([version] + values.suffix(from: assetsIndex + 2)).joined(separator: "/")
            }
        }

        if let assetsIndex = values.firstIndex(of: "assets"), values.count > assetsIndex + 1, values[assetsIndex + 1] == "scenes" {
            return values.suffix(from: assetsIndex + 2).joined(separator: "/")
        }

        return values.joined(separator: "/")
    }

    static func parseRoomActors(
        roomName: String,
        source: String,
        actorIDByName: [String: Int]
    ) throws -> RoomActorSpawns {
        let commands = try primaryCommands(in: source)
        guard let invocation = commands.first(where: { $0.name == "SCENE_CMD_ACTOR_LIST" }) else {
            return RoomActorSpawns(roomName: roomName, actors: [])
        }
        try invocation.requireCount(2)

        let arrayName = trimExpression(invocation.arguments[1])
        let actorArray = try array(named: arrayName, type: "ActorEntry", in: source)
        let actors = try topLevelBraceEntries(in: actorArray.body).map { entry in
            let fields = splitTopLevel(entry)
            guard fields.count == 4 else {
                throw SceneExtractorError.invalidActorEntry(entry)
            }

            let actorName = trimExpression(fields[0])
            guard let actorID = actorIDByName[actorName] else {
                throw SceneExtractorError.unresolvedActor(actorName)
            }

            return SceneActorSpawn(
                actorID: actorID,
                actorName: actorName,
                position: try parseVector3s(fields[1]),
                rotation: try parseVector3s(fields[2]),
                params: try parseSigned16Expression(fields[3])
            )
        }

        return RoomActorSpawns(roomName: roomName, actors: actors)
    }

    static func parseEnvironment(
        sceneName: String,
        source: String,
        commands: [ParsedCommand]
    ) throws -> SceneEnvironmentFile {
        guard let lightInvocation = commands.first(where: { $0.name == "SCENE_CMD_ENV_LIGHT_SETTINGS" }) else {
            throw SceneExtractorError.missingCommand("SCENE_CMD_ENV_LIGHT_SETTINGS")
        }
        try lightInvocation.requireCount(2)

        let timeInvocation = commands.first(where: { $0.name == "SCENE_CMD_TIME_SETTINGS" })
        let skyboxInvocation = commands.first(where: { $0.name == "SCENE_CMD_SKYBOX_SETTINGS" })
        let skyboxDisableInvocation = commands.first(where: { $0.name == "SCENE_CMD_SKYBOX_DISABLES" })

        let lightArray = try array(named: trimExpression(lightInvocation.arguments[1]), type: "EnvLightSettings", in: source)
        let lightSettings = try topLevelBraceEntries(in: lightArray.body).map(parseLightSetting)

        let time = if let timeInvocation {
            try parseTimeSettings(from: timeInvocation)
        } else {
            SceneTimeSettings(hour: 255, minute: 255, timeSpeed: 255)
        }

        let skybox = try parseSkyboxSettings(
            skyboxInvocation: skyboxInvocation,
            skyboxDisableInvocation: skyboxDisableInvocation
        )

        return SceneEnvironmentFile(
            sceneName: sceneName,
            time: time,
            skybox: skybox,
            lightSettings: lightSettings
        )
    }

    static func parsePaths(
        sceneName: String,
        source: String,
        commands: [ParsedCommand]
    ) throws -> ScenePathsFile {
        guard let invocation = commands.first(where: { $0.name == "SCENE_CMD_PATH_LIST" }) else {
            return ScenePathsFile(sceneName: sceneName, paths: [])
        }
        try invocation.requireCount(1)

        let vecArrays = try arrays(ofType: "Vec3s", in: source)
        let pathArray = try array(named: trimExpression(invocation.arguments[0]), type: "Path", in: source)
        let paths = try topLevelBraceEntries(in: pathArray.body).enumerated().map { index, entry in
            let fields = splitTopLevel(entry)
            guard fields.count == 2 else {
                throw SceneExtractorError.invalidPathEntry(entry)
            }

            let pointsName = trimExpression(fields[1])
            guard let pointsArray = vecArrays[pointsName] else {
                throw SceneExtractorError.missingArray(type: "Vec3s", name: pointsName)
            }

            let points = try topLevelBraceEntries(in: pointsArray.body).map(parseVector3s)
            return ScenePathDefinition(index: index, pointsName: pointsName, points: points)
        }

        return ScenePathsFile(sceneName: sceneName, paths: paths)
    }

    static func parseExits(
        sceneName: String,
        source: String,
        commands: [ParsedCommand],
        entranceIndexByName: [String: Int]
    ) throws -> SceneExitsFile {
        guard let invocation = commands.first(where: { $0.name == "SCENE_CMD_EXIT_LIST" }) else {
            return SceneExitsFile(sceneName: sceneName, exits: [])
        }
        try invocation.requireCount(1)

        let arrayName = trimExpression(invocation.arguments[0])
        let exitArray = try integerArray(named: arrayName, in: source)
        let exits = try splitTopLevel(exitArray.body)
            .filter { trimExpression($0).isEmpty == false }
            .enumerated()
            .map { index, token in
                let name = trimExpression(token)
                let entranceIndex: Int
                if let mapped = entranceIndexByName[name] {
                    entranceIndex = mapped
                } else {
                    entranceIndex = try Int(parseIntegerExpression(name))
                }
                return SceneExitDefinition(index: index, entranceIndex: entranceIndex, entranceName: name)
            }

        return SceneExitsFile(sceneName: sceneName, exits: exits)
    }

    static func parseLightSetting(_ entry: String) throws -> SceneLightSetting {
        let fields = splitTopLevel(entry)
        guard fields.count == 20 else {
            throw SceneExtractorError.invalidLightSetting(entry)
        }

        let values = try fields.map(parseIntegerExpression)
        let packedBlend = UInt16(bitPattern: try parseSigned16(values[18], field: "blendRateAndFogNear"))

        return SceneLightSetting(
            ambientColor: try parseRGB8(values[0...2]),
            light1Direction: try parseVector3b(values[3...5]),
            light1Color: try parseRGB8(values[6...8]),
            light2Direction: try parseVector3b(values[9...11]),
            light2Color: try parseRGB8(values[12...14]),
            fogColor: try parseRGB8(values[15...17]),
            blendRate: UInt8(((packedBlend >> 10) & 0x3F) * 4),
            fogNear: Int(packedBlend & 0x03FF),
            zFar: try parseSigned16(values[19], field: "zFar")
        )
    }

    static func parseTimeSettings(from invocation: ParsedCommand) throws -> SceneTimeSettings {
        try invocation.requireCount(3)
        return SceneTimeSettings(
            hour: Int(try parseUnsigned8Expression(invocation.arguments[0])),
            minute: Int(try parseUnsigned8Expression(invocation.arguments[1])),
            timeSpeed: Int(try parseUnsigned8Expression(invocation.arguments[2]))
        )
    }

    static func parseSkyboxSettings(
        skyboxInvocation: ParsedCommand?,
        skyboxDisableInvocation: ParsedCommand?
    ) throws -> SceneSkyboxSettings {
        let skyboxID: Int
        let skyboxConfig: Int
        let environmentLightingMode: String
        if let skyboxInvocation {
            try skyboxInvocation.requireCount(3)
            skyboxID = Int(try parseUnsigned8Expression(skyboxInvocation.arguments[0]))
            skyboxConfig = Int(try parseUnsigned8Expression(skyboxInvocation.arguments[1]))
            environmentLightingMode = trimExpression(skyboxInvocation.arguments[2])
        } else {
            skyboxID = 0
            skyboxConfig = 0
            environmentLightingMode = "0"
        }

        let skyboxDisabled: Bool
        let sunMoonDisabled: Bool
        if let skyboxDisableInvocation {
            try skyboxDisableInvocation.requireCount(2)
            skyboxDisabled = try parseBoolExpression(skyboxDisableInvocation.arguments[0])
            sunMoonDisabled = try parseBoolExpression(skyboxDisableInvocation.arguments[1])
        } else {
            skyboxDisabled = false
            sunMoonDisabled = false
        }

        return SceneSkyboxSettings(
            skyboxID: skyboxID,
            skyboxConfig: skyboxConfig,
            environmentLightingMode: environmentLightingMode,
            skyboxDisabled: skyboxDisabled,
            sunMoonDisabled: sunMoonDisabled
        )
    }

    static func primaryCommands(in source: String) throws -> [ParsedCommand] {
        let array = try firstArray(ofType: "SceneCmd", in: source)
        return try ParsedCommand.parseAll(in: array.body)
    }

    static func firstArray(ofType type: String, in source: String) throws -> ParsedArray {
        let sanitized = stripLineComments(from: source)
        let pattern = #"(?:^|\s)(?:static\s+)?\#(NSRegularExpression.escapedPattern(for: type))\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        guard let match = regex.firstMatch(
            in: sanitized,
            range: NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        ) else {
            throw SceneExtractorError.missingArray(type: type, name: "<first>")
        }

        let name = substring(in: sanitized, range: match.range(at: 1))
        let braceLocation = match.range.location + match.range.length - 1
        let bodyRange = try matchingBraceRange(in: sanitized, openingBraceLocation: braceLocation)
        return ParsedArray(name: name, body: substring(in: sanitized, range: bodyRange))
    }

    static func arrays(ofType type: String, in source: String) throws -> [String: ParsedArray] {
        let sanitized = stripLineComments(from: source)
        let pattern = #"(?:^|\s)(?:static\s+)?\#(NSRegularExpression.escapedPattern(for: type))\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let matches = regex.matches(
            in: sanitized,
            range: NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        )

        return try matches.reduce(into: [String: ParsedArray]()) { result, match in
            let name = substring(in: sanitized, range: match.range(at: 1))
            let braceLocation = match.range.location + match.range.length - 1
            let bodyRange = try matchingBraceRange(in: sanitized, openingBraceLocation: braceLocation)
            result[name] = ParsedArray(name: name, body: substring(in: sanitized, range: bodyRange))
        }
    }

    static func array(named name: String, type: String, in source: String) throws -> ParsedArray {
        let arraysByName = try arrays(ofType: type, in: source)
        guard let array = arraysByName[name] else {
            throw SceneExtractorError.missingArray(type: type, name: name)
        }
        return array
    }

    static func integerArray(named name: String, in source: String) throws -> ParsedArray {
        if let array = try? array(named: name, type: "u16", in: source) {
            return array
        }
        if let array = try? array(named: name, type: "s16", in: source) {
            return array
        }
        throw SceneExtractorError.missingArray(type: "u16|s16", name: name)
    }

    static func matchingBraceRange(in source: String, openingBraceLocation: Int) throws -> NSRange {
        let characters = Array(source.utf16)
        var depth = 0
        var index = openingBraceLocation + 1
        let bodyStart = index

        while index < characters.count {
            switch characters[index] {
            case 0x7B:
                depth += 1
            case 0x7D:
                if depth == 0 {
                    return NSRange(location: bodyStart, length: index - bodyStart)
                }
                depth -= 1
            default:
                break
            }
            index += 1
        }

        throw SceneExtractorError.unterminatedArray
    }

    static func topLevelBraceEntries(in body: String) throws -> [String] {
        var entries: [String] = []
        let characters = Array(body)
        var depth = 0
        var startIndex: Int?

        for (index, character) in characters.enumerated() {
            if character == "{" {
                if depth == 0 {
                    startIndex = index + 1
                }
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth < 0 {
                    throw SceneExtractorError.unbalancedBraces
                }
                if depth == 0, let startIndex {
                    entries.append(String(characters[startIndex..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        if depth != 0 {
            throw SceneExtractorError.unbalancedBraces
        }

        return entries
    }

    static func splitTopLevel(_ input: String) -> [String] {
        guard trimExpression(input).isEmpty == false else {
            return []
        }

        var parts: [String] = []
        var depthParentheses = 0
        var depthBraces = 0
        var depthBrackets = 0
        var current = ""
        var inBlockComment = false
        var previous: Character?

        for character in input {
            if inBlockComment {
                current.append(character)
                if previous == "*" && character == "/" {
                    inBlockComment = false
                }
                previous = character
                continue
            }

            if previous == "/" && character == "*" {
                inBlockComment = true
                current.append(character)
                previous = character
                continue
            }

            switch character {
            case "(":
                depthParentheses += 1
            case ")":
                depthParentheses -= 1
            case "{":
                depthBraces += 1
            case "}":
                depthBraces -= 1
            case "[":
                depthBrackets += 1
            case "]":
                depthBrackets -= 1
            case "," where depthParentheses == 0 && depthBraces == 0 && depthBrackets == 0:
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
                previous = nil
                continue
            default:
                break
            }

            current.append(character)
            previous = character
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.isEmpty == false {
            parts.append(tail)
        }

        return parts
    }

    static func stripLineComments(from source: String) -> String {
        var result = ""
        var iterator = source.makeIterator()
        var inString = false
        var inBlockComment = false
        var isEscaping = false
        var previous: Character?

        while let character = iterator.next() {
            if inBlockComment {
                result.append(character)
                if previous == "*" && character == "/" {
                    inBlockComment = false
                }
                previous = character
                continue
            }

            if inString {
                result.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
                previous = character
                continue
            }

            if character == "\"" {
                inString = true
                result.append(character)
                previous = character
                continue
            }

            if previous == "/" && character == "*" {
                inBlockComment = true
                result.append(character)
                previous = character
                continue
            }

            if previous == "/" && character == "/" {
                result.removeLast()
                while let next = iterator.next(), next != "\n" {
                    continue
                }
                result.append("\n")
                previous = nil
                continue
            }

            result.append(character)
            previous = character
        }

        return result
    }

    static func parseVector3s(_ expression: String) throws -> Vector3s {
        let trimmed = trimExpression(expression)
        let contents: String
        if trimmed.first == "{", trimmed.last == "}" {
            contents = String(trimmed.dropFirst().dropLast())
        } else {
            contents = trimmed
        }

        let values = splitTopLevel(contents)
        guard values.count == 3 else {
            throw SceneExtractorError.invalidVector(expression)
        }
        return Vector3s(
            x: try parseSigned16Expression(values[0]),
            y: try parseSigned16Expression(values[1]),
            z: try parseSigned16Expression(values[2])
        )
    }

    static func parseRGB8(_ values: ArraySlice<Int64>) throws -> RGB8 {
        RGB8(
            red: try parseUnsigned8(values[values.startIndex], field: "red"),
            green: try parseUnsigned8(values[values.startIndex + 1], field: "green"),
            blue: try parseUnsigned8(values[values.startIndex + 2], field: "blue")
        )
    }

    static func parseVector3b(_ values: ArraySlice<Int64>) throws -> Vector3b {
        Vector3b(
            x: try parseSigned8(values[values.startIndex], field: "x"),
            y: try parseSigned8(values[values.startIndex + 1], field: "y"),
            z: try parseSigned8(values[values.startIndex + 2], field: "z")
        )
    }

    static func parseSigned16Expression(_ expression: String) throws -> Int16 {
        try parseSigned16(parseIntegerExpression(expression), field: expression)
    }

    static func parseUnsigned8Expression(_ expression: String) throws -> UInt8 {
        try parseUnsigned8(parseIntegerExpression(expression), field: expression)
    }

    static func parseBoolExpression(_ expression: String) throws -> Bool {
        let trimmed = trimExpression(expression)
        switch trimmed {
        case "true", "TRUE", "1":
            return true
        case "false", "FALSE", "0":
            return false
        default:
            throw SceneExtractorError.invalidBoolean(trimmed)
        }
    }

    static func parseIntegerExpression(_ expression: String) throws -> Int64 {
        let trimmed = trimExpression(expression)

        if
            let match = firstMatch(
                of: try! NSRegularExpression(
                    pattern: #"BLEND_RATE_AND_FOG_NEAR\(\s*([^)]+?)\s*,\s*([^)]+?)\s*\)"#
                ),
                in: trimmed
            )
        {
            let blendRate = try parseIntegerLiteral(substring(in: trimmed, range: match.range(at: 1)))
            let fogNear = try parseIntegerLiteral(substring(in: trimmed, range: match.range(at: 2)))
            return (((blendRate / 4) & 0x3F) << 10) | (fogNear & 0x3FF)
        }

        if
            let match = firstMatch(
                of: try! NSRegularExpression(pattern: #"/\*\s*(0[xX][0-9A-Fa-f]+)\s*\*/"#),
                in: trimmed
            )
        {
            return try parseIntegerLiteral(substring(in: trimmed, range: match.range(at: 1)))
        }

        return try parseIntegerLiteral(trimmed)
    }

    static func parseIntegerLiteral(_ literal: String) throws -> Int64 {
        let trimmed = trimExpression(literal)
        guard trimmed.isEmpty == false else {
            throw SceneExtractorError.invalidIntegerLiteral(literal)
        }

        var sign: Int64 = 1
        var digits = trimmed[...]

        if digits.hasPrefix("-") {
            sign = -1
            digits.removeFirst()
        } else if digits.hasPrefix("+") {
            digits.removeFirst()
        }

        let radix: Int
        if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
            radix = 16
            digits.removeFirst(2)
        } else {
            radix = 10
        }

        guard digits.isEmpty == false, let magnitude = UInt64(digits, radix: radix) else {
            throw SceneExtractorError.invalidIntegerLiteral(literal)
        }

        if sign == -1 {
            guard magnitude <= UInt64(Int64.max) + 1 else {
                throw SceneExtractorError.invalidIntegerLiteral(literal)
            }
            if magnitude == UInt64(Int64.max) + 1 {
                return Int64.min
            }
            return -Int64(magnitude)
        }

        guard magnitude <= UInt64(Int64.max) else {
            throw SceneExtractorError.invalidIntegerLiteral(literal)
        }

        return Int64(magnitude)
    }

    static func parseSigned16(_ value: Int64, field: String) throws -> Int16 {
        if Int64(Int16.min)...Int64(Int16.max) ~= value {
            return Int16(value)
        }
        if 0...Int64(UInt16.max) ~= value {
            return Int16(bitPattern: UInt16(value))
        }
        throw SceneExtractorError.integerOutOfRange(field, value)
    }

    static func parseSigned8(_ value: Int64, field: String) throws -> Int8 {
        if Int64(Int8.min)...Int64(Int8.max) ~= value {
            return Int8(value)
        }
        if 0...Int64(UInt8.max) ~= value {
            return Int8(bitPattern: UInt8(value))
        }
        throw SceneExtractorError.integerOutOfRange(field, value)
    }

    static func parseUnsigned8(_ value: Int64, field: String) throws -> UInt8 {
        guard 0...Int64(UInt8.max) ~= value else {
            throw SceneExtractorError.integerOutOfRange(field, value)
        }
        return UInt8(value)
    }

    static func trimExpression(_ expression: String) -> String {
        expression.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func readSource(at url: URL) throws -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SceneExtractorError.unreadableFile(url.path, error)
        }
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    static func readJSON<T: Decodable>(from url: URL) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SceneExtractorError.unreadableFile(url.path, error)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SceneExtractorError.invalidJSON(url.lastPathComponent, error)
        }
    }

    static func captureFirst(in text: String, pattern: String) -> String? {
        guard let match = firstMatch(of: try! NSRegularExpression(pattern: pattern), in: text) else {
            return nil
        }
        return substring(in: text, range: match.range(at: 1))
    }

    static func firstMatch(of regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
    }

    static func substring(in text: String, range: NSRange) -> String {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
            return ""
        }
        return String(text[swiftRange])
    }
}

private extension SceneExtractor.ParsedCommand {
    static func parseAll(in source: String) throws -> [SceneExtractor.ParsedCommand] {
        let characters = Array(source)
        var index = 0
        var commands: [SceneExtractor.ParsedCommand] = []

        func skipTrivia() {
            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace || character == "," || character == ";" {
                    index += 1
                } else if character == "#" {
                    repeat {
                        var previous: Character?
                        while index < characters.count, characters[index] != "\n" {
                            previous = characters[index]
                            index += 1
                        }
                        if index < characters.count, characters[index] == "\n" {
                            index += 1
                        }
                        if previous != "\\" {
                            break
                        }
                    } while index < characters.count
                } else if
                    character == "/",
                    index + 1 < characters.count,
                    characters[index + 1] == "*"
                {
                    index += 2
                    while index + 1 < characters.count {
                        if characters[index] == "*", characters[index + 1] == "/" {
                            index += 2
                            break
                        }
                        index += 1
                    }
                } else {
                    break
                }
            }
        }

        while index < characters.count {
            skipTrivia()
            guard index < characters.count else {
                break
            }

            let start = index
            guard characters[index].isLetter || characters[index] == "_" else {
                throw SceneExtractorError.invalidCommand("Unexpected token in SceneCmd body: \(characters[index])")
            }

            index += 1
            while index < characters.count, (characters[index].isLetter || characters[index].isNumber || characters[index] == "_") {
                index += 1
            }

            let name = String(characters[start..<index])
            skipTrivia()
            guard index < characters.count, characters[index] == "(" else {
                throw SceneExtractorError.invalidCommand("Missing opening parenthesis for \(name)")
            }

            index += 1
            let argumentsStart = index
            var depth = 1

            while index < characters.count, depth > 0 {
                if characters[index] == "(" {
                    depth += 1
                } else if characters[index] == ")" {
                    depth -= 1
                    if depth == 0 {
                        break
                    }
                }
                index += 1
            }

            guard index < characters.count else {
                throw SceneExtractorError.invalidCommand("Unterminated invocation for \(name)")
            }

            let argumentsBody = String(characters[argumentsStart..<index])
            commands.append(
                SceneExtractor.ParsedCommand(
                    name: name,
                    arguments: SceneExtractor.splitTopLevel(argumentsBody)
                )
            )
            index += 1
        }

        return commands
    }
}

private enum SceneExtractorError: LocalizedError {
    case invalidActorEntry(String)
    case invalidBoolean(String)
    case invalidCommand(String)
    case invalidIntegerLiteral(String)
    case invalidJSON(String, Error)
    case invalidLightSetting(String)
    case invalidPathEntry(String)
    case invalidVector(String)
    case integerOutOfRange(String, Int64)
    case missingArray(type: String, name: String)
    case missingCommand(String)
    case unresolvedActor(String)
    case unreadableFile(String, Error)
    case unbalancedBraces
    case unterminatedArray

    var errorDescription: String? {
        switch self {
        case .invalidActorEntry(let entry):
            return "Unable to parse ActorEntry: \(entry)"
        case .invalidBoolean(let value):
            return "Unable to parse boolean expression: \(value)"
        case .invalidCommand(let detail):
            return "Unable to parse scene command: \(detail)"
        case .invalidIntegerLiteral(let literal):
            return "Unable to parse integer literal: \(literal)"
        case .invalidJSON(let name, let error):
            return "Failed to decode \(name): \(error.localizedDescription)"
        case .invalidLightSetting(let entry):
            return "Unable to parse EnvLightSettings entry: \(entry)"
        case .invalidPathEntry(let entry):
            return "Unable to parse Path entry: \(entry)"
        case .invalidVector(let expression):
            return "Unable to parse Vec3s expression: \(expression)"
        case .integerOutOfRange(let field, let value):
            return "Value \(value) is out of range for \(field)"
        case .missingArray(let type, let name):
            return "Missing \(type) array \(name)"
        case .missingCommand(let name):
            return "Missing scene command \(name)"
        case .unresolvedActor(let name):
            return "Unable to resolve actor id for \(name)"
        case .unreadableFile(let path, let error):
            return "Failed to read \(path): \(error.localizedDescription)"
        case .unbalancedBraces:
            return "Encountered unbalanced braces while parsing array entries"
        case .unterminatedArray:
            return "Encountered unterminated C array body"
        }
    }
}

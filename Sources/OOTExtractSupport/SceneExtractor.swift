import Foundation
import OOTDataModel

extension SceneExtractor {
    public func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let scenes = try Self.loadScenes(
            in: context.source,
            sceneName: context.sceneName,
            fileManager: fileManager
        )
        let metadataReferences = try? Self.loadMetadataReferences(
            outputRoot: context.output,
            sourceRoot: context.source
        )
        let vertexParser = VertexParser()
        let displayListParser = DisplayListParser()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var extractedRooms = 0
        var extractedMetadataScenes = 0
        var skippedScenes = 0

        sceneLoop: for scene in scenes {
            let sceneDirectory = context.output
                .appendingPathComponent("Scenes", isDirectory: true)
                .appendingPathComponent(scene.name, isDirectory: true)
                .appendingPathComponent("rooms", isDirectory: true)
            try fileManager.createDirectory(at: sceneDirectory, withIntermediateDirectories: true)

            var roomActors: [RoomActorSpawns] = []

            for room in scene.rooms {
                let sourceFile: URL
                do {
                    sourceFile = try Self.resolveRoomSource(
                        for: room,
                        scene: scene,
                        sourceRoot: context.source,
                        fileManager: fileManager
                    )
                } catch let error as SceneExtractorError where error.isMissingSource {
                    guard context.sceneName == nil else {
                        throw error
                    }
                    print("[\(name)] skipped scene \(scene.name): \(error.localizedDescription)")
                    skippedScenes += 1
                    continue sceneLoop
                }
                let vertexArrays = try vertexParser.parseVertexArrays(in: sourceFile, sourceRoot: context.source)
                let displayLists: [ParsedDisplayList]
                do {
                    displayLists = try displayListParser.parseDisplayLists(in: sourceFile, sourceRoot: context.source)
                } catch {
                    print(
                        "[\(name)] display list parse failed for scene \(scene.name) room \(room.outputName) at \(sourceFile.path): " +
                        "\(error.localizedDescription)"
                    )
                    throw error
                }
                guard vertexArrays.isEmpty == false else {
                    guard context.sceneName == nil else {
                        throw SceneExtractorError.noVertexData(scene.name, room.outputName, sourceFile.path)
                    }
                    print(
                        "[\(name)] skipped scene \(scene.name): " +
                        SceneExtractorError.noVertexData(scene.name, room.outputName, sourceFile.path).localizedDescription
                    )
                    skippedScenes += 1
                    continue sceneLoop
                }
                guard displayLists.isEmpty == false else {
                    guard context.sceneName == nil else {
                        throw SceneExtractorError.noDisplayListData(scene.name, room.outputName, sourceFile.path)
                    }
                    print(
                        "[\(name)] skipped scene \(scene.name): " +
                        SceneExtractorError.noDisplayListData(scene.name, room.outputName, sourceFile.path).localizedDescription
                    )
                    skippedScenes += 1
                    continue sceneLoop
                }

                let roomDirectory = sceneDirectory.appendingPathComponent(room.outputName, isDirectory: true)
                try fileManager.createDirectory(at: roomDirectory, withIntermediateDirectories: true)

                let vertices = vertexArrays.flatMap(\.vertices)
                let commands = displayLists.flatMap(\.commands)

                try VertexParser.encode(vertices).write(
                    to: roomDirectory.appendingPathComponent("vtx.bin"),
                    options: .atomic
                )
                try encoder.encode(commands).write(
                    to: roomDirectory.appendingPathComponent("dl.json"),
                    options: .atomic
                )

                if let metadataReferences {
                    let roomSource = try Self.readExpandedSource(at: sourceFile, sourceRoot: context.source)
                    roomActors.append(
                        try Self.parseRoomActors(
                            roomName: room.symbolName,
                            source: roomSource,
                            actorIDByName: metadataReferences.actorIDByName
                        )
                    )
                }

                extractedRooms += 1
            }

            guard let metadataReferences else {
                continue
            }

            let sceneSourceFile: URL
            do {
                sceneSourceFile = try Self.resolveSceneSource(
                    for: scene,
                    sourceRoot: context.source,
                    fileManager: fileManager
                )
            } catch let error as SceneExtractorError where error.isMissingSource {
                guard context.sceneName == nil else {
                    throw error
                }
                print("[\(name)] skipped scene metadata for \(scene.name): \(error.localizedDescription)")
                skippedScenes += 1
                continue
            }
            let sceneSource = try Self.readExpandedSource(at: sceneSourceFile, sourceRoot: context.source)
            let sceneCommands = try Self.sceneCommands(sceneName: scene.name, in: sceneSource)

            let metadataDirectory = try Self.metadataDirectory(
                for: scene,
                outputRoot: context.output,
                fileManager: fileManager
            )
            try Self.writeJSON(
                SceneActorsFile(sceneName: scene.name, rooms: roomActors),
                to: metadataDirectory.appendingPathComponent("actors.json")
            )
            try Self.writeJSON(
                try Self.parseEnvironment(
                    sceneName: scene.name,
                    source: sceneSource,
                    commands: sceneCommands
                ),
                to: metadataDirectory.appendingPathComponent("environment.json")
            )
            try Self.writeJSON(
                try Self.parsePaths(
                    sceneName: scene.name,
                    source: sceneSource,
                    commands: sceneCommands
                ),
                to: metadataDirectory.appendingPathComponent("paths.json")
            )
            try Self.writeJSON(
                try Self.parseExits(
                    sceneName: scene.name,
                    source: sceneSource,
                    commands: sceneCommands,
                    entranceIndexByName: metadataReferences.entranceIndexByName
                ),
                to: metadataDirectory.appendingPathComponent("exits.json")
            )
            extractedMetadataScenes += 1
        }

        print("[\(name)] extracted room geometry for \(extractedRooms) room(s)")
        print("[\(name)] extracted scene metadata for \(extractedMetadataScenes) scene(s)")
        if skippedScenes > 0 {
            print("[\(name)] skipped \(skippedScenes) scene(s) with missing source data")
        }
    }

    public func verify(using context: OOTVerificationContext) throws {
        let roomDirectories = try Self.roomDirectories(in: context.content, fileManager: .default)
        var verifiedRooms = 0

        for roomDirectory in roomDirectories {
            let vertexURL = roomDirectory.appendingPathComponent("vtx.bin")
            let displayListURL = roomDirectory.appendingPathComponent("dl.json")

            guard FileManager.default.fileExists(atPath: vertexURL.path) else {
                throw SceneExtractorError.missingOutput(vertexURL.path)
            }
            guard FileManager.default.fileExists(atPath: displayListURL.path) else {
                throw SceneExtractorError.missingOutput(displayListURL.path)
            }

            _ = try VertexParser.decode(Data(contentsOf: vertexURL), path: vertexURL.path)
            _ = try JSONDecoder().decode([F3DEX2Command].self, from: Data(contentsOf: displayListURL))
            verifiedRooms += 1
        }

        let metadataDirectories = try Self.metadataDirectories(in: context.content, fileManager: .default)
        var verifiedMetadataScenes = 0

        for metadataDirectory in metadataDirectories {
            let _: SceneActorsFile = try Self.readJSON(from: metadataDirectory.appendingPathComponent("actors.json"))
            let _: SceneEnvironmentFile = try Self.readJSON(
                from: metadataDirectory.appendingPathComponent("environment.json")
            )
            let _: ScenePathsFile = try Self.readJSON(from: metadataDirectory.appendingPathComponent("paths.json"))
            let _: SceneExitsFile = try Self.readJSON(from: metadataDirectory.appendingPathComponent("exits.json"))
            verifiedMetadataScenes += 1
        }

        print("[\(name)] verified \(verifiedRooms) room geometry bundle(s)")
        print("[\(name)] verified \(verifiedMetadataScenes) scene metadata bundle(s)")
    }
}

private extension SceneExtractor {
    struct MetadataReferenceTables {
        let actorIDByName: [String: Int]
        let entranceIndexByName: [String: Int]
    }

    struct SceneDefinition: Equatable {
        let name: String
        let categoryPath: String
        let xmlURL: URL
        let sceneSymbolName: String
        let sceneSourceName: String
        let rooms: [RoomDefinition]
    }

    struct RoomDefinition: Equatable {
        let symbolName: String
        let sourceName: String
        let outputName: String
    }

    struct ParsedArray {
        let name: String
        let body: String
    }

    struct ParsedCommandArray {
        let array: ParsedArray
        let commands: [ParsedCommand]
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

    static func loadMetadataReferences(outputRoot: URL, sourceRoot: URL) throws -> MetadataReferenceTables {
        MetadataReferenceTables(
            actorIDByName: try loadActorIDs(from: outputRoot),
            entranceIndexByName: try loadEntranceIndices(from: sourceRoot)
        )
    }

    static func loadActorIDs(from outputRoot: URL) throws -> [String: Int] {
        let actorsURL = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("tables", isDirectory: true)
            .appendingPathComponent("actor-table.json")
        let actors: [ActorTableEntry] = try readJSON(from: actorsURL)
        return Dictionary(uniqueKeysWithValues: actors.map { ($0.enumName, $0.id) })
    }

    static func loadEntranceIndices(from sourceRoot: URL) throws -> [String: Int] {
        let tableURL = sourceRoot
            .appendingPathComponent("include", isDirectory: true)
            .appendingPathComponent("tables", isDirectory: true)
            .appendingPathComponent("entrance_table.h")
        let macros = try CHeaderParser().parseMacros(at: tableURL, matching: ["DEFINE_ENTRANCE"])
        return Dictionary(uniqueKeysWithValues: macros.compactMap { macro in
            guard let tableIndex = macro.tableIndex, let name = macro.arguments.first else {
                return nil
            }
            return (name, tableIndex)
        })
    }

    static func loadScenes(in sourceRoot: URL, sceneName: String?, fileManager: FileManager) throws -> [SceneDefinition] {
        let xmlRoot = sourceRoot
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("xml", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
        guard fileManager.fileExists(atPath: xmlRoot.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: xmlRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var scenes: [SceneDefinition] = []

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true, fileURL.pathExtension == "xml" else {
                continue
            }

            let name = fileURL.deletingPathExtension().lastPathComponent
            guard name.contains("_pal_") == false else {
                continue
            }
            if let sceneName, name != sceneName {
                continue
            }

            let sceneXML = try parseSceneXML(from: fileURL, sceneName: name)
            guard sceneXML.rooms.isEmpty == false else {
                continue
            }

            let parentPath = fileURL.deletingLastPathComponent().path
            let relativeCategoryPath = String(parentPath.dropFirst(xmlRoot.path.count)).trimmingPrefix("/")

            scenes.append(
                SceneDefinition(
                    name: name,
                    categoryPath: relativeCategoryPath,
                    xmlURL: fileURL,
                    sceneSymbolName: sceneXML.scene.symbolName,
                    sceneSourceName: sceneXML.scene.sourceName,
                    rooms: sceneXML.rooms
                )
            )
        }

        if let sceneName, scenes.isEmpty {
            throw SceneExtractorError.sceneNotFound(sceneName)
        }

        return scenes.sorted { $0.name < $1.name }
    }

    static func parseSceneXML(from xmlURL: URL, sceneName: String) throws -> (scene: RawSceneDefinition, rooms: [RoomDefinition]) {
        let data = try Data(contentsOf: xmlURL)
        let delegate = SceneXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "Unknown XML parsing error"
            throw SceneExtractorError.invalidSceneXML(xmlURL.path, message)
        }

        let scene = delegate.scene ?? RawSceneDefinition(
            symbolName: "\(sceneName)_scene",
            sourceName: "\(sceneName)_scene"
        )
        let rooms = try delegate.rooms.map(makeRoomDefinition(from:))
        return (scene, rooms)
    }

    static func makeRoomDefinition(from rawRoom: RawRoomDefinition) throws -> RoomDefinition {
        let roomName = rawRoom.symbolName
        guard let roomSuffixRange = roomName.range(of: "_room_") else {
            throw SceneExtractorError.invalidRoomName(roomName)
        }

        let suffix = roomName[roomSuffixRange.upperBound...]
        return RoomDefinition(
            symbolName: roomName,
            sourceName: rawRoom.sourceName,
            outputName: "room_\(suffix)"
        )
    }

    static func metadataDirectory(for scene: SceneDefinition, outputRoot: URL, fileManager: FileManager) throws -> URL {
        var directory = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)

        for component in scene.categoryPath.split(separator: "/") {
            directory.appendPathComponent(String(component), isDirectory: true)
        }
        directory.appendPathComponent(scene.name, isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func resolveSceneSource(
        for scene: SceneDefinition,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> URL {
        try resolveAssetSource(
            candidateBasenames: [scene.sceneSourceName, scene.sceneSymbolName],
            scene: scene,
            sourceRoot: sourceRoot,
            fileManager: fileManager,
            preferredExtensions: ["c", "inc.c"],
            missingError: .missingSceneSource(scene.name, scene.xmlURL.path)
        )
    }

    static func resolveRoomSource(
        for room: RoomDefinition,
        scene: SceneDefinition,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> URL {
        try resolveAssetSource(
            candidateBasenames: [room.sourceName, room.symbolName],
            scene: scene,
            sourceRoot: sourceRoot,
            fileManager: fileManager,
            preferredExtensions: ["c", "inc.c"],
            missingError: .missingRoomSource(scene.name, room.outputName, scene.xmlURL.path)
        )
    }

    static func resolveAssetSource(
        candidateBasenames: [String],
        scene: SceneDefinition,
        sourceRoot: URL,
        fileManager: FileManager,
        preferredExtensions: [String],
        missingError: SceneExtractorError
    ) throws -> URL {
        let directSearchDirectories = [
            sourceRoot
                .appendingPathComponent("build", isDirectory: true)
                .appendingPathComponent("assets", isDirectory: true)
                .appendingPathComponent("scenes", isDirectory: true)
                .appendingPathComponent(scene.categoryPath, isDirectory: true)
                .appendingPathComponent(scene.name, isDirectory: true),
            sourceRoot
                .appendingPathComponent("assets", isDirectory: true)
                .appendingPathComponent("scenes", isDirectory: true)
                .appendingPathComponent(scene.categoryPath, isDirectory: true)
                .appendingPathComponent(scene.name, isDirectory: true),
        ]

        for directory in directSearchDirectories where fileManager.fileExists(atPath: directory.path) {
            for basename in candidateBasenames {
                for fileExtension in preferredExtensions {
                    let candidate = directory.appendingPathComponent("\(basename).\(fileExtension)")
                    if fileManager.fileExists(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }

        let searchRoots = [
            sourceRoot.appendingPathComponent("build", isDirectory: true),
            sourceRoot,
        ]

        for searchRoot in searchRoots where fileManager.fileExists(atPath: searchRoot.path) {
            if let match = try firstMatchingSource(
                namedAnyOf: candidateBasenames,
                preferredExtensions: preferredExtensions,
                in: searchRoot,
                fileManager: fileManager
            ) {
                return match
            }
        }

        throw missingError
    }

    static func firstMatchingSource(
        namedAnyOf basenames: [String],
        preferredExtensions: [String],
        in root: URL,
        fileManager: FileManager
    ) throws -> URL? {
        var filenamePriority: [String: Int] = [:]
        for basename in basenames {
            for (priority, fileExtension) in preferredExtensions.enumerated() {
                filenamePriority["\(basename).\(fileExtension)"] = priority
            }
        }
        let candidateNames = Set(filenamePriority.keys)

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let matches = try enumerator.compactMap { item -> URL? in
            guard let fileURL = item as? URL else {
                return nil
            }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                return nil
            }

            guard candidateNames.contains(fileURL.lastPathComponent) else {
                return nil
            }

            return fileURL
        }

        return matches.min { lhs, rhs in
            let lhsPriority = filenamePriority[lhs.lastPathComponent] ?? Int.max
            let rhsPriority = filenamePriority[rhs.lastPathComponent] ?? Int.max
            if lhsPriority == rhsPriority {
                return lhs.path < rhs.path
            }
            return lhsPriority < rhsPriority
        }
    }

    static func parseRoomActors(
        roomName: String,
        source: String,
        actorIDByName: [String: Int]
    ) throws -> RoomActorSpawns {
        let commands = try roomCommands(roomName: roomName, in: source)
        guard let invocation = commands.first(where: { $0.name == "SCENE_CMD_ACTOR_LIST" }) else {
            return RoomActorSpawns(roomName: roomName, actors: [])
        }
        try invocation.requireCount(2)

        let actorArray = try array(
            named: trimExpression(invocation.arguments[1]),
            type: "ActorEntry",
            in: source
        )
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

        let lightArray = try array(
            named: trimExpression(lightInvocation.arguments[1]),
            type: "EnvLightSettings",
            in: source
        )
        let lightSettings = try topLevelBraceEntries(in: lightArray.body).map(parseLightSetting)

        let time = if let timeInvocation {
            try parseTimeSettings(from: timeInvocation)
        } else {
            SceneTimeSettings(hour: 255, minute: 255, timeSpeed: 255)
        }

        return SceneEnvironmentFile(
            sceneName: sceneName,
            time: time,
            skybox: try parseSkyboxSettings(
                skyboxInvocation: skyboxInvocation,
                skyboxDisableInvocation: skyboxDisableInvocation
            ),
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

        let exitArray = try integerArray(named: trimExpression(invocation.arguments[0]), in: source)
        let exits = splitTopLevel(exitArray.body)
            .filter { trimExpression($0).isEmpty == false }
            .enumerated()
            .map { index, token in
                let name = trimExpression(token)
                let entranceIndex = if let mapped = entranceIndexByName[name] {
                    mapped
                } else if let parsed = try? Int(parseIntegerExpression(name)) {
                    parsed
                } else {
                    0
                }
                return SceneExitDefinition(index: index, entranceIndex: entranceIndex, entranceName: name)
            }

        return SceneExitsFile(sceneName: sceneName, exits: exits)
    }

    static func parseLightSetting(_ entry: String) throws -> SceneLightSetting {
        let fields = splitTopLevel(entry)
        if fields.count == 20 {
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

        if fields.count == 8 {
            let packedBlend = UInt16(bitPattern: try parseSigned16Expression(fields[6]))
            return SceneLightSetting(
                ambientColor: try parseRGB8Expression(fields[0]),
                light1Direction: try parseVector3bExpression(fields[1]),
                light1Color: try parseRGB8Expression(fields[2]),
                light2Direction: try parseVector3bExpression(fields[3]),
                light2Color: try parseRGB8Expression(fields[4]),
                fogColor: try parseRGB8Expression(fields[5]),
                blendRate: UInt8(((packedBlend >> 10) & 0x3F) * 4),
                fogNear: Int(packedBlend & 0x03FF),
                zFar: try parseSigned16Expression(fields[7])
            )
        }

        throw SceneExtractorError.invalidLightSetting(entry)
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
            skyboxID = Int((try? parseUnsigned8Expression(skyboxInvocation.arguments[0])) ?? 0)
            skyboxConfig = Int((try? parseUnsigned8Expression(skyboxInvocation.arguments[1])) ?? 0)
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

    static func sceneCommands(sceneName: String, in source: String) throws -> [ParsedCommand] {
        let preferredName = "\(sceneName)_sceneCommands"
        let candidates = try parsedCommandArrays(in: source)
        guard candidates.isEmpty == false else {
            throw SceneExtractorError.missingArray(type: "SceneCmd", name: "<first>")
        }

        if let preferred = candidates.first(where: { $0.array.name == preferredName }) {
            if
                let best = selectBestSceneCommandArray(from: candidates),
                sceneCommandScore(for: best) > sceneCommandScore(for: preferred)
            {
                return best.commands
            }
            return preferred.commands
        }

        guard let selected = selectBestSceneCommandArray(from: candidates) else {
            throw SceneExtractorError.missingArray(type: "SceneCmd", name: "<first>")
        }
        return selected.commands
    }

    static func roomCommands(roomName: String, in source: String) throws -> [ParsedCommand] {
        let preferredName = "\(roomName)Commands"
        if let array = try? array(named: preferredName, type: "SceneCmd", in: source) {
            return try ParsedCommand.parseAll(in: array.body)
        }

        return try primaryCommands(in: source)
    }

    static func primaryCommands(in source: String) throws -> [ParsedCommand] {
        let array = try firstArray(ofType: "SceneCmd", in: source)
        return try ParsedCommand.parseAll(in: array.body)
    }

    static func parsedCommandArrays(in source: String) throws -> [ParsedCommandArray] {
        try orderedArrays(ofType: "SceneCmd", in: source).map { array in
            ParsedCommandArray(array: array, commands: try ParsedCommand.parseAll(in: array.body))
        }
    }

    static func selectBestSceneCommandArray(from candidates: [ParsedCommandArray]) -> ParsedCommandArray? {
        candidates
            .enumerated()
            .max { lhs, rhs in
                let lhsScore = sceneCommandScore(for: lhs.element)
                let rhsScore = sceneCommandScore(for: rhs.element)
                if lhsScore == rhsScore {
                    return lhs.offset > rhs.offset
                }
                return lhsScore < rhsScore
            }?
            .element
    }

    static func sceneCommandScore(for candidate: ParsedCommandArray) -> Int {
        let commandNames = Set(candidate.commands.map(\.name))
        var score = 0

        if candidate.array.name.hasSuffix("_sceneCommands") {
            score += 100
        }
        if commandNames.contains("SCENE_CMD_ENV_LIGHT_SETTINGS") {
            score += 500
        }
        if commandNames.contains("SCENE_CMD_ROOM_LIST") {
            score += 300
        }
        if commandNames.contains("SCENE_CMD_PATH_LIST") {
            score += 150
        }
        if commandNames.contains("SCENE_CMD_EXIT_LIST") {
            score += 150
        }
        if commandNames.contains("SCENE_CMD_ENTRANCE_LIST") {
            score += 75
        }
        if commandNames.contains("SCENE_CMD_SPAWN_LIST") {
            score += 75
        }
        if commandNames.contains("SCENE_CMD_COL_HEADER") {
            score += 150
        }
        if commandNames.contains("SCENE_CMD_ALTERNATE_HEADER_LIST") {
            score -= 50
        }
        if commandNames.contains("SCENE_CMD_ACTOR_LIST") {
            score -= 100
        }

        return score
    }

    static func firstArray(ofType type: String, in source: String) throws -> ParsedArray {
        let sanitized = stripLineComments(from: source)
        let pattern =
            #"(?:^|\s)(?:static\s+)?\#(NSRegularExpression.escapedPattern(for: type))\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{"#
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

    static func orderedArrays(ofType type: String, in source: String) throws -> [ParsedArray] {
        let sanitized = stripLineComments(from: source)
        let pattern =
            #"(?:^|\s)(?:static\s+)?\#(NSRegularExpression.escapedPattern(for: type))\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let matches = regex.matches(
            in: sanitized,
            range: NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        )

        return try matches.map { match in
            let name = substring(in: sanitized, range: match.range(at: 1))
            let braceLocation = match.range.location + match.range.length - 1
            let bodyRange = try matchingBraceRange(in: sanitized, openingBraceLocation: braceLocation)
            return ParsedArray(name: name, body: substring(in: sanitized, range: bodyRange))
        }
    }

    static func arrays(ofType type: String, in source: String) throws -> [String: ParsedArray] {
        try orderedArrays(ofType: type, in: source).reduce(into: [String: ParsedArray]()) { result, array in
            result[array.name] = array
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
                    entries.append(
                        String(characters[startIndex..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    )
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

    static func parseRGB8Expression(_ expression: String) throws -> RGB8 {
        try parseRGB8(ArraySlice(parseIntegerTriplet(expression)))
    }

    static func parseVector3bExpression(_ expression: String) throws -> Vector3b {
        try parseVector3b(ArraySlice(parseIntegerTriplet(expression)))
    }

    static func parseIntegerTriplet(_ expression: String) throws -> [Int64] {
        let trimmed = trimExpression(expression)
        let contents: String
        if trimmed.first == "{", trimmed.last == "}" {
            contents = String(trimmed.dropFirst().dropLast())
        } else {
            contents = trimmed
        }

        let values = try splitTopLevel(contents).map(parseIntegerExpression)
        guard values.count == 3 else {
            throw SceneExtractorError.invalidVector(expression)
        }
        return values
    }

    static func parseSigned16Expression(_ expression: String) throws -> Int16 {
        try parseSigned16(parseIntegerExpression(expression), field: expression)
    }

    static func parseUnsigned8Expression(_ expression: String) throws -> UInt8 {
        try parseUnsigned8(parseIntegerExpression(expression), field: expression)
    }

    static func parseBoolExpression(_ expression: String) throws -> Bool {
        switch trimExpression(expression) {
        case "true", "TRUE", "1":
            true
        case "false", "FALSE", "0":
            false
        default:
            throw SceneExtractorError.invalidBoolean(expression)
        }
    }

    static func parseIntegerExpression(_ expression: String) throws -> Int64 {
        let trimmed = trimExpression(expression)

        if trimmed.first == "(", trimmed.last == ")" {
            let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.isEmpty == false {
                return try parseIntegerExpression(inner)
            }
        }

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
            return (((blendRate / 4) & 0x3F) << 10) | (fogNear & 0x03FF)
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

    static func roomDirectories(in contentRoot: URL, fileManager: FileManager) throws -> [URL] {
        let scenesRoot = contentRoot.appendingPathComponent("Scenes", isDirectory: true)
        guard fileManager.fileExists(atPath: scenesRoot.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: scenesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else {
                return nil
            }

            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true, url.lastPathComponent.hasPrefix("room_") else {
                return nil
            }

            return url
        }
        .sorted { $0.path < $1.path }
    }

    static func metadataDirectories(in contentRoot: URL, fileManager: FileManager) throws -> [URL] {
        let scenesRoot = contentRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
        guard fileManager.fileExists(atPath: scenesRoot.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: scenesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> URL? in
            guard let fileURL = item as? URL else {
                return nil
            }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, fileURL.lastPathComponent == "actors.json" else {
                return nil
            }

            return fileURL.deletingLastPathComponent()
        }
        .sorted { $0.path < $1.path }
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

    static func readExpandedSource(at url: URL, sourceRoot: URL) throws -> String {
        var visited = Set<String>()
        return try expandIncludeBackedSource(at: url, sourceRoot: sourceRoot, visited: &visited)
    }

    static func expandIncludeBackedSource(
        at url: URL,
        sourceRoot: URL,
        visited: inout Set<String>
    ) throws -> String {
        let standardizedPath = url.standardizedFileURL.path
        guard visited.insert(standardizedPath).inserted else {
            return ""
        }
        defer { visited.remove(standardizedPath) }

        let source = try readSource(at: url)
        let pattern = #"(?m)^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source))
        guard matches.isEmpty == false else {
            return source
        }

        var expanded = source
        for match in matches.reversed() {
            let includePath = substring(in: expanded, range: match.range(at: 1))
            guard includePath.hasSuffix(".inc.c") else {
                continue
            }

            let replacement = if let includeURL = resolveIncludedSource(
                path: includePath,
                relativeTo: url,
                sourceRoot: sourceRoot
            ) {
                try expandIncludeBackedSource(at: includeURL, sourceRoot: sourceRoot, visited: &visited)
            } else {
                ""
            }

            guard let replacementRange = Range(match.range, in: expanded) else {
                continue
            }
            expanded.replaceSubrange(replacementRange, with: replacement)
        }

        return expanded
    }

    static func resolveIncludedSource(path: String, relativeTo sourceFile: URL, sourceRoot: URL) -> URL? {
        let candidates = [
            sourceFile.deletingLastPathComponent().appendingPathComponent(path),
            assetRoot(for: sourceFile)?.appendingPathComponent(path),
            sourceRoot.appendingPathComponent(path),
            sourceRoot.appendingPathComponent("build", isDirectory: true).appendingPathComponent(path),
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func assetRoot(for sourceFile: URL) -> URL? {
        let standardizedPath = sourceFile.standardizedFileURL.path
        guard let assetsRange = standardizedPath.range(of: "/assets/") else {
            return nil
        }

        return URL(
            fileURLWithPath: String(standardizedPath[..<assetsRange.lowerBound]),
            isDirectory: true
        )
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

private struct RawSceneDefinition: Equatable {
    let symbolName: String
    let sourceName: String
}

private struct RawRoomDefinition: Equatable {
    let symbolName: String
    let sourceName: String
}

private final class SceneXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var scene: RawSceneDefinition?
    private(set) var rooms: [RawRoomDefinition] = []
    private var currentFileName: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "File":
            currentFileName = attributeDict["Name"]
        case "Scene":
            guard let symbolName = attributeDict["Name"] else {
                return
            }
            scene = RawSceneDefinition(
                symbolName: symbolName,
                sourceName: currentFileName ?? symbolName
            )
        case "Room":
            guard let symbolName = attributeDict["Name"] else {
                return
            }
            rooms.append(
                RawRoomDefinition(
                    symbolName: symbolName,
                    sourceName: currentFileName ?? symbolName
                )
            )
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "File" {
            currentFileName = nil
        }
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
    case invalidRoomName(String)
    case invalidSceneXML(String, String)
    case invalidVector(String)
    case integerOutOfRange(String, Int64)
    case missingArray(type: String, name: String)
    case missingCommand(String)
    case missingOutput(String)
    case missingRoomSource(String, String, String)
    case missingSceneSource(String, String)
    case noDisplayListData(String, String, String)
    case noVertexData(String, String, String)
    case sceneNotFound(String)
    case unresolvedActor(String)
    case unreadableFile(String, Error)
    case unbalancedBraces
    case unterminatedArray

    var isMissingSource: Bool {
        switch self {
        case .missingRoomSource, .missingSceneSource:
            true
        default:
            false
        }
    }

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
        case .invalidRoomName(let name):
            return "Unsupported room name '\(name)'."
        case .invalidSceneXML(let path, let message):
            return "Failed to parse scene XML '\(path)': \(message)"
        case .invalidVector(let expression):
            return "Unable to parse Vec3s expression: \(expression)"
        case .integerOutOfRange(let field, let value):
            return "Value \(value) is out of range for \(field)"
        case .missingArray(let type, let name):
            return "Missing \(type) array \(name)"
        case .missingCommand(let name):
            return "Missing scene command \(name)"
        case .missingOutput(let path):
            return "Missing extracted artifact at '\(path)'."
        case .missingRoomSource(let scene, let room, let xmlPath):
            return "Could not locate source data for scene '\(scene)' room '\(room)' referenced by '\(xmlPath)'."
        case .missingSceneSource(let scene, let xmlPath):
            return "Could not locate source data for scene '\(scene)' referenced by '\(xmlPath)'."
        case .noDisplayListData(let scene, let room, let source):
            return "No display list data was found for scene '\(scene)' room '\(room)' in '\(source)'."
        case .noVertexData(let scene, let room, let source):
            return "No vertex data was found for scene '\(scene)' room '\(room)' in '\(source)'."
        case .sceneNotFound(let sceneName):
            return "Scene XML '\(sceneName)' was not found under assets/xml/scenes."
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

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }

        return String(dropFirst(prefix.count))
    }
}

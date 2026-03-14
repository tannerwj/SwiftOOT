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
        let vertexParser = VertexParser()
        let displayListParser = DisplayListParser()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var extractedRooms = 0

        for scene in scenes {
            let sceneDirectory = context.output
                .appendingPathComponent("Scenes", isDirectory: true)
                .appendingPathComponent(scene.name, isDirectory: true)
                .appendingPathComponent("rooms", isDirectory: true)
            try fileManager.createDirectory(at: sceneDirectory, withIntermediateDirectories: true)

            for room in scene.rooms {
                let sourceFile = try Self.resolveRoomSource(
                    for: room,
                    scene: scene,
                    sourceRoot: context.source,
                    fileManager: fileManager
                )
                let vertexArrays = try vertexParser.parseVertexArrays(in: sourceFile, sourceRoot: context.source)
                let displayLists = try displayListParser.parseDisplayLists(in: sourceFile, sourceRoot: context.source)
                guard vertexArrays.isEmpty == false else {
                    throw SceneExtractorError.noVertexData(scene.name, room.outputName, sourceFile.path)
                }
                guard displayLists.isEmpty == false else {
                    throw SceneExtractorError.noDisplayListData(scene.name, room.outputName, sourceFile.path)
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
                extractedRooms += 1
            }
        }

        print("[\(name)] extracted room geometry for \(extractedRooms) room(s)")
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

        print("[\(name)] verified \(verifiedRooms) room geometry bundle(s)")
    }
}

private extension SceneExtractor {
    struct SceneDefinition: Equatable {
        let name: String
        let categoryPath: String
        let xmlURL: URL
        let rooms: [RoomDefinition]
    }

    struct RoomDefinition: Equatable {
        let symbolName: String
        let sourceName: String
        let outputName: String
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

            let rooms = try parseRooms(from: fileURL)
            guard rooms.isEmpty == false else {
                continue
            }

            let parentPath = fileURL.deletingLastPathComponent().path
            let relativeCategoryPath = String(parentPath.dropFirst(xmlRoot.path.count)).trimmingPrefix("/")

            scenes.append(
                SceneDefinition(
                    name: name,
                    categoryPath: relativeCategoryPath,
                    xmlURL: fileURL,
                    rooms: rooms
                )
            )
        }

        if let sceneName, scenes.isEmpty {
            throw SceneExtractorError.sceneNotFound(sceneName)
        }

        return scenes.sorted { $0.name < $1.name }
    }

    static func parseRooms(from xmlURL: URL) throws -> [RoomDefinition] {
        let data = try Data(contentsOf: xmlURL)
        let delegate = SceneXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "Unknown XML parsing error"
            throw SceneExtractorError.invalidSceneXML(xmlURL.path, message)
        }

        return try delegate.rooms.map(makeRoomDefinition(from:))
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

    static func resolveRoomSource(
        for room: RoomDefinition,
        scene: SceneDefinition,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> URL {
        let generatedSceneDirectory = sourceRoot
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
            .appendingPathComponent(scene.categoryPath, isDirectory: true)
            .appendingPathComponent(scene.name, isDirectory: true)
        let candidateBasenames = [room.sourceName, room.symbolName]
        let candidateExtensions = ["c", "inc.c"]

        for basename in candidateBasenames {
            for fileExtension in candidateExtensions {
                let candidate = generatedSceneDirectory.appendingPathComponent("\(basename).\(fileExtension)")
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        let searchRoots = [
            sourceRoot.appendingPathComponent("build", isDirectory: true),
            sourceRoot,
        ]

        for searchRoot in searchRoots where fileManager.fileExists(atPath: searchRoot.path) {
            if let match = try firstMatchingRoomSource(
                namedAnyOf: candidateBasenames,
                in: searchRoot,
                fileManager: fileManager
            ) {
                return match
            }
        }

        throw SceneExtractorError.missingRoomSource(scene.name, room.outputName, scene.xmlURL.path)
    }

    static func firstMatchingRoomSource(
        namedAnyOf basenames: [String],
        in root: URL,
        fileManager: FileManager
    ) throws -> URL? {
        let candidateNames = Set(basenames.flatMap { basename in
            ["\(basename).c", "\(basename).inc.c"]
        })

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

        return matches.sorted { $0.path < $1.path }.first
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
}

private struct RawRoomDefinition: Equatable {
    let symbolName: String
    let sourceName: String
}

private final class SceneXMLParserDelegate: NSObject, XMLParserDelegate {
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

private enum SceneExtractorError: LocalizedError {
    case invalidRoomName(String)
    case invalidSceneXML(String, String)
    case missingOutput(String)
    case missingRoomSource(String, String, String)
    case noDisplayListData(String, String, String)
    case noVertexData(String, String, String)
    case sceneNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidRoomName(let name):
            return "Unsupported room name '\(name)'."
        case .invalidSceneXML(let path, let message):
            return "Failed to parse scene XML '\(path)': \(message)"
        case .missingOutput(let path):
            return "Missing extracted room artifact at '\(path)'."
        case .missingRoomSource(let scene, let room, let xmlPath):
            return "Could not locate source data for scene '\(scene)' room '\(room)' referenced by '\(xmlPath)'."
        case .noDisplayListData(let scene, let room, let source):
            return "No display list data was found for scene '\(scene)' room '\(room)' in '\(source)'."
        case .noVertexData(let scene, let room, let source):
            return "No vertex data was found for scene '\(scene)' room '\(room)' in '\(source)'."
        case .sceneNotFound(let sceneName):
            return "Scene XML '\(sceneName)' was not found under assets/xml/scenes."
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

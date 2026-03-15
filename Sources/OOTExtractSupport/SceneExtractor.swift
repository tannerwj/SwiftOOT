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
                let vertexAddressMap = Self.makeVertexAddressMap(vertexArrays: vertexArrays)
                let commands = Self.rewriteVertexAddresses(
                    in: displayLists.flatMap(\.commands),
                    vertexAddressMap: vertexAddressMap
                )

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

struct CollisionSceneBinary: Equatable, Sendable {
    let minimumBounds: Vector3s
    let maximumBounds: Vector3s
    let vertices: [Vector3s]
    let polygons: [CollisionPolygonBinary]
    let surfaceTypes: [CollisionSurfaceTypeBinary]
    let waterBoxes: [CollisionWaterBoxBinary]
}

struct CollisionPolygonBinary: Equatable, Sendable {
    let surfaceType: UInt16
    let vertexA: UInt16
    let vertexB: UInt16
    let vertexC: UInt16
    let normal: Vector3s
    let distance: Int16
}

struct CollisionSurfaceTypeBinary: Equatable, Sendable {
    let low: UInt32
    let high: UInt32
}

struct CollisionWaterBoxBinary: Equatable, Sendable {
    let xMin: Int16
    let ySurface: Int16
    let zMin: Int16
    let xLength: UInt16
    let zLength: UInt16
    let properties: UInt32
}

extension CollisionExtractor {
    public func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let scenes = try SceneExtractor.loadScenes(
            in: context.source,
            sceneName: context.sceneName,
            fileManager: fileManager
        )
        var extractedScenes = 0
        var skippedScenes = 0

        for scene in scenes {
            let sceneSourceFile: URL
            do {
                sceneSourceFile = try SceneExtractor.resolveSceneSource(
                    for: scene,
                    sourceRoot: context.source,
                    fileManager: fileManager
                )
            } catch let error as SceneExtractorError where error.isMissingSource {
                guard context.sceneName == nil else {
                    throw error
                }
                print("[\(name)] skipped scene \(scene.name): \(error.localizedDescription)")
                skippedScenes += 1
                continue
            }

            let sceneSource = try SceneExtractor.readExpandedSource(at: sceneSourceFile, sourceRoot: context.source)
            guard let collision = try Self.parseCollision(sceneName: scene.name, source: sceneSource) else {
                continue
            }

            let sceneDirectory = context.output
                .appendingPathComponent("Scenes", isDirectory: true)
                .appendingPathComponent(scene.name, isDirectory: true)
            try fileManager.createDirectory(at: sceneDirectory, withIntermediateDirectories: true)
            try Self.encode(collision).write(
                to: sceneDirectory.appendingPathComponent("collision.bin"),
                options: .atomic
            )
            extractedScenes += 1
        }

        print("[\(name)] extracted \(extractedScenes) collision bundle(s)")
        if skippedScenes > 0 {
            print("[\(name)] skipped \(skippedScenes) scene(s) with missing source data")
        }
    }

    public func verify(using context: OOTVerificationContext) throws {
        let collisionFiles = try Self.collisionBinaryFiles(in: context.content, fileManager: .default)

        for collisionFile in collisionFiles {
            _ = try Self.decode(
                Data(contentsOf: collisionFile),
                path: collisionFile.path
            )
        }

        print("[\(name)] verified \(collisionFiles.count) collision bundle(s)")
    }

    static func encode(_ collision: CollisionSceneBinary) -> Data {
        var data = Data()
        data.reserveCapacity(
            20 +
                (collision.vertices.count * 6) +
                (collision.polygons.count * 16) +
                (collision.surfaceTypes.count * 8) +
                (collision.waterBoxes.count * 14)
        )

        data.append(bigEndian: collision.minimumBounds.x)
        data.append(bigEndian: collision.minimumBounds.y)
        data.append(bigEndian: collision.minimumBounds.z)
        data.append(bigEndian: collision.maximumBounds.x)
        data.append(bigEndian: collision.maximumBounds.y)
        data.append(bigEndian: collision.maximumBounds.z)
        data.append(bigEndian: UInt16(clamping: collision.vertices.count))
        data.append(bigEndian: UInt16(clamping: collision.polygons.count))
        data.append(bigEndian: UInt16(clamping: collision.surfaceTypes.count))
        data.append(bigEndian: UInt16(clamping: collision.waterBoxes.count))

        for vertex in collision.vertices {
            data.append(bigEndian: vertex.x)
            data.append(bigEndian: vertex.y)
            data.append(bigEndian: vertex.z)
        }

        for polygon in collision.polygons {
            data.append(bigEndian: polygon.surfaceType)
            data.append(bigEndian: polygon.vertexA)
            data.append(bigEndian: polygon.vertexB)
            data.append(bigEndian: polygon.vertexC)
            data.append(bigEndian: polygon.normal.x)
            data.append(bigEndian: polygon.normal.y)
            data.append(bigEndian: polygon.normal.z)
            data.append(bigEndian: polygon.distance)
        }

        for surfaceType in collision.surfaceTypes {
            data.append(bigEndian: surfaceType.low)
            data.append(bigEndian: surfaceType.high)
        }

        for waterBox in collision.waterBoxes {
            data.append(bigEndian: waterBox.xMin)
            data.append(bigEndian: waterBox.ySurface)
            data.append(bigEndian: waterBox.zMin)
            data.append(bigEndian: waterBox.xLength)
            data.append(bigEndian: waterBox.zLength)
            data.append(bigEndian: waterBox.properties)
        }

        return data
    }

    static func decode(_ data: Data, path: String = "<memory>") throws -> CollisionSceneBinary {
        var offset = data.startIndex
        let minimumBounds = try Vector3s(
            x: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            y: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            z: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
        )
        let maximumBounds = try Vector3s(
            x: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            y: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
            z: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
        )
        let vertexCount = Int(try readInteger(from: data, offset: &offset, as: UInt16.self, path: path))
        let polygonCount = Int(try readInteger(from: data, offset: &offset, as: UInt16.self, path: path))
        let surfaceTypeCount = Int(try readInteger(from: data, offset: &offset, as: UInt16.self, path: path))
        let waterBoxCount = Int(try readInteger(from: data, offset: &offset, as: UInt16.self, path: path))

        var vertices: [Vector3s] = []
        vertices.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            vertices.append(
                try Vector3s(
                    x: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    y: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    z: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
                )
            )
        }

        var polygons: [CollisionPolygonBinary] = []
        polygons.reserveCapacity(polygonCount)
        for _ in 0..<polygonCount {
            polygons.append(
                try CollisionPolygonBinary(
                    surfaceType: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    vertexA: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    vertexB: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    vertexC: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    normal: Vector3s(
                        x: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                        y: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                        z: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
                    ),
                    distance: readInteger(from: data, offset: &offset, as: Int16.self, path: path)
                )
            )
        }

        var surfaceTypes: [CollisionSurfaceTypeBinary] = []
        surfaceTypes.reserveCapacity(surfaceTypeCount)
        for _ in 0..<surfaceTypeCount {
            surfaceTypes.append(
                try CollisionSurfaceTypeBinary(
                    low: readInteger(from: data, offset: &offset, as: UInt32.self, path: path),
                    high: readInteger(from: data, offset: &offset, as: UInt32.self, path: path)
                )
            )
        }

        var waterBoxes: [CollisionWaterBoxBinary] = []
        waterBoxes.reserveCapacity(waterBoxCount)
        for _ in 0..<waterBoxCount {
            waterBoxes.append(
                try CollisionWaterBoxBinary(
                    xMin: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    ySurface: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    zMin: readInteger(from: data, offset: &offset, as: Int16.self, path: path),
                    xLength: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    zLength: readInteger(from: data, offset: &offset, as: UInt16.self, path: path),
                    properties: readInteger(from: data, offset: &offset, as: UInt32.self, path: path)
                )
            )
        }

        guard offset == data.endIndex else {
            throw CollisionExtractorError.invalidBinarySize(path, data.count, offset)
        }

        for polygon in polygons {
            guard Int(polygon.vertexA) < vertices.count else {
                throw CollisionExtractorError.invalidReference(path, "vertexA", Int(polygon.vertexA), vertices.count)
            }
            guard Int(polygon.vertexB) < vertices.count else {
                throw CollisionExtractorError.invalidReference(path, "vertexB", Int(polygon.vertexB), vertices.count)
            }
            guard Int(polygon.vertexC) < vertices.count else {
                throw CollisionExtractorError.invalidReference(path, "vertexC", Int(polygon.vertexC), vertices.count)
            }
            guard Int(polygon.surfaceType) < surfaceTypes.count || surfaceTypes.isEmpty else {
                throw CollisionExtractorError.invalidReference(
                    path,
                    "surfaceType",
                    Int(polygon.surfaceType),
                    surfaceTypes.count
                )
            }
        }

        return CollisionSceneBinary(
            minimumBounds: minimumBounds,
            maximumBounds: maximumBounds,
            vertices: vertices,
            polygons: polygons,
            surfaceTypes: surfaceTypes,
            waterBoxes: waterBoxes
        )
    }
}

extension SceneManifestExtractor {
    public func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let scenes = try SceneExtractor.loadScenes(
            in: context.source,
            sceneName: context.sceneName,
            fileManager: fileManager
        )
        let sceneTableEntries = try Self.loadSceneTableEntries(from: context.output)
        let sceneTableBySegmentName = Dictionary(uniqueKeysWithValues: sceneTableEntries.map { ($0.segmentName, $0) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var extractedScenes = 0
        var skippedScenes = 0

        sceneLoop: for scene in scenes {
            guard let sceneTableEntry = Self.resolveSceneTableEntry(for: scene, sceneTableBySegmentName: sceneTableBySegmentName)
            else {
                guard context.sceneName == nil else {
                    throw SceneManifestExtractorError.missingSceneTableEntry(scene.name)
                }
                print("[\(name)] skipped scene manifest for \(scene.name): missing scene-table entry")
                skippedScenes += 1
                continue
            }

            let sceneDirectory = context.output
                .appendingPathComponent("Scenes", isDirectory: true)
                .appendingPathComponent(scene.name, isDirectory: true)
            let metadataDirectory = Self.metadataDirectoryPath(for: scene, outputRoot: context.output)
            let roomDirectoryRoot = sceneDirectory.appendingPathComponent("rooms", isDirectory: true)

            var roomManifests: [RoomManifest] = []
            roomManifests.reserveCapacity(scene.rooms.count)

            for (index, room) in scene.rooms.enumerated() {
                let roomDirectory = roomDirectoryRoot.appendingPathComponent(room.outputName, isDirectory: true)
                guard fileManager.fileExists(atPath: roomDirectory.path) else {
                    guard context.sceneName == nil else {
                        throw SceneManifestExtractorError.missingReferencedPath(roomDirectory.path)
                    }
                    print("[\(name)] skipped scene manifest for \(scene.name): missing room directory \(roomDirectory.path)")
                    skippedScenes += 1
                    continue sceneLoop
                }

                roomManifests.append(
                    RoomManifest(
                        id: index,
                        name: room.symbolName,
                        directory: try Self.relativePath(from: context.output, to: roomDirectory),
                        textureDirectories: Self.textureDirectories(
                            named: [room.sourceName, room.symbolName],
                            outputRoot: context.output,
                            fileManager: fileManager
                        )
                    )
                )
            }

            let metadataNames = ["actors.json", "environment.json", "paths.json", "exits.json"]
            for metadataName in metadataNames {
                let metadataURL = metadataDirectory.appendingPathComponent(metadataName)
                guard fileManager.fileExists(atPath: metadataURL.path) else {
                    guard context.sceneName == nil else {
                        throw SceneManifestExtractorError.missingReferencedPath(metadataURL.path)
                    }
                    print("[\(name)] skipped scene manifest for \(scene.name): missing metadata file \(metadataURL.path)")
                    skippedScenes += 1
                    continue sceneLoop
                }
            }

            let collisionURL = sceneDirectory.appendingPathComponent("collision.bin")
            let manifest = SceneManifest(
                id: sceneTableEntry.index,
                name: scene.name,
                title: sceneTableEntry.title,
                drawConfig: sceneTableEntry.drawConfig,
                rooms: roomManifests,
                collisionPath: fileManager.fileExists(atPath: collisionURL.path)
                    ? try Self.relativePath(from: context.output, to: collisionURL)
                    : nil,
                actorsPath: try Self.relativePath(
                    from: context.output,
                    to: metadataDirectory.appendingPathComponent("actors.json")
                ),
                environmentPath: try Self.relativePath(
                    from: context.output,
                    to: metadataDirectory.appendingPathComponent("environment.json")
                ),
                pathsPath: try Self.relativePath(
                    from: context.output,
                    to: metadataDirectory.appendingPathComponent("paths.json")
                ),
                exitsPath: try Self.relativePath(
                    from: context.output,
                    to: metadataDirectory.appendingPathComponent("exits.json")
                ),
                textureDirectories: Self.textureDirectories(
                    named: [scene.sceneSourceName, scene.sceneSymbolName],
                    outputRoot: context.output,
                    fileManager: fileManager
                )
            )

            let data = try encoder.encode(manifest)
            _ = try JSONDecoder().decode(SceneManifest.self, from: data)
            try fileManager.createDirectory(at: sceneDirectory, withIntermediateDirectories: true)
            try data.write(
                to: sceneDirectory.appendingPathComponent("SceneManifest.json"),
                options: .atomic
            )
            extractedScenes += 1
        }

        print("[\(name)] wrote \(extractedScenes) scene manifest(s)")
        if skippedScenes > 0 {
            print("[\(name)] skipped \(skippedScenes) scene(s) with incomplete extracted outputs")
        }
    }

    public func verify(using context: OOTVerificationContext) throws {
        let manifestFiles = try Self.sceneManifestFiles(in: context.content, fileManager: .default)

        for manifestFile in manifestFiles {
            let manifest: SceneManifest = try Self.readJSON(from: manifestFile)
            try Self.verify(manifest: manifest, contentRoot: context.content)
        }

        print("[\(name)] verified \(manifestFiles.count) scene manifest(s)")
    }
}

private extension SceneManifestExtractor {
    static func loadSceneTableEntries(from outputRoot: URL) throws -> [SceneTableEntry] {
        let tableURL = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("tables", isDirectory: true)
            .appendingPathComponent("scene-table.json")
        guard FileManager.default.fileExists(atPath: tableURL.path) else {
            throw SceneManifestExtractorError.missingSceneTable(tableURL.path)
        }
        return try readJSON(from: tableURL)
    }

    static func resolveSceneTableEntry(
        for scene: SceneExtractor.SceneDefinition,
        sceneTableBySegmentName: [String: SceneTableEntry]
    ) -> SceneTableEntry? {
        sceneTableBySegmentName[scene.sceneSourceName] ?? sceneTableBySegmentName[scene.sceneSymbolName]
    }

    static func metadataDirectoryPath(for scene: SceneExtractor.SceneDefinition, outputRoot: URL) -> URL {
        var directory = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)

        for component in scene.categoryPath.split(separator: "/") {
            directory.appendPathComponent(String(component), isDirectory: true)
        }
        directory.appendPathComponent(scene.name, isDirectory: true)
        return directory
    }

    static func textureDirectories(named candidates: [String], outputRoot: URL, fileManager: FileManager) -> [String] {
        var directories: [String] = []
        var seen: Set<String> = []

        for candidate in candidates where seen.insert(candidate).inserted {
            let directory = outputRoot
                .appendingPathComponent("Textures", isDirectory: true)
                .appendingPathComponent(candidate, isDirectory: true)
            guard fileManager.fileExists(atPath: directory.path) else {
                continue
            }
            if let relativePath = try? relativePath(from: outputRoot, to: directory) {
                directories.append(relativePath)
            }
        }

        return directories
    }

    static func relativePath(from root: URL, to target: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path

        if targetPath == rootPath {
            return ""
        }

        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(prefix) else {
            throw SceneManifestExtractorError.invalidReferencedPath(targetPath)
        }

        return String(targetPath.dropFirst(prefix.count))
    }

    static func sceneManifestFiles(in contentRoot: URL, fileManager: FileManager) throws -> [URL] {
        let scenesRoot = contentRoot.appendingPathComponent("Scenes", isDirectory: true)
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
            guard values.isRegularFile == true, fileURL.lastPathComponent == "SceneManifest.json" else {
                return nil
            }

            return fileURL
        }
        .sorted { $0.path < $1.path }
    }

    static func verify(manifest: SceneManifest, contentRoot: URL) throws {
        for room in manifest.rooms {
            let roomDirectory = try referencedURL(path: room.directory, contentRoot: contentRoot)
            guard FileManager.default.fileExists(atPath: roomDirectory.path) else {
                throw SceneManifestExtractorError.missingReferencedPath(roomDirectory.path)
            }

            let vertexURL = roomDirectory.appendingPathComponent("vtx.bin")
            let displayListURL = roomDirectory.appendingPathComponent("dl.json")
            guard FileManager.default.fileExists(atPath: vertexURL.path) else {
                throw SceneManifestExtractorError.missingReferencedPath(vertexURL.path)
            }
            guard FileManager.default.fileExists(atPath: displayListURL.path) else {
                throw SceneManifestExtractorError.missingReferencedPath(displayListURL.path)
            }

            _ = try VertexParser.decode(Data(contentsOf: vertexURL), path: vertexURL.path)
            _ = try JSONDecoder().decode([F3DEX2Command].self, from: Data(contentsOf: displayListURL))

            try verifyTextureDirectories(room.textureDirectories, contentRoot: contentRoot)
        }

        if let collisionPath = manifest.collisionPath {
            let collisionURL = try referencedURL(path: collisionPath, contentRoot: contentRoot)
            guard FileManager.default.fileExists(atPath: collisionURL.path) else {
                throw SceneManifestExtractorError.missingReferencedPath(collisionURL.path)
            }
            _ = try CollisionExtractor.decode(Data(contentsOf: collisionURL), path: collisionURL.path)
        }

        if let actorsPath = manifest.actorsPath {
            let actorsURL = try referencedURL(path: actorsPath, contentRoot: contentRoot)
            let _: SceneActorsFile = try readJSON(from: actorsURL)
        }
        if let environmentPath = manifest.environmentPath {
            let environmentURL = try referencedURL(path: environmentPath, contentRoot: contentRoot)
            let _: SceneEnvironmentFile = try readJSON(from: environmentURL)
        }
        if let pathsPath = manifest.pathsPath {
            let pathsURL = try referencedURL(path: pathsPath, contentRoot: contentRoot)
            let _: ScenePathsFile = try readJSON(from: pathsURL)
        }
        if let exitsPath = manifest.exitsPath {
            let exitsURL = try referencedURL(path: exitsPath, contentRoot: contentRoot)
            let _: SceneExitsFile = try readJSON(from: exitsURL)
        }

        try verifyTextureDirectories(manifest.textureDirectories, contentRoot: contentRoot)
    }

    static func verifyTextureDirectories(_ paths: [String], contentRoot: URL) throws {
        for path in paths {
            let directoryURL = try referencedURL(path: path, contentRoot: contentRoot)
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw SceneManifestExtractorError.missingReferencedPath(directoryURL.path)
            }
        }
    }

    static func referencedURL(path: String, contentRoot: URL) throws -> URL {
        let url = contentRoot.appendingPathComponent(path, isDirectory: false)
        _ = try relativePath(from: contentRoot, to: url)
        return url
    }

    static func readJSON<T: Decodable>(from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SceneManifestExtractorError.missingReferencedPath(url.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SceneManifestExtractorError.unreadableFile(url.path, error)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SceneManifestExtractorError.invalidJSON(url.path, error)
        }
    }
}

private enum SceneManifestExtractorError: LocalizedError {
    case missingSceneTable(String)
    case missingSceneTableEntry(String)
    case missingReferencedPath(String)
    case invalidReferencedPath(String)
    case unreadableFile(String, Error)
    case invalidJSON(String, Error)

    var errorDescription: String? {
        switch self {
        case .missingSceneTable(let path):
            return "Missing scene-table manifest at \(path)"
        case .missingSceneTableEntry(let sceneName):
            return "Could not resolve a scene-table entry for \(sceneName)"
        case .missingReferencedPath(let path):
            return "Missing referenced output at \(path)"
        case .invalidReferencedPath(let path):
            return "Referenced path escapes the content root: \(path)"
        case .unreadableFile(let path, let error):
            return "Failed to read \(path): \(error.localizedDescription)"
        case .invalidJSON(let path, let error):
            return "Failed to decode JSON at \(path): \(error.localizedDescription)"
        }
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

            let normalizedXMLRoot = xmlRoot.resolvingSymlinksInPath().standardizedFileURL
            let normalizedParent = fileURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            let relativeCategoryPath = normalizedParent
                .pathComponents
                .dropFirst(normalizedXMLRoot.pathComponents.count)
                .joined(separator: "/")

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

    static func makeVertexAddressMap(vertexArrays: [ParsedVertexArray]) -> [UInt32: UInt32] {
        let stride = MemoryLayout<N64Vertex>.size
        var nextOffset = 0
        var addressMap: [UInt32: UInt32] = [:]

        for array in vertexArrays {
            let baseOffset = nextOffset
            addressMap[DisplayListParser.stableID(for: array.name)] = segmentedRoomVertexAddress(offset: baseOffset)

            for index in array.vertices.indices {
                let indexedName = "\(array.name)[\(index)]"
                let indexedOffset = baseOffset + (index * stride)
                addressMap[DisplayListParser.stableID(for: indexedName)] = segmentedRoomVertexAddress(offset: indexedOffset)
            }

            nextOffset += array.vertices.count * stride
        }

        return addressMap
    }

    static func rewriteVertexAddresses(
        in commands: [F3DEX2Command],
        vertexAddressMap: [UInt32: UInt32]
    ) -> [F3DEX2Command] {
        commands.map { command in
            guard case .spVertex(let vertexCommand) = command else {
                return command
            }

            guard let rewrittenAddress = vertexAddressMap[vertexCommand.address] else {
                return command
            }

            return .spVertex(
                VertexCommand(
                    address: rewrittenAddress,
                    count: vertexCommand.count,
                    destinationIndex: vertexCommand.destinationIndex
                )
            )
        }
    }

    static func segmentedRoomVertexAddress(offset: Int) -> UInt32 {
        (UInt32(0x03) << 24) | UInt32(offset)
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
        let trimmed = trimExpression(expression)
        if
            let match = firstMatch(
                of: try! NSRegularExpression(pattern: #"COLPOLY_SNORMAL\(\s*([^)]+?)\s*\)"#),
                in: trimmed
            )
        {
            let normal = try parseFloatingPointLiteral(substring(in: trimmed, range: match.range(at: 1)))
            let scaled = (normal * 32767.0).rounded(.towardZero)
            guard scaled >= Double(Int16.min), scaled <= Double(Int16.max) else {
                throw SceneExtractorError.integerOutOfRange(expression, Int64(scaled))
            }
            return Int16(scaled)
        }

        return try parseSigned16(parseIntegerExpression(expression), field: expression)
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

    static func parseFloatingPointLiteral(_ literal: String) throws -> Double {
        var trimmed = trimExpression(literal)
        if trimmed.hasSuffix("f") || trimmed.hasSuffix("F") {
            trimmed.removeLast()
        }
        guard trimmed.isEmpty == false, let value = Double(trimmed) else {
            throw SceneExtractorError.invalidIntegerLiteral(literal)
        }
        return value
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

    static func stripBlockComments(from expression: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"/\*.*?\*/"#, options: [.dotMatchesLineSeparators])
        let range = NSRange(expression.startIndex..<expression.endIndex, in: expression)
        return regex.stringByReplacingMatches(in: expression, range: range, withTemplate: " ")
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

private extension CollisionExtractor {
    struct CollisionHeaderDefinition {
        let minimumBounds: Vector3s
        let maximumBounds: Vector3s
        let vertexCount: Int
        let vertexArrayName: String
        let polygonCount: Int
        let polygonArrayName: String
        let surfaceTypeArrayName: String?
        let waterBoxCount: Int
        let waterBoxArrayName: String?
    }

    static func parseCollision(sceneName: String, source: String) throws -> CollisionSceneBinary? {
        let commands = try SceneExtractor.sceneCommands(sceneName: sceneName, in: source)
        guard let invocation = commands.first(where: { $0.name == "SCENE_CMD_COL_HEADER" }) else {
            return nil
        }
        try invocation.requireCount(1)

        let headerName = sanitizeReference(invocation.arguments[0])
        let header = try collisionHeader(named: headerName, in: source)
        let vertices = try parseVertices(named: header.vertexArrayName, in: source, expectedCount: header.vertexCount)
        let polygons = try parsePolygons(named: header.polygonArrayName, in: source, expectedCount: header.polygonCount)
        let surfaceTypes = try parseSurfaceTypes(named: header.surfaceTypeArrayName, in: source)
        let waterBoxes = try parseWaterBoxes(
            named: header.waterBoxArrayName,
            in: source,
            expectedCount: header.waterBoxCount
        )

        return CollisionSceneBinary(
            minimumBounds: header.minimumBounds,
            maximumBounds: header.maximumBounds,
            vertices: vertices,
            polygons: polygons,
            surfaceTypes: surfaceTypes,
            waterBoxes: waterBoxes
        )
    }

    static func parseVertices(named name: String, in source: String, expectedCount: Int) throws -> [Vector3s] {
        let array = try SceneExtractor.array(named: name, type: "Vec3s", in: source)
        let vertices = try SceneExtractor.topLevelBraceEntries(in: array.body).map(SceneExtractor.parseVector3s)
        try expectCount(vertices.count, expected: expectedCount, field: "vertices", name: name)
        return vertices
    }

    static func parsePolygons(named name: String, in source: String, expectedCount: Int) throws -> [CollisionPolygonBinary] {
        let array = try SceneExtractor.array(named: name, type: "CollisionPoly", in: source)
        let polygons = try SceneExtractor.topLevelBraceEntries(in: array.body).map(parsePolygon)
        try expectCount(polygons.count, expected: expectedCount, field: "polygons", name: name)
        return polygons
    }

    static func parseSurfaceTypes(named name: String?, in source: String) throws -> [CollisionSurfaceTypeBinary] {
        guard let name else {
            return []
        }

        let array = try SceneExtractor.array(named: name, type: "SurfaceType", in: source)
        let entries = try SceneExtractor.topLevelBraceEntries(in: array.body)
        if entries.isEmpty {
            let rawValues = SceneExtractor.splitTopLevel(array.body).filter { SceneExtractor.trimExpression($0).isEmpty == false }
            guard rawValues.count.isMultiple(of: 2) else {
                throw CollisionExtractorError.invalidEntry("SurfaceType", array.body)
            }

            return try stride(from: 0, to: rawValues.count, by: 2).map { index in
                try CollisionSurfaceTypeBinary(
                    low: parseUnsigned32Expression(rawValues[index]),
                    high: parseUnsigned32Expression(rawValues[index + 1])
                )
            }
        }

        return try entries.map(parseSurfaceType)
    }

    static func parseWaterBoxes(named name: String?, in source: String, expectedCount: Int) throws -> [CollisionWaterBoxBinary] {
        guard let name else {
            guard expectedCount == 0 else {
                throw CollisionExtractorError.countMismatch(name: "WaterBox", expected: expectedCount, actual: 0)
            }
            return []
        }

        let array = try SceneExtractor.array(named: name, type: "WaterBox", in: source)
        let waterBoxes = try SceneExtractor.topLevelBraceEntries(in: array.body).map(parseWaterBox)
        try expectCount(waterBoxes.count, expected: expectedCount, field: "waterBoxes", name: name)
        return waterBoxes
    }

    static func collisionHeader(named name: String, in source: String) throws -> CollisionHeaderDefinition {
        let body = try structBody(named: name, type: "CollisionHeader", in: source)
        let fields = SceneExtractor.splitTopLevel(body)
        guard fields.count == 9 || fields.count == 10 else {
            throw CollisionExtractorError.invalidEntry("CollisionHeader", body)
        }

        let minimumBounds = try SceneExtractor.parseVector3s(fields[0])
        let maximumBounds = try SceneExtractor.parseVector3s(fields[1])
        let vertexArrayName = sanitizeReference(fields[3])
        let polygonArrayName = sanitizeReference(fields[5])
        let surfaceTypeIndex = fields.count == 10 ? 6 : 6
        let waterBoxCountIndex = fields.count == 10 ? 8 : 7
        let waterBoxArrayIndex = fields.count == 10 ? 9 : 8
        let waterBoxArrayName = optionalReference(fields[waterBoxArrayIndex])

        return CollisionHeaderDefinition(
            minimumBounds: minimumBounds,
            maximumBounds: maximumBounds,
            vertexCount: try parseCount(
                fields[2],
                field: "numVertices",
                fallbackArrayName: vertexArrayName,
                arrayType: "Vec3s",
                source: source
            ),
            vertexArrayName: vertexArrayName,
            polygonCount: try parseCount(
                fields[4],
                field: "numPolygons",
                fallbackArrayName: polygonArrayName,
                arrayType: "CollisionPoly",
                source: source
            ),
            polygonArrayName: polygonArrayName,
            surfaceTypeArrayName: optionalReference(fields[surfaceTypeIndex]),
            waterBoxCount: try parseCount(
                fields[waterBoxCountIndex],
                field: "numWaterBoxes",
                fallbackArrayName: waterBoxArrayName,
                arrayType: "WaterBox",
                source: source
            ),
            waterBoxArrayName: waterBoxArrayName
        )
    }

    static func parsePolygon(_ entry: String) throws -> CollisionPolygonBinary {
        let fields = SceneExtractor.splitTopLevel(entry)
        switch fields.count {
        case 4:
            let vertices = try parsePackedVertexTriplet(fields[1])
            return try CollisionPolygonBinary(
                surfaceType: parseUnsigned16Expression(fields[0]),
                vertexA: vertices.0,
                vertexB: vertices.1,
                vertexC: vertices.2,
                normal: SceneExtractor.parseVector3s(fields[2]),
                distance: SceneExtractor.parseSigned16Expression(fields[3])
            )
        case 6:
            return try CollisionPolygonBinary(
                surfaceType: parseUnsigned16Expression(fields[0]),
                vertexA: parsePackedVertexIndex(fields[1]),
                vertexB: parsePackedVertexIndex(fields[2]),
                vertexC: parsePackedVertexIndex(fields[3]),
                normal: SceneExtractor.parseVector3s(fields[4]),
                distance: SceneExtractor.parseSigned16Expression(fields[5])
            )
        case 8:
            return try CollisionPolygonBinary(
                surfaceType: parseUnsigned16Expression(fields[0]),
                vertexA: parsePackedVertexIndex(fields[1]),
                vertexB: parsePackedVertexIndex(fields[2]),
                vertexC: parsePackedVertexIndex(fields[3]),
                normal: Vector3s(
                    x: SceneExtractor.parseSigned16Expression(fields[4]),
                    y: SceneExtractor.parseSigned16Expression(fields[5]),
                    z: SceneExtractor.parseSigned16Expression(fields[6])
                ),
                distance: SceneExtractor.parseSigned16Expression(fields[7])
            )
        default:
            throw CollisionExtractorError.invalidEntry("CollisionPoly", entry)
        }
    }

    static func parseSurfaceType(_ entry: String) throws -> CollisionSurfaceTypeBinary {
        var fields = SceneExtractor.splitTopLevel(entry)
        if fields.count != 2, let nestedEntries = try? SceneExtractor.topLevelBraceEntries(in: entry), nestedEntries.count == 1 {
            fields = SceneExtractor.splitTopLevel(nestedEntries[0])
        }
        guard fields.count == 2 else {
            throw CollisionExtractorError.invalidEntry("SurfaceType", entry)
        }
        return try CollisionSurfaceTypeBinary(
            low: parseSurfaceTypeWord(fields[0]),
            high: parseSurfaceTypeWord(fields[1])
        )
    }

    static func parseWaterBox(_ entry: String) throws -> CollisionWaterBoxBinary {
        let fields = SceneExtractor.splitTopLevel(entry)
        switch fields.count {
        case 6:
            return try CollisionWaterBoxBinary(
                xMin: SceneExtractor.parseSigned16Expression(fields[0]),
                ySurface: SceneExtractor.parseSigned16Expression(fields[1]),
                zMin: SceneExtractor.parseSigned16Expression(fields[2]),
                xLength: parseUnsigned16Expression(fields[3]),
                zLength: parseUnsigned16Expression(fields[4]),
                properties: parseUnsigned32Expression(fields[5])
            )
        case 4:
            let minimum = try SceneExtractor.parseVector3s(fields[0])
            return try CollisionWaterBoxBinary(
                xMin: minimum.x,
                ySurface: minimum.y,
                zMin: minimum.z,
                xLength: parseUnsigned16Expression(fields[1]),
                zLength: parseUnsigned16Expression(fields[2]),
                properties: parseUnsigned32Expression(fields[3])
            )
        default:
            throw CollisionExtractorError.invalidEntry("WaterBox", entry)
        }
    }

    static func collisionBinaryFiles(in contentRoot: URL, fileManager: FileManager) throws -> [URL] {
        let scenesRoot = contentRoot.appendingPathComponent("Scenes", isDirectory: true)
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
            guard values.isRegularFile == true, fileURL.lastPathComponent == "collision.bin" else {
                return nil
            }

            return fileURL
        }
        .sorted { $0.path < $1.path }
    }

    static func structBody(named name: String, type: String, in source: String) throws -> String {
        let sanitized = SceneExtractor.stripLineComments(from: source)
        let pattern =
            #"(?:^|\s)(?:static\s+)?\#(NSRegularExpression.escapedPattern(for: type))\s+\#(NSRegularExpression.escapedPattern(for: name))\s*=\s*\{"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        guard let match = regex.firstMatch(
            in: sanitized,
            range: NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        ) else {
            throw CollisionExtractorError.missingStruct(type: type, name: name)
        }

        let braceLocation = match.range.location + match.range.length - 1
        let bodyRange = try SceneExtractor.matchingBraceRange(in: sanitized, openingBraceLocation: braceLocation)
        return SceneExtractor.substring(in: sanitized, range: bodyRange)
    }

    static func parseCount(
        _ expression: String,
        field: String,
        fallbackArrayName: String?,
        arrayType: String,
        source: String
    ) throws -> Int {
        let trimmed = SceneExtractor.trimExpression(expression)
        if let arrayName = parseArrayCountReference(from: trimmed) {
            let resolvedName = arrayName.isEmpty ? fallbackArrayName : arrayName
            guard let resolvedName else {
                throw CollisionExtractorError.invalidEntry(field, expression)
            }
            let array = try SceneExtractor.array(named: resolvedName, type: arrayType, in: source)
            let entries = try SceneExtractor.topLevelBraceEntries(in: array.body)
            if entries.isEmpty {
                return SceneExtractor.splitTopLevel(array.body)
                    .filter { SceneExtractor.trimExpression($0).isEmpty == false }
                    .count
            }
            return entries.count
        }

        let value = try SceneExtractor.parseIntegerExpression(expression)
        guard value >= 0, value <= Int64(UInt16.max) else {
            throw CollisionExtractorError.integerOutOfRange(field: field, value: value)
        }
        return Int(value)
    }

    static func parseArrayCountReference(from expression: String) -> String? {
        guard
            let match = SceneExtractor.firstMatch(
                of: try! NSRegularExpression(pattern: #"ARRAY_COUNT(?:U)?\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#),
                in: expression
            )
        else {
            return nil
        }

        return SceneExtractor.substring(in: expression, range: match.range(at: 1))
    }

    static func parseUnsigned16Expression(_ expression: String) throws -> UInt16 {
        let value = try SceneExtractor.parseIntegerExpression(expression)
        guard 0...Int64(UInt16.max) ~= value else {
            throw CollisionExtractorError.integerOutOfRange(field: expression, value: value)
        }
        return UInt16(value)
    }

    static func parseUnsigned32Expression(_ expression: String) throws -> UInt32 {
        let trimmed = SceneExtractor.trimExpression(SceneExtractor.stripBlockComments(from: expression))
        if
            let match = SceneExtractor.firstMatch(
                of: try! NSRegularExpression(pattern: #"(?s)WATERBOX_PROPERTIES\(\s*(.*)\s*\)"#),
                in: trimmed
            )
        {
            let arguments = SceneExtractor.splitTopLevel(
                SceneExtractor.substring(in: trimmed, range: match.range(at: 1))
            )
            guard arguments.count == 4 else {
                throw CollisionExtractorError.invalidEntry("WaterBox", expression)
            }

            let bgCamIndex = try parseSurfaceTypeScalar(arguments[0])
            let lightIndex = try parseSurfaceTypeScalar(arguments[1])
            let room = try parseSurfaceTypeScalar(arguments[2])
            let setFlag19 = try parseSurfaceTypeScalar(arguments[3])

            let words: [UInt32] = [
                UInt32((bgCamIndex & 0xFF) << 0),
                UInt32((lightIndex & 0x1F) << 8),
                UInt32((room & 0x3F) << 13),
                UInt32((setFlag19 & 1) << 19),
            ]
            return words.reduce(0, |)
        }

        let value = try SceneExtractor.parseIntegerExpression(trimmed)
        guard 0...Int64(UInt32.max) ~= value else {
            throw CollisionExtractorError.integerOutOfRange(field: expression, value: value)
        }
        return UInt32(value)
    }

    static func parseSurfaceTypeWord(_ expression: String) throws -> UInt32 {
        let trimmed = SceneExtractor.trimExpression(expression)

        if
            let match = SceneExtractor.firstMatch(
                of: try! NSRegularExpression(pattern: #"(?s)SURFACETYPE([01])\(\s*(.*)\s*\)"#),
                in: trimmed
            )
        {
            let variant = SceneExtractor.substring(in: trimmed, range: match.range(at: 1))
            let arguments = SceneExtractor.splitTopLevel(
                SceneExtractor.substring(in: trimmed, range: match.range(at: 2))
            )

            switch variant {
            case "0":
                guard arguments.count == 8 else {
                    throw CollisionExtractorError.invalidEntry("SurfaceType", expression)
                }
                let bgCamIndex = try parseSurfaceTypeScalar(arguments[0])
                let exitIndex = try parseSurfaceTypeScalar(arguments[1])
                let floorType = try parseSurfaceTypeScalar(arguments[2])
                let unk18 = try parseSurfaceTypeScalar(arguments[3])
                let wallType = try parseSurfaceTypeScalar(arguments[4])
                let floorProperty = try parseSurfaceTypeScalar(arguments[5])
                let isSoft = try parseSurfaceTypeScalar(arguments[6])
                let isHorseBlocked = try parseSurfaceTypeScalar(arguments[7])

                let words: [UInt32] = [
                    UInt32((bgCamIndex & 0xFF) << 0),
                    UInt32((exitIndex & 0x1F) << 8),
                    UInt32((floorType & 0x1F) << 13),
                    UInt32((unk18 & 0x07) << 18),
                    UInt32((wallType & 0x1F) << 21),
                    UInt32((floorProperty & 0x0F) << 26),
                    UInt32((isSoft & 1) << 30),
                    UInt32((isHorseBlocked & 1) << 31),
                ]
                return words.reduce(0, |)
            case "1":
                guard arguments.count == 8 else {
                    throw CollisionExtractorError.invalidEntry("SurfaceType", expression)
                }
                let material = try parseSurfaceTypeScalar(arguments[0])
                let floorEffect = try parseSurfaceTypeScalar(arguments[1])
                let lightSetting = try parseSurfaceTypeScalar(arguments[2])
                let echo = try parseSurfaceTypeScalar(arguments[3])
                let canHookshot = try parseSurfaceTypeScalar(arguments[4])
                let conveyorSpeed = try parseSurfaceTypeScalar(arguments[5])
                let conveyorDirection = try parseSurfaceTypeScalar(arguments[6])
                let unk27 = try parseSurfaceTypeScalar(arguments[7])

                let words: [UInt32] = [
                    UInt32((material & 0x0F) << 0),
                    UInt32((floorEffect & 0x03) << 4),
                    UInt32((lightSetting & 0x1F) << 6),
                    UInt32((echo & 0x3F) << 11),
                    UInt32((canHookshot & 1) << 17),
                    UInt32((conveyorSpeed & 0x07) << 18),
                    UInt32((conveyorDirection & 0x3F) << 21),
                    UInt32((unk27 & 1) << 27),
                ]
                return words.reduce(0, |)
            default:
                break
            }
        }

        return try parseUnsigned32Expression(trimmed)
    }

    static func parsePackedVertexIndex(_ expression: String) throws -> UInt16 {
        let trimmed = SceneExtractor.trimExpression(expression)
        if
            let match = SceneExtractor.firstMatch(
                of: try! NSRegularExpression(
                    pattern: #"COLPOLY_VTX\(\s*([^,]+?)\s*,\s*([^)]+?)\s*\)"#
                ),
                in: trimmed
            )
        {
            let vertexID = try SceneExtractor.parseIntegerExpression(
                SceneExtractor.substring(in: trimmed, range: match.range(at: 1))
            )
            let flags = try parseCollisionVertexFlags(
                SceneExtractor.substring(in: trimmed, range: match.range(at: 2))
            )

            guard 0...0x1FFF ~= vertexID, 0...7 ~= flags else {
                throw CollisionExtractorError.invalidEntry("CollisionPoly vertex", expression)
            }

            let packed = (((UInt16(flags) & 7) << 13) | (UInt16(vertexID) & 0x1FFF))
            return packed & 0x1FFF
        }

        return try parseUnsigned16Expression(expression) & 0x1FFF
    }

    static func parsePackedVertexTriplet(_ expression: String) throws -> (UInt16, UInt16, UInt16) {
        let trimmed = SceneExtractor.trimExpression(expression)
        let contents: String
        if trimmed.first == "{", trimmed.last == "}" {
            contents = String(trimmed.dropFirst().dropLast())
        } else {
            contents = trimmed
        }

        let values = SceneExtractor.splitTopLevel(contents)
        guard values.count == 3 else {
            throw CollisionExtractorError.invalidEntry("CollisionPoly vertices", expression)
        }

        return try (
            parsePackedVertexIndex(values[0]),
            parsePackedVertexIndex(values[1]),
            parsePackedVertexIndex(values[2])
        )
    }

    static func parseCollisionVertexFlags(_ expression: String) throws -> Int64 {
        let trimmed = SceneExtractor.trimExpression(SceneExtractor.stripBlockComments(from: expression))
        if trimmed.contains("|") {
            return try SceneExtractor.splitTopLevel(trimmed.replacingOccurrences(of: "|", with: ","))
                .reduce(0) { partial, component in
                    partial | (try parseCollisionVertexFlags(component))
                }
        }

        switch trimmed {
        case "0", "COLPOLY_IGNORE_NONE":
            return 0
        case "COLPOLY_IGNORE_CAMERA", "COLPOLY_IS_FLOOR_CONVEYOR":
            return 1
        case "COLPOLY_IGNORE_ENTITY":
            return 2
        case "COLPOLY_IGNORE_PROJECTILES":
            return 4
        default:
            return try SceneExtractor.parseIntegerExpression(trimmed)
        }
    }

    static func parseSurfaceTypeScalar(_ expression: String) throws -> Int64 {
        let trimmed = SceneExtractor.trimExpression(SceneExtractor.stripBlockComments(from: expression))

        if trimmed.contains("|") {
            return try SceneExtractor.splitTopLevel(trimmed.replacingOccurrences(of: "|", with: ","))
                .reduce(0) { partial, component in
                    partial | (try parseSurfaceTypeScalar(component))
                }
        }

        if let value = try? Int64(SceneExtractor.parseBoolExpression(trimmed) ? 1 : 0) {
            return value
        }

        if
            let match = SceneExtractor.firstMatch(
                of: try! NSRegularExpression(pattern: #"CONVEYOR_DIRECTION_FROM_BINANG\(\s*([^)]+?)\s*\)"#),
                in: trimmed
            )
        {
            let raw = try SceneExtractor.parseIntegerExpression(
                SceneExtractor.substring(in: trimmed, range: match.range(at: 1))
            )
            return raw / (0x10000 / 64)
        }

        let mappedValues: [String: Int64] = [
            "CONVEYOR_SPEED_DISABLED": 0,
            "CONVEYOR_SPEED_SLOW": 1,
            "CONVEYOR_SPEED_MEDIUM": 2,
            "CONVEYOR_SPEED_FAST": 3,
            "SURFACE_MATERIAL_DIRT": 0,
            "SURFACE_MATERIAL_SAND": 1,
            "SURFACE_MATERIAL_STONE": 2,
            "SURFACE_MATERIAL_JABU": 3,
            "SURFACE_MATERIAL_WATER_SHALLOW": 4,
            "SURFACE_MATERIAL_WATER_DEEP": 5,
            "SURFACE_MATERIAL_TALL_GRASS": 6,
            "SURFACE_MATERIAL_LAVA": 7,
            "SURFACE_MATERIAL_GRASS": 8,
            "SURFACE_MATERIAL_BRIDGE": 9,
            "SURFACE_MATERIAL_WOOD": 10,
            "SURFACE_MATERIAL_DIRT_SOFT": 11,
            "SURFACE_MATERIAL_ICE": 12,
            "SURFACE_MATERIAL_CARPET": 13,
        ]
        if let mapped = mappedValues[trimmed] {
            return mapped
        }

        if
            let match = SceneExtractor.firstMatch(
                of: try! NSRegularExpression(
                    pattern: #"^(?:FLOOR_TYPE|WALL_TYPE|FLOOR_EFFECT|FLOOR_PROPERTY)_([0-9]+)$"#
                ),
                in: trimmed
            )
        {
            return try SceneExtractor.parseIntegerExpression(
                SceneExtractor.substring(in: trimmed, range: match.range(at: 1))
            )
        }

        return try SceneExtractor.parseIntegerExpression(trimmed)
    }

    static func sanitizeReference(_ expression: String) -> String {
        SceneExtractor.trimExpression(expression)
            .trimmingPrefix("&")
            .trimmingPrefix("*")
    }

    static func optionalReference(_ expression: String) -> String? {
        let trimmed = sanitizeReference(expression)
        guard trimmed.isEmpty == false, trimmed != "NULL", trimmed != "0" else {
            return nil
        }
        return trimmed
    }

    static func expectCount(_ actual: Int, expected: Int, field: String, name: String) throws {
        guard actual == expected else {
            throw CollisionExtractorError.countMismatch(name: "\(field) \(name)", expected: expected, actual: actual)
        }
    }

    static func readInteger<T: FixedWidthInteger>(
        from data: Data,
        offset: inout Data.Index,
        as type: T.Type,
        path: String
    ) throws -> T {
        let end = offset + MemoryLayout<T>.size
        guard end <= data.endIndex else {
            throw CollisionExtractorError.invalidBinarySize(path, data.count, offset)
        }

        var value: T = 0
        withUnsafeMutableBytes(of: &value) { destination in
            _ = data[offset..<end].copyBytes(to: destination)
        }
        offset = end
        return T(bigEndian: value)
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

private enum CollisionExtractorError: LocalizedError {
    case countMismatch(name: String, expected: Int, actual: Int)
    case integerOutOfRange(field: String, value: Int64)
    case invalidBinarySize(String, Int, Int)
    case invalidEntry(String, String)
    case invalidReference(String, String, Int, Int)
    case missingStruct(type: String, name: String)

    var errorDescription: String? {
        switch self {
        case .countMismatch(let name, let expected, let actual):
            return "Expected \(expected) entries for \(name), found \(actual)."
        case .integerOutOfRange(let field, let value):
            return "Value \(value) is out of range for \(field)."
        case .invalidBinarySize(let path, let actualSize, let consumedBytes):
            return "Collision binary '\(path)' has invalid size \(actualSize) bytes after consuming \(consumedBytes) bytes."
        case .invalidEntry(let type, let entry):
            return "Unable to parse \(type) entry: \(entry)"
        case .invalidReference(let path, let field, let index, let count):
            return "Collision binary '\(path)' has \(field) index \(index) outside \(count) available entries."
        case .missingStruct(let type, let name):
            return "Missing \(type) struct \(name)."
        }
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(bigEndian value: T) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { buffer in
            append(contentsOf: buffer)
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

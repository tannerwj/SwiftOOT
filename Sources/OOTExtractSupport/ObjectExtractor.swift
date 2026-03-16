import Foundation
import OOTDataModel

extension ObjectExtractor {
    public func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let selectedObjectNames =
            try context.sceneNames.map { try SceneSelection.requiredObjectNames(for: $0, outputRoot: context.output, fileManager: fileManager) }
        let objects = try Self.loadObjects(in: context.source, fileManager: fileManager)
            .filter { selectedObjectNames?.contains($0.name) ?? true }
        let vertexParser = VertexParser()
        let displayListParser = DisplayListParser()
        var extractedObjects = 0
        var skippedObjects = 0

        for object in objects {
            let sourceFiles = try Self.sourceFiles(for: object, sourceRoot: context.source, fileManager: fileManager)
            guard sourceFiles.isEmpty == false else {
                print("[\(name)] skipped object \(object.name): no candidate source files")
                skippedObjects += 1
                continue
            }

            let index = try Self.buildSourceIndex(
                from: sourceFiles,
                sourceRoot: context.source,
                vertexParser: vertexParser,
                displayListParser: displayListParser
            )

            let objectDirectory = context.output
                .appendingPathComponent("Objects", isDirectory: true)
                .appendingPathComponent(object.name, isDirectory: true)
            let meshesDirectory = objectDirectory.appendingPathComponent("meshes", isDirectory: true)
            let animationsDirectory = objectDirectory.appendingPathComponent("animations", isDirectory: true)
            let texturesDirectory = objectDirectory.appendingPathComponent("textures", isDirectory: true)

            try fileManager.createDirectory(at: objectDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: meshesDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: animationsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: texturesDirectory, withIntermediateDirectories: true)

            let meshAssets = try Self.emitMeshes(
                named: object.displayListNames,
                index: index,
                meshesDirectory: meshesDirectory
            )
            let availableDisplayLists = Set(meshAssets.map(\.name))

            let skeletons = try Self.emitSkeletons(
                named: object.skeletonNames,
                index: index,
                availableDisplayLists: availableDisplayLists
            )
            if skeletons.isEmpty == false {
                try Self.writeJSON(
                    ObjectSkeletonFile(skeletons: skeletons),
                    to: objectDirectory.appendingPathComponent("skeleton.json")
                )
            }

            let animationReferences = try Self.emitAnimations(
                object: object,
                index: index,
                animationsDirectory: animationsDirectory
            )

            let textures = try Self.copyTextures(
                for: object,
                from: context.output,
                to: texturesDirectory,
                fileManager: fileManager
            )

            guard skeletons.isEmpty == false || animationReferences.isEmpty == false || meshAssets.isEmpty == false || textures.isEmpty == false else {
                print("[\(name)] skipped object \(object.name): no extractable assets found")
                skippedObjects += 1
                continue
            }

            try Self.writeJSON(
                ObjectManifest(
                    name: object.name,
                    skeletonPath: skeletons.isEmpty ? nil : "skeleton.json",
                    animations: animationReferences,
                    meshes: meshAssets,
                    textures: textures
                ),
                to: objectDirectory.appendingPathComponent("object_manifest.json")
            )
            extractedObjects += 1
        }

        print("[\(name)] extracted \(extractedObjects) object bundle(s)")
        if skippedObjects > 0 {
            print("[\(name)] skipped \(skippedObjects) object(s) with missing source data")
        }
    }

    public func verify(using context: OOTVerificationContext) throws {
        let fileManager = FileManager.default
        let objectsRoot = context.content.appendingPathComponent("Objects", isDirectory: true)
        guard fileManager.fileExists(atPath: objectsRoot.path) else {
            print("[\(name)] verified 0 object bundle(s)")
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: objectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[\(name)] verified 0 object bundle(s)")
            return
        }

        var verifiedObjects = 0
        for case let directory as URL in enumerator {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                continue
            }

            let manifestURL = directory.appendingPathComponent("object_manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                continue
            }

            let manifest = try JSONDecoder().decode(ObjectManifest.self, from: Data(contentsOf: manifestURL))
            if let skeletonPath = manifest.skeletonPath {
                let _: ObjectSkeletonFile = try Self.readJSON(
                    from: directory.appendingPathComponent(skeletonPath)
                )
            }

            for animation in manifest.animations {
                let _: ObjectAnimationData = try Self.readJSON(
                    from: directory.appendingPathComponent(animation.path)
                )
            }

            for mesh in manifest.meshes {
                let displayListURL = directory.appendingPathComponent(mesh.displayListPath)
                let _: [F3DEX2Command] = try Self.readJSON(from: displayListURL)

                for vertexPath in mesh.vertexPaths {
                    let vertexURL = directory.appendingPathComponent(vertexPath)
                    _ = try VertexParser.decode(Data(contentsOf: vertexURL), path: vertexURL.path)
                }
            }

            for texture in manifest.textures {
                let binaryURL = directory.appendingPathComponent(texture.path)
                let metadataURL = binaryURL.deletingPathExtension().appendingPathExtension("json")
                guard fileManager.fileExists(atPath: binaryURL.path) else {
                    throw ObjectExtractorError.missingOutput(binaryURL.path)
                }
                let _: TextureAssetMetadata = try Self.readJSON(from: metadataURL)
            }

            verifiedObjects += 1
        }

        print("[\(name)] verified \(verifiedObjects) object bundle(s)")
    }
}

private extension ObjectExtractor {
    struct ObjectDefinition: Equatable {
        let name: String
        let xmlURL: URL
        let externalAssetDirectories: [String]
        let skeletonNames: [String]
        let displayListNames: [String]
        let animationNames: [String]
        let playerAnimationNames: [String]
        let textureDefinitions: [ObjectTextureDefinition]
    }

    struct ObjectTextureDefinition: Equatable {
        let sourceName: String
        let name: String
        let format: TextureFormat
        let width: Int
        let height: Int
    }

    struct SourceIndex {
        var vertexArrays: [String: ParsedVertexArray] = [:]
        var displayLists: [String: ParsedDisplayList] = [:]
        var limbs: [String: ParsedLimb] = [:]
        var limbTables: [String: [String]] = [:]
        var skeletons: [String: ParsedSkeletonHeader] = [:]
        var frameData: [String: [Int16]] = [:]
        var jointIndices: [String: [AnimationJointIndex]] = [:]
        var standardAnimations: [String: ParsedAnimationHeader] = [:]
        var playerAnimations: [String: ParsedPlayerAnimationHeader] = [:]
        var playerFrameData: [String: [Int16]] = [:]
    }

    struct ParsedLimb: Equatable {
        let translation: Vector3s
        let childIndex: Int?
        let siblingIndex: Int?
        let displayListName: String?
        let lowDetailDisplayListName: String?
    }

    struct ParsedSkeletonHeader: Equatable {
        let type: SkeletonType
        let limbTableName: String
        let limbCount: Int
    }

    struct ParsedAnimationHeader: Equatable {
        let frameCount: Int
        let frameDataName: String
        let jointIndicesName: String
        let staticIndexMax: Int
    }

    struct ParsedPlayerAnimationHeader: Equatable {
        let frameCount: Int
        let dataName: String
    }

    final class ObjectXMLParserDelegate: NSObject, XMLParserDelegate {
        private let defaultName: String

        private(set) var externalAssetDirectories: [String] = []
        private(set) var skeletonNames: [String] = []
        private(set) var displayListNames: [String] = []
        private(set) var animationNames: [String] = []
        private(set) var playerAnimationNames: [String] = []
        private(set) var textureDefinitions: [ObjectTextureDefinition] = []

        private var currentSourceName: String?

        init(defaultName: String) {
            self.defaultName = defaultName
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "ExternalFile":
                if let outPath = attributeDict["OutPath"]?.trimmingCharacters(in: .whitespacesAndNewlines), outPath.isEmpty == false {
                    externalAssetDirectories.append(outPath.trimmingSuffix("/"))
                }
            case "File":
                currentSourceName = attributeDict["Name"]
            case "Skeleton":
                if let name = attributeDict["Name"] {
                    skeletonNames.append(name)
                }
            case "DList":
                if let name = attributeDict["Name"] {
                    displayListNames.append(name)
                }
            case "Animation":
                if let name = attributeDict["Name"] {
                    animationNames.append(name)
                }
            case "PlayerAnimation":
                if let name = attributeDict["Name"] {
                    playerAnimationNames.append(name)
                }
            case "Texture":
                guard
                    let name = attributeDict["Name"],
                    let format = Self.parseTextureFormat(attributeDict["Format"]),
                    let width = Self.parseInteger(attributeDict["Width"]),
                    let height = Self.parseInteger(attributeDict["Height"])
                else {
                    return
                }
                textureDefinitions.append(
                    ObjectTextureDefinition(
                        sourceName: currentSourceName ?? defaultName,
                        name: name,
                        format: format,
                        width: width,
                        height: height
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
                currentSourceName = nil
            }
        }

        private static func parseInteger(_ value: String?) -> Int? {
            guard let value else {
                return nil
            }
            return try? Int(parseIntegerExpression(value))
        }

        private static func parseTextureFormat(_ rawValue: String?) -> TextureFormat? {
            guard let rawValue else {
                return nil
            }

            let normalized = rawValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")

            return TextureFormat(rawValue: normalized)
        }
    }

    static let limbExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)(StandardLimb|LodLimb)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{(.*?)\};"#,
        options: [.anchorsMatchLines, .dotMatchesLineSeparators]
    )

    static let limbTableExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)(?:static\s+)?void\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{(.*?)\};"#,
        options: [.anchorsMatchLines, .dotMatchesLineSeparators]
    )

    static let skeletonExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)(SkeletonHeader|FlexSkeletonHeader)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{(.*?)\};"#,
        options: [.anchorsMatchLines, .dotMatchesLineSeparators]
    )

    static let signed16ArrayExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)(?:static\s+)?s16\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{(.*?)\};"#,
        options: [.anchorsMatchLines, .dotMatchesLineSeparators]
    )

    static let jointIndexArrayExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)(?:static\s+)?JointIndex\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{(.*?)\};"#,
        options: [.anchorsMatchLines, .dotMatchesLineSeparators]
    )

    static let animationExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)(AnimationHeader|LinkAnimationHeader)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{(.*?)\};"#,
        options: [.anchorsMatchLines, .dotMatchesLineSeparators]
    )

    static func loadObjects(in sourceRoot: URL, fileManager: FileManager) throws -> [ObjectDefinition] {
        let xmlRoot = sourceRoot
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("xml", isDirectory: true)
            .appendingPathComponent("objects", isDirectory: true)
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

        var objects: [ObjectDefinition] = []
        for case let xmlURL as URL in enumerator {
            let values = try xmlURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, xmlURL.pathExtension == "xml" else {
                continue
            }

            let name = xmlURL.deletingPathExtension().lastPathComponent
            guard name.contains("_pal_") == false else {
                continue
            }

            let data = try Data(contentsOf: xmlURL)
            let delegate = ObjectXMLParserDelegate(defaultName: name)
            let parser = XMLParser(data: data)
            parser.delegate = delegate

            guard parser.parse() else {
                let message = parser.parserError?.localizedDescription ?? "Unknown XML parsing error"
                throw ObjectExtractorError.invalidXML(xmlURL.path, message)
            }

            objects.append(
                ObjectDefinition(
                    name: name,
                    xmlURL: xmlURL,
                    externalAssetDirectories: Array(Set(delegate.externalAssetDirectories)).sorted(),
                    skeletonNames: Array(Set(delegate.skeletonNames)).sorted(),
                    displayListNames: Array(Set(delegate.displayListNames)).sorted(),
                    animationNames: Array(Set(delegate.animationNames)).sorted(),
                    playerAnimationNames: Array(Set(delegate.playerAnimationNames)).sorted(),
                    textureDefinitions: delegate.textureDefinitions.sorted { lhs, rhs in
                        if lhs.sourceName == rhs.sourceName {
                            return lhs.name < rhs.name
                        }
                        return lhs.sourceName < rhs.sourceName
                    }
                )
            )
        }

        return objects.sorted { $0.name < $1.name }
    }

    static func sourceFiles(for object: ObjectDefinition, sourceRoot: URL, fileManager: FileManager) throws -> [URL] {
        let baseRoots = try assetBaseRoots(in: sourceRoot, fileManager: fileManager)
        let relativeDirectories = ["assets/objects/\(object.name)"] + object.externalAssetDirectories
        let searchDirectories = relativeDirectories.flatMap { relativePath in
            baseRoots.map { $0.appendingPathComponent(relativePath, isDirectory: true) }
        }

        var files: [URL] = []
        var seenPaths = Set<String>()
        for directory in searchDirectories where fileManager.fileExists(atPath: directory.path) {
            guard let enumerator = fileManager.enumerator(
                at: directory,
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
                guard fileURL.pathExtension == "c", fileURL.lastPathComponent.hasSuffix(".inc.c") == false else {
                    continue
                }

                let standardized = fileURL.standardizedFileURL.path
                guard seenPaths.insert(standardized).inserted else {
                    continue
                }
                files.append(fileURL)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    static func assetBaseRoots(in sourceRoot: URL, fileManager: FileManager) throws -> [URL] {
        let buildRoot = sourceRoot.appendingPathComponent("build", isDirectory: true)
        var roots = [sourceRoot, buildRoot]

        if fileManager.fileExists(atPath: buildRoot.path) {
            let buildEntries = try fileManager.contentsOfDirectory(
                at: buildRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for entry in buildEntries {
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else {
                    continue
                }

                let assetRoot = entry.appendingPathComponent("assets", isDirectory: true)
                if fileManager.fileExists(atPath: assetRoot.path) {
                    roots.append(entry)
                }
            }
        }

        var uniqueRoots: [URL] = []
        var seenPaths = Set<String>()
        for root in roots {
            let standardizedPath = root.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else {
                continue
            }
            uniqueRoots.append(root)
        }

        return uniqueRoots
    }

    static func buildSourceIndex(
        from sourceFiles: [URL],
        sourceRoot: URL,
        vertexParser: VertexParser,
        displayListParser: DisplayListParser
    ) throws -> SourceIndex {
        var index = SourceIndex()

        for fileURL in sourceFiles {
            let expandedSource: String
            if let preexpandedSource = try? readExpandedSource(at: fileURL, sourceRoot: sourceRoot) {
                expandedSource = preexpandedSource
            } else {
                expandedSource = try String(contentsOf: fileURL, encoding: .utf8)
            }
            let sanitizedSource = stripLineComments(from: stripBlockComments(from: expandedSource))

            if let arrays = try? vertexParser.parseVertexArrays(in: fileURL, sourceRoot: sourceRoot) {
                for array in arrays {
                    index.vertexArrays[array.name] = array
                }
            }

            do {
                let displayLists = try displayListParser.parseDisplayLists(in: fileURL, sourceRoot: sourceRoot)
                for displayList in displayLists {
                    index.displayLists[displayList.name] = displayList
                }
            } catch {
                print("[ObjectExtractor] skipped display list parse for \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }

            parseLimbs(in: sanitizedSource, index: &index)
            parseLimbTables(in: sanitizedSource, index: &index)
            parseSkeletons(in: sanitizedSource, index: &index)
            parseSigned16Arrays(in: sanitizedSource, index: &index)
            parseJointIndexArrays(in: sanitizedSource, index: &index)
            parseAnimations(in: sanitizedSource, index: &index)
        }

        return index
    }

    static func emitMeshes(named names: [String], index: SourceIndex, meshesDirectory: URL) throws -> [ObjectMeshAsset] {
        var assets: [ObjectMeshAsset] = []
        var writtenVertices = Set<String>()
        let vertexNameByID = Dictionary(
            uniqueKeysWithValues: index.vertexArrays.values.map { (DisplayListParser.stableID(for: $0.name), $0.name) }
        )
        let displayListNameByID = Dictionary(
            uniqueKeysWithValues: index.displayLists.values.map { (DisplayListParser.stableID(for: $0.name), $0.name) }
        )

        for name in names {
            guard let displayList = index.displayLists[name] else {
                continue
            }

            let displayListURL = meshesDirectory.appendingPathComponent("\(name).dl.json")
            try writeJSON(displayList.commands, to: displayListURL)

            let vertexNames = referencedVertexArrayNames(
                from: name,
                displayLists: index.displayLists,
                vertexNameByID: vertexNameByID,
                displayListNameByID: displayListNameByID
            )
            let vertexPaths = try vertexNames.compactMap { vertexName -> String? in
                guard let array = index.vertexArrays[vertexName] else {
                    return nil
                }

                let path = "meshes/\(vertexName).vtx.bin"
                if writtenVertices.insert(vertexName).inserted {
                    try VertexParser.encode(array.vertices).write(
                        to: meshesDirectory.appendingPathComponent("\(vertexName).vtx.bin"),
                        options: .atomic
                    )
                }
                return path
            }

            assets.append(
                ObjectMeshAsset(
                    name: name,
                    displayListPath: "meshes/\(name).dl.json",
                    vertexPaths: vertexPaths.sorted()
                )
            )
        }

        return assets.sorted { $0.name < $1.name }
    }

    static func emitSkeletons(
        named names: [String],
        index: SourceIndex,
        availableDisplayLists: Set<String>
    ) throws -> [NamedSkeletonData] {
        try names.compactMap { name in
            guard let header = index.skeletons[name] else {
                return nil
            }
            guard let limbTable = index.limbTables[header.limbTableName], limbTable.count >= header.limbCount else {
                return nil
            }

            let limbs = try limbTable.prefix(header.limbCount).map { limbName in
                guard let limb = index.limbs[limbName] else {
                    throw ObjectExtractorError.missingSymbol(limbName)
                }

                let displayListPath = limb.displayListName.flatMap {
                    availableDisplayLists.contains($0) ? "meshes/\($0).dl.json" : nil
                }
                let lowDetailDisplayListPath = limb.lowDetailDisplayListName.flatMap {
                    availableDisplayLists.contains($0) ? "meshes/\($0).dl.json" : nil
                }

                return LimbData(
                    translation: limb.translation,
                    childIndex: limb.childIndex,
                    siblingIndex: limb.siblingIndex,
                    displayListPath: displayListPath,
                    lowDetailDisplayListPath: lowDetailDisplayListPath
                )
            }

            return NamedSkeletonData(name: name, skeleton: SkeletonData(type: header.type, limbs: limbs))
        }
    }

    static func emitAnimations(
        object: ObjectDefinition,
        index: SourceIndex,
        animationsDirectory: URL
    ) throws -> [ObjectAnimationReference] {
        var references: [ObjectAnimationReference] = []

        for name in object.animationNames {
            guard let animation = index.standardAnimations[name] else {
                continue
            }
            guard
                let values = index.frameData[animation.frameDataName],
                let jointIndices = index.jointIndices[animation.jointIndicesName]
            else {
                continue
            }

            let data = ObjectAnimationData(
                name: name,
                kind: .standard,
                frameCount: animation.frameCount,
                values: values,
                jointIndices: jointIndices,
                staticIndexMax: animation.staticIndexMax
            )
            let path = "animations/\(name).anim.json"
            try writeJSON(data, to: animationsDirectory.appendingPathComponent("\(name).anim.json"))
            references.append(ObjectAnimationReference(name: name, kind: .standard, path: path))
        }

        for name in object.playerAnimationNames {
            guard let animation = index.playerAnimations[name], let values = index.playerFrameData[animation.dataName] else {
                continue
            }

            let stride = animation.frameCount == 0 ? 0 : values.count / animation.frameCount
            let limbCount = stride > 0 ? max((stride - 1) / 3, 0) : nil
            let data = ObjectAnimationData(
                name: name,
                kind: .player,
                frameCount: animation.frameCount,
                values: values,
                limbCount: limbCount
            )
            let path = "animations/\(name).anim.json"
            try writeJSON(data, to: animationsDirectory.appendingPathComponent("\(name).anim.json"))
            references.append(ObjectAnimationReference(name: name, kind: .player, path: path))
        }

        return references.sorted { $0.name < $1.name }
    }

    static func copyTextures(
        for object: ObjectDefinition,
        from outputRoot: URL,
        to texturesDirectory: URL,
        fileManager: FileManager
    ) throws -> [TextureDescriptor] {
        var descriptors: [TextureDescriptor] = []
        var copiedNames = Set<String>()

        for texture in object.textureDefinitions {
            guard copiedNames.insert(texture.name).inserted else {
                continue
            }

            let sourceDirectory = outputRoot
                .appendingPathComponent("Textures", isDirectory: true)
                .appendingPathComponent(texture.sourceName, isDirectory: true)
            let sourceBinaryURL = sourceDirectory.appendingPathComponent("\(texture.name).tex.bin")
            let sourceMetadataURL = sourceDirectory.appendingPathComponent("\(texture.name).tex.json")
            guard fileManager.fileExists(atPath: sourceBinaryURL.path), fileManager.fileExists(atPath: sourceMetadataURL.path) else {
                continue
            }

            let destinationBinaryURL = texturesDirectory.appendingPathComponent("\(texture.name).tex.bin")
            let destinationMetadataURL = texturesDirectory.appendingPathComponent("\(texture.name).tex.json")
            if fileManager.fileExists(atPath: destinationBinaryURL.path) {
                try fileManager.removeItem(at: destinationBinaryURL)
            }
            if fileManager.fileExists(atPath: destinationMetadataURL.path) {
                try fileManager.removeItem(at: destinationMetadataURL)
            }
            try fileManager.copyItem(at: sourceBinaryURL, to: destinationBinaryURL)
            try fileManager.copyItem(at: sourceMetadataURL, to: destinationMetadataURL)

            descriptors.append(
                TextureDescriptor(
                    format: texture.format,
                    width: texture.width,
                    height: texture.height,
                    path: "textures/\(texture.name).tex.bin"
                )
            )
        }

        return descriptors.sorted { $0.path < $1.path }
    }

    static func parseLimbs(in source: String, index: inout SourceIndex) {
        for match in limbExpression.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        ) {
            guard
                let typeRange = Range(match.range(at: 1), in: source),
                let nameRange = Range(match.range(at: 2), in: source),
                let bodyRange = Range(match.range(at: 3), in: source)
            else {
                continue
            }

            let type = String(source[typeRange])
            let name = String(source[nameRange])
            let body = String(source[bodyRange])
            guard let limb = try? parseLimb(body: body, type: type) else {
                continue
            }
            index.limbs[name] = limb
        }
    }

    static func parseLimbTables(in source: String, index: inout SourceIndex) {
        for match in limbTableExpression.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        ) {
            guard
                let nameRange = Range(match.range(at: 1), in: source),
                let bodyRange = Range(match.range(at: 2), in: source)
            else {
                continue
            }

            let name = String(source[nameRange])
            let body = String(source[bodyRange])
            let symbols = splitTopLevel(body).compactMap(parseRequiredSymbol(from:))
            if symbols.isEmpty == false {
                index.limbTables[name] = symbols
            }
        }
    }

    static func parseSkeletons(in source: String, index: inout SourceIndex) {
        for match in skeletonExpression.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        ) {
            guard
                let kindRange = Range(match.range(at: 1), in: source),
                let nameRange = Range(match.range(at: 2), in: source),
                let bodyRange = Range(match.range(at: 3), in: source)
            else {
                continue
            }

            let kind = String(source[kindRange])
            let name = String(source[nameRange])
            let body = String(source[bodyRange])
            guard let header = try? parseSkeletonHeader(body: body, kind: kind) else {
                continue
            }
            index.skeletons[name] = header
        }
    }

    static func parseSigned16Arrays(in source: String, index: inout SourceIndex) {
        for match in signed16ArrayExpression.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        ) {
            guard
                let nameRange = Range(match.range(at: 1), in: source),
                let bodyRange = Range(match.range(at: 2), in: source)
            else {
                continue
            }

            let name = String(source[nameRange])
            let body = String(source[bodyRange])
            let values = parseSigned16Values(in: body)
            if values.isEmpty == false {
                index.frameData[name] = values
                index.playerFrameData[name] = values
            }
        }
    }

    static func parseJointIndexArrays(in source: String, index: inout SourceIndex) {
        for match in jointIndexArrayExpression.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        ) {
            guard
                let nameRange = Range(match.range(at: 1), in: source),
                let bodyRange = Range(match.range(at: 2), in: source)
            else {
                continue
            }

            let name = String(source[nameRange])
            let body = String(source[bodyRange])
            let values = parseJointIndices(in: body)
            if values.isEmpty == false {
                index.jointIndices[name] = values
            }
        }
    }

    static func parseAnimations(in source: String, index: inout SourceIndex) {
        for match in animationExpression.matches(
            in: source,
            range: NSRange(source.startIndex..<source.endIndex, in: source)
        ) {
            guard
                let kindRange = Range(match.range(at: 1), in: source),
                let nameRange = Range(match.range(at: 2), in: source),
                let bodyRange = Range(match.range(at: 3), in: source)
            else {
                continue
            }

            let kind = String(source[kindRange])
            let name = String(source[nameRange])
            let body = String(source[bodyRange])

            if kind == "AnimationHeader", let animation = try? parseStandardAnimationHeader(body: body) {
                index.standardAnimations[name] = animation
            } else if kind == "LinkAnimationHeader", let animation = try? parsePlayerAnimationHeader(body: body) {
                index.playerAnimations[name] = animation
            }
        }
    }

    static func parseLimb(body: String, type: String) throws -> ParsedLimb {
        let fields = splitTopLevel(body)
        if type == "StandardLimb" {
            guard fields.count >= 4 else {
                throw ObjectExtractorError.invalidSource("Expected 4 fields for StandardLimb")
            }
            return ParsedLimb(
                translation: try parseVector3s(fields[0]),
                childIndex: try parseOptionalLimbIndex(fields[1]),
                siblingIndex: try parseOptionalLimbIndex(fields[2]),
                displayListName: parseOptionalSymbol(from: fields[3]),
                lowDetailDisplayListName: nil
            )
        }

        guard fields.count >= 4 else {
            throw ObjectExtractorError.invalidSource("Expected 4 fields for LodLimb")
        }
        let dlistFields = splitTopLevel(trimOuterBraces(fields[3]))
        return ParsedLimb(
            translation: try parseVector3s(fields[0]),
            childIndex: try parseOptionalLimbIndex(fields[1]),
            siblingIndex: try parseOptionalLimbIndex(fields[2]),
            displayListName: dlistFields.indices.contains(0) ? parseOptionalSymbol(from: dlistFields[0]) : nil,
            lowDetailDisplayListName: dlistFields.indices.contains(1) ? parseOptionalSymbol(from: dlistFields[1]) : nil
        )
    }

    static func parseSkeletonHeader(body: String, kind: String) throws -> ParsedSkeletonHeader {
        let fields = splitTopLevel(body)
        if kind == "SkeletonHeader" {
            guard fields.count >= 2, let limbTableName = parseRequiredSymbol(from: fields[0]) else {
                throw ObjectExtractorError.invalidSource("Expected limb table for SkeletonHeader")
            }
            return ParsedSkeletonHeader(
                type: .normal,
                limbTableName: limbTableName,
                limbCount: Int(try parseIntegerExpression(fields[1]))
            )
        }

        guard fields.count >= 2 else {
            throw ObjectExtractorError.invalidSource("Expected 2 fields for FlexSkeletonHeader")
        }
        let nestedFields = splitTopLevel(trimOuterBraces(fields[0]))
        guard nestedFields.count >= 2, let limbTableName = parseRequiredSymbol(from: nestedFields[0]) else {
            throw ObjectExtractorError.invalidSource("Expected nested SkeletonHeader fields for FlexSkeletonHeader")
        }
        return ParsedSkeletonHeader(
            type: .flex,
            limbTableName: limbTableName,
            limbCount: Int(try parseIntegerExpression(nestedFields[1]))
        )
    }

    static func parseStandardAnimationHeader(body: String) throws -> ParsedAnimationHeader {
        let fields = splitTopLevel(body)
        guard fields.count >= 4 else {
            throw ObjectExtractorError.invalidSource("Expected 4 fields for AnimationHeader")
        }

        let commonFields = splitTopLevel(trimOuterBraces(fields[0]))
        guard let frameCountField = commonFields.first else {
            throw ObjectExtractorError.invalidSource("Expected frame count in AnimationHeaderCommon")
        }
        guard
            let frameDataName = parseRequiredSymbol(from: fields[1]),
            let jointIndicesName = parseRequiredSymbol(from: fields[2])
        else {
            throw ObjectExtractorError.invalidSource("AnimationHeader references must be symbols")
        }

        return ParsedAnimationHeader(
            frameCount: Int(try parseIntegerExpression(frameCountField)),
            frameDataName: frameDataName,
            jointIndicesName: jointIndicesName,
            staticIndexMax: Int(try parseIntegerExpression(fields[3]))
        )
    }

    static func parsePlayerAnimationHeader(body: String) throws -> ParsedPlayerAnimationHeader {
        let fields = splitTopLevel(body)
        guard fields.count >= 2 else {
            throw ObjectExtractorError.invalidSource("Expected at least 2 fields for LinkAnimationHeader")
        }

        let commonFields = splitTopLevel(trimOuterBraces(fields[0]))
        guard
            let frameCountField = commonFields.first,
            let dataName = parseRequiredSymbol(from: fields.last ?? "")
        else {
            throw ObjectExtractorError.invalidSource("LinkAnimationHeader references must be symbols")
        }

        return ParsedPlayerAnimationHeader(
            frameCount: Int(try parseIntegerExpression(frameCountField)),
            dataName: dataName
        )
    }

    static func parseSigned16Values(in body: String) -> [Int16] {
        splitTopLevel(body).compactMap { entry in
            try? parseSigned16Expression(entry)
        }
    }

    static func parseJointIndices(in body: String) -> [AnimationJointIndex] {
        splitTopLevel(body).compactMap { entry in
            let fields = splitTopLevel(trimOuterBraces(entry))
            guard fields.count == 3 else {
                return nil
            }
            guard
                let x = try? parseIntegerExpression(fields[0]),
                let y = try? parseIntegerExpression(fields[1]),
                let z = try? parseIntegerExpression(fields[2])
            else {
                return nil
            }

            return AnimationJointIndex(x: Int(x), y: Int(y), z: Int(z))
        }
    }

    static func parseOptionalLimbIndex(_ expression: String) throws -> Int? {
        let value = Int(try parseIntegerExpression(expression))
        if value == 0xFF {
            return nil
        }
        return value
    }

    static func parseOptionalSymbol(from expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        if trimmed == "NULL" || trimmed == "0" {
            return nil
        }

        let normalized = trimOuterBraces(trimmed)
            .replacingOccurrences(of: "&", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            return nil
        }

        let pattern = #"[A-Za-z_][A-Za-z0-9_]*"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)),
            let range = Range(match.range, in: normalized)
        else {
            return nil
        }

        let symbol = String(normalized[range])
        if symbol == "NULL" {
            return nil
        }
        return symbol
    }

    static func parseRequiredSymbol(from expression: String) -> String? {
        parseOptionalSymbol(from: expression)
    }

    static func trimOuterBraces(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}" else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    static func referencedVertexArrayNames(
        from displayListName: String,
        displayLists: [String: ParsedDisplayList],
        vertexNameByID: [UInt32: String],
        displayListNameByID: [UInt32: String]
    ) -> Set<String> {
        guard let root = displayLists[displayListName] else {
            return []
        }

        var seenDisplayLists = Set<String>()
        var queue = [root]
        var vertexNames = Set<String>()

        while let current = queue.popLast() {
            guard seenDisplayLists.insert(current.name).inserted else {
                continue
            }

            for command in current.commands {
                switch command {
                case .spVertex(let vertexCommand):
                    if let vertexName = vertexNameByID[vertexCommand.address] {
                        vertexNames.insert(vertexName)
                    }
                case .spDisplayList(let address), .spBranchList(let address):
                    if let childName = displayListNameByID[address], let child = displayLists[childName] {
                        queue.append(child)
                    }
                default:
                    break
                }
            }
        }

        return vertexNames
    }

    static func readJSON<T: Decodable>(from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func trimExpression(_ expression: String) -> String {
        expression.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripBlockComments(from expression: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"/\*.*?\*/"#, options: [.dotMatchesLineSeparators])
        let range = NSRange(expression.startIndex..<expression.endIndex, in: expression)
        return regex.stringByReplacingMatches(in: expression, range: range, withTemplate: " ")
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

    static func readSource(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
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

            let replacement: String
            if let includeURL = resolveIncludedSource(path: includePath, relativeTo: url, sourceRoot: sourceRoot) {
                replacement = try expandIncludeBackedSource(at: includeURL, sourceRoot: sourceRoot, visited: &visited)
            } else {
                replacement = ""
            }

            guard let replacementRange = Range(match.range, in: expanded) else {
                continue
            }
            expanded.replaceSubrange(replacementRange, with: replacement)
        }

        return expanded
    }

    static func resolveIncludedSource(path: String, relativeTo sourceFile: URL, sourceRoot: URL) -> URL? {
        var candidates = [sourceFile.deletingLastPathComponent().appendingPathComponent(path)]
        if let assetRoot = assetRoot(for: sourceFile) {
            candidates.append(assetRoot.appendingPathComponent(path))
        }
        if let baseRoots = try? assetBaseRoots(in: sourceRoot, fileManager: .default) {
            candidates.append(contentsOf: baseRoots.map { $0.appendingPathComponent(path) })
        } else {
            candidates.append(sourceRoot.appendingPathComponent(path))
            candidates.append(sourceRoot.appendingPathComponent("build", isDirectory: true).appendingPathComponent(path))
        }

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
                    throw ObjectExtractorError.invalidSource("Unbalanced braces")
                }
                if depth == 0, let startIndex {
                    entries.append(
                        String(characters[startIndex..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
        }

        if depth != 0 {
            throw ObjectExtractorError.invalidSource("Unbalanced braces")
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
            throw ObjectExtractorError.invalidSource("Invalid vector expression \(expression)")
        }

        return Vector3s(
            x: try parseSigned16Expression(values[0]),
            y: try parseSigned16Expression(values[1]),
            z: try parseSigned16Expression(values[2])
        )
    }

    static func parseSigned16Expression(_ expression: String) throws -> Int16 {
        let value = try parseIntegerExpression(expression)
        guard value >= Int64(Int16.min), value <= Int64(Int16.max) else {
            throw ObjectExtractorError.invalidSource("Value out of range for signed 16-bit: \(expression)")
        }
        return Int16(value)
    }

    static func parseIntegerExpression(_ expression: String) throws -> Int64 {
        let trimmed = trimExpression(expression)
            .replacingOccurrences(of: "LIMB_DONE", with: "0xFF")

        if trimmed.first == "(", trimmed.last == ")" {
            return try parseIntegerExpression(String(trimmed.dropFirst().dropLast()))
        }
        if trimmed.first == "{", trimmed.last == "}" {
            return try parseIntegerExpression(String(trimmed.dropFirst().dropLast()))
        }

        if trimmed.lowercased().hasPrefix("0x"), let value = Int64(trimmed.dropFirst(2), radix: 16) {
            return value
        }
        if let value = Int64(trimmed) {
            return value
        }

        throw ObjectExtractorError.invalidSource("Invalid integer expression \(expression)")
    }

    static func substring(in text: String, range: NSRange) -> String {
        guard let range = Range(range, in: text) else {
            return ""
        }
        return String(text[range])
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

private enum ObjectExtractorError: LocalizedError {
    case invalidXML(String, String)
    case invalidSource(String)
    case missingOutput(String)
    case missingSymbol(String)

    var errorDescription: String? {
        switch self {
        case .invalidXML(let path, let message):
            return "Failed to parse object XML '\(path)': \(message)"
        case .invalidSource(let message):
            return "Failed to parse object source: \(message)"
        case .missingOutput(let path):
            return "Missing required object output \(path)"
        case .missingSymbol(let symbol):
            return "Missing required symbol \(symbol)"
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else {
            return self
        }
        return String(dropLast(suffix.count))
    }
}

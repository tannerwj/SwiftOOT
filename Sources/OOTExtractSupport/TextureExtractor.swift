import CoreGraphics
import Foundation
import ImageIO
import OOTDataModel

extension TextureExtractor {
    public func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let sourceGroups = try Self.loadTextureSourceGroups(
            in: context.source,
            outputRoot: context.output,
            sceneNames: context.sceneNames,
            fileManager: fileManager
        )
        let decoder = N64TextureDecoder()
        var emittedTextures = 0

        for sourceGroup in sourceGroups {
            let pngFallbackTLUTNames = Self.pngFallbackTLUTNames(in: sourceGroup)
            let arrayBackedTextures = sourceGroup.textures.filter { $0.pngURL == nil }
            let requiredArrayNames = Set(
                arrayBackedTextures.map(\.name)
                    + arrayBackedTextures.compactMap(\.tlutName)
                    + arrayBackedTextures.compactMap(\.tlutOffset).compactMap {
                        Self.tlutDefinition(forOffset: $0, in: sourceGroup)?.name
                    }
            )
            let arrays: [String: ParsedTextureArray]
            let sourceFilePath: String
            if requiredArrayNames.isEmpty {
                arrays = [:]
                sourceFilePath = sourceGroup.xmlURL.path
            } else {
                let sourceFiles = try Self.resolveSourceFiles(
                    for: sourceGroup,
                    requiredSymbols: requiredArrayNames,
                    sourceRoot: context.source,
                    fileManager: fileManager
                )
                sourceFilePath = sourceFiles.map(\.path).joined(separator: ", ")
                arrays = try sourceFiles.reduce(into: [:]) { result, sourceFile in
                    let expandedSource = try CMacroPreprocessor().preprocess(
                        fileURL: sourceFile,
                        sourceRoot: context.source
                    )
                    let parsedArrays = try Self.parseTextureArrays(
                        in: expandedSource,
                        sourceFile: sourceFile,
                        requiredArrayNames: requiredArrayNames.subtracting(result.keys)
                    )
                    result.merge(parsedArrays) { current, _ in current }
                }
            }
            let outputDirectory = context.output
                .appendingPathComponent("Textures", isDirectory: true)
                .appendingPathComponent(sourceGroup.outputSource, isDirectory: true)
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            for texture in sourceGroup.textures {
                if Self.shouldSkipOrphanedTLUT(texture, in: sourceGroup) {
                    continue
                }
                if let pngURL = texture.pngURL {
                    let binaryData = try Self.loadPNGTextureData(
                        from: pngURL,
                        expectedWidth: texture.width,
                        expectedHeight: texture.height
                    )
                    try binaryData.write(
                        to: outputDirectory.appendingPathComponent("\(texture.name).tex.bin"),
                        options: [.atomic]
                    )
                    try Self.writeJSON(
                        TextureAssetMetadata(format: .rgba32, width: texture.width, height: texture.height, hasTLUT: false),
                        to: outputDirectory.appendingPathComponent("\(texture.name).tex.json")
                    )
                    emittedTextures += 1
                    continue
                }

                guard let textureArray = arrays[texture.name] else {
                    if pngFallbackTLUTNames.contains(texture.name) {
                        continue
                    }
                    throw TextureExtractorError.missingArray(texture.name, sourceFilePath)
                }
                if pngFallbackTLUTNames.contains(texture.name), Self.isEmpty(textureArray.dataSource) {
                    continue
                }

                let tlutDataSource: N64TextureDataSource?
                let tlutFormat: TextureFormat?
                if let tlutName = texture.tlutName {
                    guard let tlut = sourceGroup.tlutByName[tlutName] else {
                        throw TextureExtractorError.missingNamedTLUTDefinition(
                            texture.name,
                            tlutName,
                            sourceGroup.xmlURL.path
                        )
                    }
                    guard let tlutArray = arrays[tlut.name] else {
                        throw TextureExtractorError.missingArray(tlut.name, sourceFilePath)
                    }

                    tlutDataSource = tlutArray.dataSource
                    tlutFormat = tlut.format
                } else if let tlutOffset = texture.tlutOffset {
                    guard let tlut = Self.tlutDefinition(forOffset: tlutOffset, in: sourceGroup) else {
                        throw TextureExtractorError.missingTLUTDefinition(
                            texture.name,
                            tlutOffset,
                            sourceGroup.xmlURL.path
                        )
                    }
                    guard let tlutArray = arrays[tlut.name] else {
                        throw TextureExtractorError.missingArray(tlut.name, sourceFilePath)
                    }

                    tlutDataSource = tlutArray.dataSource
                    tlutFormat = tlut.format
                } else {
                    tlutDataSource = nil
                    tlutFormat = nil
                }

                let decoded: DecodedN64Texture
                do {
                    decoded = try decoder.decode(
                        format: texture.format,
                        width: texture.width,
                        height: texture.height,
                        texelData: textureArray.dataSource,
                        tlutData: tlutDataSource,
                        tlutFormat: tlutFormat
                    )
                } catch {
                    throw TextureExtractorError.textureDecodingFailed(
                        texture.name,
                        sourceGroup.sourceName,
                        error.localizedDescription
                    )
                }

                var binaryData = decoded.texelData
                if let tlutData = decoded.tlutData {
                    binaryData.append(tlutData)
                }

                try binaryData.write(
                    to: outputDirectory.appendingPathComponent("\(texture.name).tex.bin"),
                    options: [.atomic]
                )
                try Self.writeJSON(
                    decoded.metadata,
                    to: outputDirectory.appendingPathComponent("\(texture.name).tex.json")
                )
                emittedTextures += 1
            }
        }

        print("[\(name)] emitted \(emittedTextures) texture asset(s)")
    }

    public func verify(using context: OOTVerificationContext) throws {
        let fileManager = FileManager.default
        let texturesRoot = context.content.appendingPathComponent("Textures", isDirectory: true)

        guard fileManager.fileExists(atPath: texturesRoot.path) else {
            print("[\(name)] verified 0 texture asset(s)")
            return
        }

        guard let enumerator = fileManager.enumerator(
            at: texturesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[\(name)] verified 0 texture asset(s)")
            return
        }

        var verifiedTextures = 0

        for case let metadataURL as URL in enumerator {
            let values = try metadataURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            guard metadataURL.lastPathComponent.hasSuffix(".tex.json") else {
                continue
            }

            let metadata: TextureAssetMetadata = try Self.readJSON(from: metadataURL)
            let binaryURL = metadataURL.deletingPathExtension().deletingPathExtension().appendingPathExtension("tex.bin")
            guard fileManager.fileExists(atPath: binaryURL.path) else {
                throw TextureExtractorError.missingTextureBinary(binaryURL.path)
            }

            let binaryData = try Data(contentsOf: binaryURL)
            let expectedSize = try Self.expectedBinaryByteCount(for: metadata)
            guard binaryData.count == expectedSize else {
                throw TextureExtractorError.invalidBinarySize(
                    binaryURL.path,
                    expected: expectedSize,
                    actual: binaryData.count
                )
            }

            verifiedTextures += 1
        }

        print("[\(name)] verified \(verifiedTextures) texture asset(s)")
    }
}

private extension TextureExtractor {
    struct TextureSourceGroup: Sendable {
        let xmlURL: URL
        let sourceName: String
        let outputSource: String
        let assetDirectory: String
        let textures: [TextureDefinition]
        let tlutByOffset: [Int: TLUTDefinition]
        let tlutByName: [String: TLUTDefinition]
    }

    struct TextureDefinition: Sendable {
        let name: String
        let format: TextureFormat
        let width: Int
        let height: Int
        let offset: Int
        let tlutOffset: Int?
        let tlutName: String?
        let pngURL: URL?
        let ignoreIfOrphanedTLUT: Bool
    }

    struct TLUTDefinition: Sendable {
        let name: String
        let format: TextureFormat?
        let offset: Int
    }

    struct ParsedTextureArray: Sendable {
        let dataSource: N64TextureDataSource
    }

    struct SourceBackedTextureDeclaration: Sendable {
        let name: String
        let format: TextureFormat
        let width: Int
        let height: Int
        let order: Int
        let tlutName: String?
        let pngURL: URL?
        let usesMissingIncludeFallback: Bool
    }

    struct SourceBackedTextureFallbackDeclaration: Sendable {
        let name: String
        let pngURL: URL?
        let usesMissingIncludeFallback: Bool
    }

    struct SourceBackedTLUTDeclaration: Sendable {
        let name: String
        let format: TextureFormat?
        let order: Int
    }

    enum AssetKind {
        case object
        case scene
        case textureCatalog
    }

    enum IntegerArrayElementKind: String {
        case s8
        case u8
        case s16
        case u16
        case s32
        case u32
        case s64
        case u64
    }

    static func pngFallbackTLUTNames(in sourceGroup: TextureSourceGroup) -> Set<String> {
        Set(
            sourceGroup.textures.compactMap { texture in
                guard texture.pngURL != nil else {
                    return nil
                }
                if let tlutName = texture.tlutName {
                    return tlutName
                }
                if let tlutOffset = texture.tlutOffset {
                    return tlutDefinition(forOffset: tlutOffset, in: sourceGroup)?.name
                }
                return nil
            }
        )
    }

    static func tlutDefinition(
        forOffset offset: Int,
        in sourceGroup: TextureSourceGroup
    ) -> TLUTDefinition? {
        if let tlut = sourceGroup.tlutByOffset[offset] {
            return tlut
        }

        guard let texture = sourceGroup.textures.first(where: {
            $0.offset == offset && $0.format == .rgba16
        }) else {
            return nil
        }

        return TLUTDefinition(name: texture.name, format: .rgba16, offset: texture.offset)
    }

    static func isEmpty(_ dataSource: N64TextureDataSource) -> Bool {
        switch dataSource {
        case .bytes(let bytes):
            return bytes.isEmpty
        case .words(let words):
            return words.isEmpty
        }
    }

    static func shouldSkipOrphanedTLUT(_ texture: TextureDefinition, in sourceGroup: TextureSourceGroup) -> Bool {
        guard texture.ignoreIfOrphanedTLUT else {
            return false
        }

        return sourceGroup.textures.contains { candidate in
            guard candidate.name != texture.name else {
                return false
            }
            return candidate.tlutName == texture.name || candidate.tlutOffset == texture.offset
        } == false
    }

    final class TextureXMLParserDelegate: NSObject, XMLParserDelegate {
        private let defaultSourceName: String
        private(set) var groupedTextures: [String: [TextureDefinition]] = [:]
        private(set) var groupedTLUTs: [String: [TLUTDefinition]] = [:]
        private(set) var sourceNames: [String] = []
        private var currentSourceName: String?

        init(defaultSourceName: String) {
            self.defaultSourceName = defaultSourceName
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "File":
                currentSourceName = attributeDict["Name"]
                if let currentSourceName, sourceNames.contains(currentSourceName) == false {
                    sourceNames.append(currentSourceName)
                }
            case "Texture":
                guard
                    let name = attributeDict["Name"],
                    let format = parseTextureFormat(attributeDict["Format"]),
                    let width = Self.parseInteger(attributeDict["Width"]),
                    let height = Self.parseInteger(attributeDict["Height"]),
                    let offset = Self.parseInteger(attributeDict["Offset"])
                else {
                    return
                }

                let sourceName = currentSourceName ?? defaultSourceName
                groupedTextures[sourceName, default: []].append(
                    TextureDefinition(
                        name: name,
                        format: format,
                        width: width,
                        height: height,
                        offset: offset,
                        tlutOffset: Self.parseInteger(attributeDict["TlutOffset"]),
                        tlutName: nil,
                        pngURL: nil,
                        ignoreIfOrphanedTLUT: attributeDict["HackMode"] == "ignore_orphaned_tlut"
                    )
                )
            case "TLUT":
                guard
                    let name = attributeDict["Name"],
                    let offset = Self.parseInteger(attributeDict["Offset"])
                else {
                    return
                }

                let sourceName = currentSourceName ?? defaultSourceName
                groupedTLUTs[sourceName, default: []].append(
                    TLUTDefinition(
                        name: name,
                        format: parseTextureFormat(attributeDict["Format"]),
                        offset: offset
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
    }

    static let arrayExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)(?:static\s+)?(?:(?:const|volatile)\s+)*(s8|u8|s16|u16|s32|u32|s64|u64)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{"#,
        options: [.anchorsMatchLines]
    )
    static let sourceBackedTextureDefinitionExpression = try! NSRegularExpression(
        pattern: #"(?:^|\n)\s*u(?:8|16|32|64)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\[[^\]]*\]\s*=\s*\{\s*#include\s+\"([^\"]+)\"\s*\};"#,
        options: [.dotMatchesLineSeparators]
    )
    static let textureDimensionExpression = try! NSRegularExpression(
        pattern: #"#define\s+([A-Za-z_][A-Za-z0-9_]*)_(WIDTH|HEIGHT)\s+([0-9]+)"#
    )
    static let textureIncludeWithTLUTExpression = try! NSRegularExpression(
        pattern: #"^[^.]+\.([A-Za-z0-9]+)(?:\.[A-Za-z0-9_]+)*\.tlut_([A-Za-z_][A-Za-z0-9_]*?)(?:_(?:u8|u16|u32|u64))?(?:\.[A-Za-z0-9_]+)*\.inc\.c$"#
    )
    static let tlutIncludeExpression = try! NSRegularExpression(
        pattern: #"^[^.]+\.tlut\.([A-Za-z0-9]+)(?:\.[A-Za-z0-9_]+)*\.inc\.c$"#
    )
    static let textureIncludeExpression = try! NSRegularExpression(
        pattern: #"^[^.]+\.([A-Za-z0-9]+)(?:\.[A-Za-z0-9_]+)*\.inc\.c$"#
    )

    static func loadTextureSourceGroups(
        in sourceRoot: URL,
        outputRoot: URL,
        sceneNames: Set<String>?,
        fileManager: FileManager
    ) throws -> [TextureSourceGroup] {
        var groups: [TextureSourceGroup] = []
        let requiredObjectNames =
            try sceneNames.map { try SceneSelection.requiredObjectNames(for: $0, outputRoot: outputRoot, fileManager: fileManager) }

        if sceneNames == nil || requiredObjectNames?.isEmpty == false {
            groups.append(contentsOf: try loadTextureSourceGroups(
                in: sourceRoot,
                xmlSubdirectory: "assets/xml/objects",
                assetSubdirectory: "assets/objects",
                kind: .object,
                sceneNames: nil,
                objectNames: requiredObjectNames,
                fileManager: fileManager
            ))
        }

        groups.append(contentsOf: try loadTextureSourceGroups(
            in: sourceRoot,
            xmlSubdirectory: "assets/xml/scenes",
            assetSubdirectory: "assets/scenes",
            kind: .scene,
            sceneNames: sceneNames,
            objectNames: nil,
            fileManager: fileManager
        ))

        groups.append(contentsOf: try loadTextureSourceGroups(
            in: sourceRoot,
            xmlSubdirectory: "assets/xml/textures",
            assetSubdirectory: "assets/textures",
            kind: .textureCatalog,
            sceneNames: nil,
            objectNames: nil,
            fileManager: fileManager
        ))

        return groups.sorted { lhs, rhs in
            if lhs.outputSource == rhs.outputSource {
                return lhs.sourceName < rhs.sourceName
            }
            return lhs.outputSource < rhs.outputSource
        }
    }

    static func loadTextureSourceGroups(
        in sourceRoot: URL,
        xmlSubdirectory: String,
        assetSubdirectory: String,
        kind: AssetKind,
        sceneNames: Set<String>?,
        objectNames: Set<String>?,
        fileManager: FileManager
    ) throws -> [TextureSourceGroup] {
        let xmlRoot = sourceRoot.appendingPathComponent(xmlSubdirectory, isDirectory: true)
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

        var groups: [TextureSourceGroup] = []

        for case let xmlURL as URL in enumerator {
            let values = try xmlURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, xmlURL.pathExtension == "xml" else {
                continue
            }
            let sourceName = xmlURL.deletingPathExtension().lastPathComponent
            if kind == .scene, SceneSelection.includes(sourceName, in: sceneNames) == false {
                continue
            }
            if let objectNames, kind == .object, objectNames.contains(sourceName) == false {
                continue
            }
            if kind == .textureCatalog, sourceName != "skyboxes" {
                continue
            }

            groups.append(contentsOf: try parseTextureSourceGroups(
                from: xmlURL,
                xmlRoot: xmlRoot,
                assetSubdirectory: assetSubdirectory,
                kind: kind,
                sourceRoot: sourceRoot,
                fileManager: fileManager
            ))
        }

        return groups
    }

    static func parseTextureSourceGroups(
        from xmlURL: URL,
        xmlRoot: URL,
        assetSubdirectory: String,
        kind: AssetKind,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> [TextureSourceGroup] {
        let data = try Data(contentsOf: xmlURL)
        let xmlRelativeDirectory = xmlURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
            .replacingOccurrences(of: xmlRoot.standardizedFileURL.path, with: "")
            .trimmingPrefix("/")
        let defaultSourceName = xmlURL.deletingPathExtension().lastPathComponent
        let delegate = TextureXMLParserDelegate(defaultSourceName: defaultSourceName)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "Unknown XML parsing error"
            throw TextureExtractorError.invalidXML(xmlURL.path, message)
        }

        let assetDirectory = [assetSubdirectory, xmlRelativeDirectory, defaultSourceName]
            .filter { $0.isEmpty == false }
            .joined(separator: "/")

        if kind == .textureCatalog {
            let sourceNames = delegate.sourceNames.isEmpty ? [defaultSourceName] : delegate.sourceNames
            let sourceBackedGroups = try parseSourceBackedTextureSourceGroups(
                sourceNames: sourceNames,
                xmlURL: xmlURL,
                assetDirectory: assetDirectory,
                sourceRoot: sourceRoot,
                fileManager: fileManager
            )

            if sourceBackedGroups.isEmpty == false {
                return sourceBackedGroups.sorted { $0.sourceName < $1.sourceName }
            }
        }

        var groups: [TextureSourceGroup] = []
        for (sourceName, textures) in delegate.groupedTextures {
            let tluts = delegate.groupedTLUTs[sourceName] ?? []
            let tlutByOffset = Dictionary(tluts.map { ($0.offset, $0) }, uniquingKeysWith: { current, _ in current })
            let tlutByName = Dictionary(tluts.map { ($0.name, $0) }, uniquingKeysWith: { current, _ in current })
            groups.append(
                TextureSourceGroup(
                    xmlURL: xmlURL,
                    sourceName: sourceName,
                    outputSource: sourceName,
                    assetDirectory: assetDirectory,
                    textures: textures.sorted {
                        if $0.offset == $1.offset {
                            return $0.name < $1.name
                        }
                        return $0.offset < $1.offset
                    },
                    tlutByOffset: tlutByOffset,
                    tlutByName: tlutByName
                )
            )
        }

        if groups.isEmpty {
            groups = try parseSourceBackedTextureSourceGroups(
                sourceNames: delegate.sourceNames.isEmpty ? [defaultSourceName] : delegate.sourceNames,
                xmlURL: xmlURL,
                assetDirectory: assetDirectory,
                sourceRoot: sourceRoot,
                fileManager: fileManager
            )
        } else {
            groups = try applySourceBackedPNGFallbacks(
                to: groups,
                sourceRoot: sourceRoot,
                fileManager: fileManager
            )
        }

        return groups.sorted { $0.sourceName < $1.sourceName }
    }

    static func locateSourceFile(
        named basename: String,
        preferredExtensions: [String],
        assetDirectory: String,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> URL? {
        let directDirectories = directAssetDirectories(
            assetDirectory: assetDirectory,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        )

        for directory in directDirectories where fileManager.fileExists(atPath: directory.path) {
            for fileExtension in preferredExtensions {
                let candidate = directory.appendingPathComponent("\(basename).\(fileExtension)")
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        let searchRoots =
            [
                sourceRoot.appendingPathComponent("build", isDirectory: true),
            ]
            + extractedRoots(in: sourceRoot, fileManager: fileManager)
            + [sourceRoot]

        for searchRoot in searchRoots where fileManager.fileExists(atPath: searchRoot.path) {
            if let match = try firstMatchingSource(
                namedAnyOf: [basename],
                preferredExtensions: preferredExtensions,
                in: searchRoot,
                fileManager: fileManager
            ) {
                return match
            }
        }

        return nil
    }

    static func directAssetDirectories(
        assetDirectory: String,
        sourceRoot: URL,
        fileManager: FileManager
    ) -> [URL] {
        (
            [
                sourceRoot.appendingPathComponent("build", isDirectory: true).appendingPathComponent(assetDirectory, isDirectory: true),
                sourceRoot.appendingPathComponent(assetDirectory, isDirectory: true),
            ]
            + extractedRoots(in: sourceRoot, fileManager: fileManager).map {
                $0.appendingPathComponent(assetDirectory, isDirectory: true)
            }
        ).filter { fileManager.fileExists(atPath: $0.path) }
    }

    static func extractedRoots(in sourceRoot: URL, fileManager: FileManager) -> [URL] {
        let extractedRoot = sourceRoot.appendingPathComponent("extracted", isDirectory: true)
        guard fileManager.fileExists(atPath: extractedRoot.path) else {
            return []
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: extractedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.compactMap { child in
            guard
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory == true
            else {
                return nil
            }
            return child
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func parseSourceBackedTextureSourceGroups(
        sourceNames: [String],
        xmlURL: URL,
        assetDirectory: String,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> [TextureSourceGroup] {
        var groups: [TextureSourceGroup] = []
        var seenSourceNames: Set<String> = []

        for sourceName in sourceNames where seenSourceNames.insert(sourceName).inserted {
            guard let sourceFile = try locateSourceFile(
                named: sourceName,
                preferredExtensions: ["c", "inc.c"],
                assetDirectory: assetDirectory,
                sourceRoot: sourceRoot,
                fileManager: fileManager
            ) else {
                continue
            }

            let headerFile = try locateSourceFile(
                named: sourceName,
                preferredExtensions: ["h"],
                assetDirectory: assetDirectory,
                sourceRoot: sourceRoot,
                fileManager: fileManager
            )
            let sourceContents = try String(contentsOf: sourceFile, encoding: .utf8)
            let headerContents = if let headerFile {
                try String(contentsOf: headerFile, encoding: .utf8)
            } else {
                ""
            }

            let dimensionsByName = parseTextureDimensions(in: headerContents)
            let declarations = parseSourceBackedTextureDeclarations(
                in: sourceContents,
                dimensionsByName: dimensionsByName,
                sourceFile: sourceFile,
                sourceRoot: sourceRoot,
                fileManager: fileManager
            )

            guard declarations.textures.isEmpty == false else {
                continue
            }

            let tluts = declarations.tluts.map {
                TLUTDefinition(name: $0.name, format: $0.format, offset: $0.order)
            }
            let tlutByOffset = Dictionary(tluts.map { ($0.offset, $0) }, uniquingKeysWith: { current, _ in current })
            let tlutByName = Dictionary(tluts.map { ($0.name, $0) }, uniquingKeysWith: { current, _ in current })
            let textures = declarations.textures.map {
                TextureDefinition(
                    name: $0.name,
                    format: $0.format,
                    width: $0.width,
                    height: $0.height,
                    offset: $0.order,
                    tlutOffset: nil,
                    tlutName: $0.tlutName,
                    pngURL: $0.pngURL,
                    ignoreIfOrphanedTLUT: false
                )
            }.sorted {
                if $0.offset == $1.offset {
                    return $0.name < $1.name
                }
                return $0.offset < $1.offset
            }

            groups.append(
                TextureSourceGroup(
                    xmlURL: xmlURL,
                    sourceName: sourceName,
                    outputSource: sourceName,
                    assetDirectory: assetDirectory,
                    textures: textures,
                    tlutByOffset: tlutByOffset,
                    tlutByName: tlutByName
                )
            )
        }

        return groups
    }

    static func parseTextureDimensions(in headerContents: String) -> [String: (width: Int, height: Int)] {
        let range = NSRange(headerContents.startIndex..<headerContents.endIndex, in: headerContents)
        var widths: [String: Int] = [:]
        var heights: [String: Int] = [:]

        for match in textureDimensionExpression.matches(in: headerContents, range: range) {
            let symbol = substring(in: headerContents, range: match.range(at: 1))
            let axis = substring(in: headerContents, range: match.range(at: 2))
            guard let value = Int(substring(in: headerContents, range: match.range(at: 3))) else {
                continue
            }

            if axis == "WIDTH" {
                widths[symbol] = value
            } else {
                heights[symbol] = value
            }
        }

        var dimensions: [String: (width: Int, height: Int)] = [:]
        for (symbol, width) in widths {
            guard let height = heights[symbol] else {
                continue
            }
            dimensions[symbol] = (width, height)
        }

        return dimensions
    }

    static func parseSourceBackedTextureDeclarations(
        in sourceContents: String,
        dimensionsByName: [String: (width: Int, height: Int)],
        sourceFile: URL,
        sourceRoot: URL,
        fileManager: FileManager
    ) -> (textures: [SourceBackedTextureDeclaration], tluts: [SourceBackedTLUTDeclaration]) {
        let range = NSRange(sourceContents.startIndex..<sourceContents.endIndex, in: sourceContents)
        var textures: [SourceBackedTextureDeclaration] = []
        var tluts: [SourceBackedTLUTDeclaration] = []

        for (index, match) in sourceBackedTextureDefinitionExpression.matches(in: sourceContents, range: range).enumerated() {
            let symbol = substring(in: sourceContents, range: match.range(at: 1))
            let includePath = substring(in: sourceContents, range: match.range(at: 2))

            if let tlut = parseSourceBackedTLUTDeclaration(
                symbol: symbol,
                includePath: includePath,
                order: index
            ) {
                tluts.append(tlut)
                continue
            }

            guard
                let dimension = dimensionsByName[symbol],
                let texture = parseSourceBackedTextureDeclaration(
                    symbol: symbol,
                    includePath: includePath,
                    width: dimension.width,
                    height: dimension.height,
                    order: index,
                    sourceFile: sourceFile,
                    sourceRoot: sourceRoot,
                    fileManager: fileManager
                )
            else {
                continue
            }

            textures.append(texture)
        }

        return (textures, tluts)
    }

    static func parseSourceBackedTLUTDeclaration(
        symbol: String,
        includePath: String,
        order: Int
    ) -> SourceBackedTLUTDeclaration? {
        let basename = URL(fileURLWithPath: includePath).lastPathComponent
        guard let match = firstMatch(in: basename, expression: tlutIncludeExpression) else {
            return nil
        }

        let format = parseTextureFormat(substring(in: basename, range: match.range(at: 1)))
        return SourceBackedTLUTDeclaration(name: symbol, format: format, order: order)
    }

    static func parseSourceBackedTextureDeclaration(
        symbol: String,
        includePath: String,
        width: Int,
        height: Int,
        order: Int,
        sourceFile: URL,
        sourceRoot: URL,
        fileManager: FileManager
    ) -> SourceBackedTextureDeclaration? {
        let basename = URL(fileURLWithPath: includePath).lastPathComponent
        let includeURL = sourceBackedIncludeURL(
            forIncludePath: includePath,
            sourceFile: sourceFile,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        )
        let pngURL = sourceBackedPNGURL(
            forIncludePath: includePath,
            sourceFile: sourceFile,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        )

        if let match = firstMatch(in: basename, expression: textureIncludeWithTLUTExpression) {
            guard let format = parseTextureFormat(substring(in: basename, range: match.range(at: 1))) else {
                return nil
            }

            return SourceBackedTextureDeclaration(
                name: symbol,
                format: format,
                width: width,
                height: height,
                order: order,
                tlutName: substring(in: basename, range: match.range(at: 2)),
                pngURL: pngURL,
                usesMissingIncludeFallback: includeURL == nil && pngURL != nil
            )
        }

        guard let match = firstMatch(in: basename, expression: textureIncludeExpression) else {
            return nil
        }
        guard let format = parseTextureFormat(substring(in: basename, range: match.range(at: 1))) else {
            return nil
        }

        return SourceBackedTextureDeclaration(
            name: symbol,
            format: format,
            width: width,
            height: height,
            order: order,
            tlutName: nil,
            pngURL: pngURL,
            usesMissingIncludeFallback: includeURL == nil && pngURL != nil
        )
    }

    static func parseSourceBackedTextureFallbackDeclaration(
        symbol: String,
        includePath: String,
        sourceFile: URL,
        sourceRoot: URL,
        fileManager: FileManager
    ) -> SourceBackedTextureFallbackDeclaration? {
        let basename = URL(fileURLWithPath: includePath).lastPathComponent
        guard firstMatch(in: basename, expression: tlutIncludeExpression) == nil else {
            return nil
        }

        guard
            firstMatch(in: basename, expression: textureIncludeWithTLUTExpression) != nil ||
                firstMatch(in: basename, expression: textureIncludeExpression) != nil
        else {
            return nil
        }

        let includeURL = sourceBackedIncludeURL(
            forIncludePath: includePath,
            sourceFile: sourceFile,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        )
        let pngURL = sourceBackedPNGURL(
            forIncludePath: includePath,
            sourceFile: sourceFile,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        )

        return SourceBackedTextureFallbackDeclaration(
            name: symbol,
            pngURL: pngURL,
            usesMissingIncludeFallback: includeURL == nil && pngURL != nil
        )
    }

    static func sourceBackedIncludeURL(
        forIncludePath includePath: String,
        sourceFile: URL,
        sourceRoot: URL,
        fileManager: FileManager
    ) -> URL? {
        for root in sourceBackedSearchRoots(
            for: sourceFile,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        ) {
            let candidate = root.appendingPathComponent(includePath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    static func sourceBackedPNGURL(
        forIncludePath includePath: String,
        sourceFile: URL,
        sourceRoot: URL,
        fileManager: FileManager
    ) -> URL? {
        guard includePath.hasSuffix(".inc.c") else {
            return nil
        }

        let pngPath = String(includePath.dropLast(".inc.c".count)) + ".png"
        for root in sourceBackedSearchRoots(
            for: sourceFile,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        ) {
            let candidate = root.appendingPathComponent(pngPath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    static func sourceBackedSearchRoots(
        for sourceFile: URL,
        sourceRoot: URL,
        fileManager: FileManager
    ) -> [URL] {
        var roots: [URL] = []
        if let assetRoot = assetRoot(for: sourceFile) {
            roots.append(assetRoot)
        }
        roots.append(sourceRoot.appendingPathComponent("build", isDirectory: true))
        roots.append(contentsOf: extractedRoots(in: sourceRoot, fileManager: fileManager))
        roots.append(sourceRoot)
        roots.append(sourceFile.deletingLastPathComponent())
        return roots
    }

    static func assetRoot(for fileURL: URL) -> URL? {
        let standardizedPath = fileURL.standardizedFileURL.path
        guard let assetsRange = standardizedPath.range(of: "/assets/") else {
            return nil
        }

        return URL(
            fileURLWithPath: String(standardizedPath[..<assetsRange.lowerBound]),
            isDirectory: true
        )
    }

    static func loadPNGTextureData(
        from pngURL: URL,
        expectedWidth: Int,
        expectedHeight: Int
    ) throws -> Data {
        guard
            let source = CGImageSourceCreateWithURL(pngURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw TextureExtractorError.unreadablePNG(pngURL.path)
        }

        guard image.width == expectedWidth, image.height == expectedHeight else {
            throw TextureExtractorError.invalidPNGDimensions(
                pngURL.path,
                expectedWidth: expectedWidth,
                expectedHeight: expectedHeight,
                actualWidth: image.width,
                actualHeight: image.height
            )
        }

        let bytesPerPixel = 4
        let bytesPerRow = expectedWidth * bytesPerPixel
        var buffer = Data(count: expectedHeight * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let rendered = buffer.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return false
            }

            guard let context = CGContext(
                data: baseAddress,
                width: expectedWidth,
                height: expectedHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: expectedWidth, height: expectedHeight))
            return true
        }

        guard rendered else {
            throw TextureExtractorError.unreadablePNG(pngURL.path)
        }

        return buffer
    }

    static func parseTextureFormat(_ rawValue: String?) -> TextureFormat? {
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

    static func firstMatch(in input: String, expression: NSRegularExpression) -> NSTextCheckingResult? {
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return expression.firstMatch(in: input, range: range)
    }

    static func resolveSourceFile(
        for sourceGroup: TextureSourceGroup,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> URL {
        if let sourceFile = try locateSourceFile(
            named: sourceGroup.sourceName,
            preferredExtensions: ["c", "inc.c"],
            assetDirectory: sourceGroup.assetDirectory,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        ) {
            return sourceFile
        }

        let searchRoots = [
            sourceRoot.appendingPathComponent("build", isDirectory: true),
            sourceRoot,
        ]
        for searchRoot in searchRoots where fileManager.fileExists(atPath: searchRoot.path) {
            if let match = try firstSourceContainingRequiredTextureSymbols(
                for: sourceGroup,
                in: searchRoot,
                fileManager: fileManager
            ) {
                return match
            }
        }

        throw TextureExtractorError.missingSourceFile(sourceGroup.sourceName, sourceGroup.xmlURL.path)
    }

    static func resolveSourceFiles(
        for sourceGroup: TextureSourceGroup,
        requiredSymbols: Set<String>,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        let sourceFiles = try sourceFilesDeclaringSymbols(
            for: sourceGroup,
            requiredSymbols: requiredSymbols,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        )
        guard sourceFiles.isEmpty == false else {
            throw TextureExtractorError.missingSourceFile(sourceGroup.sourceName, sourceGroup.xmlURL.path)
        }
        return sourceFiles
    }

    static func parseTextureArrays(
        in source: String,
        sourceFile: URL,
        requiredArrayNames: Set<String>
    ) throws -> [String: ParsedTextureArray] {
        let sanitized = stripLineComments(from: source)
        let searchRange = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        let matches = arrayExpression.matches(in: sanitized, range: searchRange)
        var arrays: [String: ParsedTextureArray] = [:]

        for match in matches {
            let kindName = substring(in: sanitized, range: match.range(at: 1))
            let name = substring(in: sanitized, range: match.range(at: 2))
            guard requiredArrayNames.contains(name) else {
                continue
            }
            guard let elementKind = IntegerArrayElementKind(rawValue: kindName) else {
                continue
            }

            let braceLocation = match.range.location + match.range.length - 1
            let bodyRange = try matchingBraceRange(
                in: sanitized,
                openingBraceLocation: braceLocation
            )
            let body = substring(in: sanitized, range: bodyRange)
            let values = try splitTopLevel(body).map(parseIntegerExpression)
            arrays[name] = ParsedTextureArray(
                dataSource: try dataSource(
                    from: values,
                    elementKind: elementKind,
                    arrayName: name,
                    sourceFile: sourceFile
                )
            )
        }

        return arrays
    }

    static func applySourceBackedPNGFallbacks(
        to groups: [TextureSourceGroup],
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> [TextureSourceGroup] {
        var fallbackURLsBySourceName: [String: [String: URL]] = [:]
        var enrichedGroups: [TextureSourceGroup] = []
        enrichedGroups.reserveCapacity(groups.count)

        for group in groups {
            let fallbackURLs: [String: URL]
            if let cached = fallbackURLsBySourceName[group.sourceName] {
                fallbackURLs = cached
            } else {
                let resolved = try missingIncludePNGFallbacksByTextureName(
                    for: group,
                    sourceRoot: sourceRoot,
                    fileManager: fileManager
                )
                fallbackURLsBySourceName[group.sourceName] = resolved
                fallbackURLs = resolved
            }

            guard fallbackURLs.isEmpty == false else {
                enrichedGroups.append(group)
                continue
            }

            let textures = group.textures.map { texture in
                guard
                    texture.pngURL == nil,
                    let pngURL = fallbackURLs[texture.name]
                else {
                    return texture
                }

                return TextureDefinition(
                    name: texture.name,
                    format: texture.format,
                    width: texture.width,
                    height: texture.height,
                    offset: texture.offset,
                    tlutOffset: texture.tlutOffset,
                    tlutName: texture.tlutName,
                    pngURL: pngURL,
                    ignoreIfOrphanedTLUT: texture.ignoreIfOrphanedTLUT
                )
            }

            enrichedGroups.append(
                TextureSourceGroup(
                    xmlURL: group.xmlURL,
                    sourceName: group.sourceName,
                    outputSource: group.outputSource,
                    assetDirectory: group.assetDirectory,
                    textures: textures,
                    tlutByOffset: group.tlutByOffset,
                    tlutByName: group.tlutByName
                )
            )
        }

        return enrichedGroups
    }

    static func missingIncludePNGFallbacksByTextureName(
        for sourceGroup: TextureSourceGroup,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> [String: URL] {
        let sourceFiles = try sourceFilesDeclaringSymbols(
            for: sourceGroup,
            requiredSymbols: Set(sourceGroup.textures.map(\.name)),
            sourceRoot: sourceRoot,
            fileManager: fileManager
        )

        return try sourceFiles.reduce(into: [:]) { result, sourceFile in
            let sourceContents = try String(contentsOf: sourceFile, encoding: .utf8)
            let range = NSRange(sourceContents.startIndex..<sourceContents.endIndex, in: sourceContents)

            for match in sourceBackedTextureDefinitionExpression.matches(in: sourceContents, range: range) {
                let symbol = substring(in: sourceContents, range: match.range(at: 1))
                let includePath = substring(in: sourceContents, range: match.range(at: 2))
                guard
                    let texture = parseSourceBackedTextureFallbackDeclaration(
                        symbol: symbol,
                        includePath: includePath,
                        sourceFile: sourceFile,
                        sourceRoot: sourceRoot,
                        fileManager: fileManager
                    ),
                    texture.usesMissingIncludeFallback,
                    let pngURL = texture.pngURL
                else {
                    continue
                }

                result[texture.name] = pngURL
            }
        }
    }

    static func firstSourceContainingRequiredTextureSymbolsInSourceRoot(
        for sourceGroup: TextureSourceGroup,
        sourceRoot: URL,
        fileManager: FileManager
    ) -> URL? {
        let searchRoots =
            [sourceRoot.appendingPathComponent("build", isDirectory: true)]
            + extractedRoots(in: sourceRoot, fileManager: fileManager)
            + [sourceRoot]

        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            if let match = try? firstSourceContainingRequiredTextureSymbols(
                for: sourceGroup,
                in: root,
                fileManager: fileManager
            ) {
                guard match.pathExtension != "h" else {
                    continue
                }
                return match
            }
        }

        return nil
    }

    static func sourceFilesDeclaringSymbols(
        for sourceGroup: TextureSourceGroup,
        requiredSymbols: Set<String>,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        guard requiredSymbols.isEmpty == false else {
            return []
        }

        let directMatches = try findSourceFilesDeclaringTextureSymbols(
            in: directAssetDirectories(
                assetDirectory: sourceGroup.assetDirectory,
                sourceRoot: sourceRoot,
                fileManager: fileManager
            ),
            requiredSymbols: requiredSymbols,
            fileManager: fileManager
        )
        if directMatches.isEmpty == false {
            return directMatches
        }

        let searchRoots =
            [sourceRoot.appendingPathComponent("build", isDirectory: true)]
            + extractedRoots(in: sourceRoot, fileManager: fileManager)
            + [sourceRoot]

        return try findSourceFilesDeclaringTextureSymbols(
            in: searchRoots,
            requiredSymbols: requiredSymbols,
            fileManager: fileManager
        )
    }

    static func findSourceFilesDeclaringTextureSymbols(
        in searchRoots: [URL],
        requiredSymbols: Set<String>,
        fileManager: FileManager
    ) throws -> [URL] {
        var matches: [URL] = []
        var seenPaths: Set<String> = []

        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
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
                guard isCandidateTextureSourceFile(fileURL) else {
                    continue
                }
                guard seenPaths.insert(fileURL.standardizedFileURL.path).inserted else {
                    continue
                }
                guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    continue
                }
                guard requiredSymbols.contains(where: contents.contains) else {
                    continue
                }
                guard declaredTextureSymbols(in: contents).intersection(requiredSymbols).isEmpty == false else {
                    continue
                }

                matches.append(fileURL)
            }
        }

        return matches.sorted { $0.path < $1.path }
    }

    static func dataSource(
        from values: [Int64],
        elementKind: IntegerArrayElementKind,
        arrayName: String,
        sourceFile: URL
    ) throws -> N64TextureDataSource {
        switch elementKind {
        case .s8, .u8:
            return .bytes(
                try values.map {
                    try coerceUnsigned($0, bitWidth: 8, field: arrayName, sourceFile: sourceFile)
                }
            )
        case .s16, .u16:
            return .words(
                try values.map {
                    try coerceUnsigned16($0, field: arrayName, sourceFile: sourceFile)
                }
            )
        case .s32, .u32:
            var data = Data()
            data.reserveCapacity(values.count * 4)
            for value in values {
                data.append(
                    bigEndian: try coerceUnsigned32(value, field: arrayName, sourceFile: sourceFile)
                )
            }
            return .bytes([UInt8](data))
        case .s64, .u64:
            var data = Data()
            data.reserveCapacity(values.count * 8)
            for value in values {
                data.append(
                    bigEndian: try coerceUnsigned64(value, field: arrayName, sourceFile: sourceFile)
                )
            }
            return .bytes([UInt8](data))
        }
    }

    static func coerceUnsigned(
        _ value: Int64,
        bitWidth: Int,
        field: String,
        sourceFile: URL
    ) throws -> UInt8 {
        let coerced = try coerceUnsigned64(value, bitWidth: bitWidth, field: field, sourceFile: sourceFile)
        return UInt8(truncatingIfNeeded: coerced)
    }

    static func coerceUnsigned16(
        _ value: Int64,
        field: String,
        sourceFile: URL
    ) throws -> UInt16 {
        let coerced = try coerceUnsigned64(value, bitWidth: 16, field: field, sourceFile: sourceFile)
        return UInt16(truncatingIfNeeded: coerced)
    }

    static func coerceUnsigned32(
        _ value: Int64,
        field: String,
        sourceFile: URL
    ) throws -> UInt32 {
        let coerced = try coerceUnsigned64(value, bitWidth: 32, field: field, sourceFile: sourceFile)
        return UInt32(truncatingIfNeeded: coerced)
    }

    static func coerceUnsigned64(
        _ value: Int64,
        field: String,
        sourceFile: URL
    ) throws -> UInt64 {
        try coerceUnsigned64(value, bitWidth: 64, field: field, sourceFile: sourceFile)
    }

    static func coerceUnsigned64(
        _ value: Int64,
        bitWidth: Int,
        field: String,
        sourceFile: URL
    ) throws -> UInt64 {
        let unsignedMax = bitWidth == 64 ? UInt64.max : (UInt64(1) << bitWidth) - 1
        if value >= 0 {
            let magnitude = UInt64(value)
            guard magnitude <= unsignedMax else {
                throw TextureExtractorError.integerOutOfRange(
                    value,
                    bitWidth: bitWidth,
                    field: field,
                    sourceFile: sourceFile.path
                )
            }
            return magnitude
        }

        let signedMin = -(Int64(1) << (bitWidth - 1))
        guard value >= signedMin else {
            throw TextureExtractorError.integerOutOfRange(
                value,
                bitWidth: bitWidth,
                field: field,
                sourceFile: sourceFile.path
            )
        }

        return UInt64(bitPattern: value) & unsignedMax
    }

    static func expectedBinaryByteCount(for metadata: TextureAssetMetadata) throws -> Int {
        guard metadata.width > 0, metadata.height > 0 else {
            throw TextureExtractorError.invalidMetadataDimensions(
                metadata.width,
                metadata.height
            )
        }

        let (pixelCount, overflow) = metadata.width.multipliedReportingOverflow(by: metadata.height)
        guard overflow == false else {
            throw TextureExtractorError.invalidMetadataDimensions(metadata.width, metadata.height)
        }

        let texelBytes: Int
        switch metadata.format {
        case .rgba16, .rgba32:
            texelBytes = pixelCount * 4
        case .ci4, .ci8, .i4, .i8:
            texelBytes = pixelCount
        case .ia4, .ia8, .ia16:
            texelBytes = pixelCount * 2
        }

        let tlutBytes: Int
        if metadata.hasTLUT {
            switch metadata.format {
            case .ci4:
                tlutBytes = 16 * 4
            case .ci8:
                tlutBytes = 256 * 4
            default:
                throw TextureExtractorError.unexpectedTLUTMetadata(metadata.format.rawValue)
            }
        } else {
            tlutBytes = 0
        }

        return texelBytes + tlutBytes
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    static func readJSON<T: Decodable>(from url: URL) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
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

    static func firstSourceContainingRequiredTextureSymbols(
        for sourceGroup: TextureSourceGroup,
        in root: URL,
        fileManager: FileManager
    ) throws -> URL? {
        let requiredSymbols = Set(
            sourceGroup.textures.map(\.name)
                + sourceGroup.tlutByOffset.values.map(\.name)
                + sourceGroup.tlutByName.values.map(\.name)
        )
        guard requiredSymbols.isEmpty == false else {
            return nil
        }

        let preferredFilenames = [
            "\(sourceGroup.sourceName).c",
            "\(sourceGroup.sourceName).inc.c",
            "\(sourceGroup.sourceName).h",
        ]
        let preferredHeaderPath = "\(sourceGroup.assetDirectory)/\(sourceGroup.sourceName).h"

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let matches = try enumerator.compactMap { item -> (score: Int, url: URL)? in
            guard let fileURL = item as? URL else {
                return nil
            }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                return nil
            }

            guard isCandidateTextureSourceFile(fileURL) else {
                return nil
            }

            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return nil
            }

            guard requiredSymbols.allSatisfy(contents.contains) else {
                return nil
            }
            guard declaredTextureSymbols(in: contents).contains(where: requiredSymbols.contains) else {
                return nil
            }

            var score = 0
            if preferredFilenames.contains(fileURL.lastPathComponent) {
                score += 4
            }
            if contents.contains(preferredHeaderPath) {
                score += 3
            }
            if contents.contains(sourceGroup.sourceName) {
                score += 2
            }
            if fileURL.path.contains("/src/") {
                score += 1
            }

            return (score, fileURL)
        }

        return matches.max { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.url.path > rhs.url.path
            }
            return lhs.score < rhs.score
        }?.url
    }

    static func isCandidateTextureSourceFile(_ fileURL: URL) -> Bool {
        if fileURL.lastPathComponent.hasSuffix(".inc.c") {
            return true
        }

        switch fileURL.pathExtension {
        case "c", "h":
            return true
        default:
            return false
        }
    }

    static func declaredTextureSymbols(in source: String) -> Set<String> {
        let sanitized = stripLineComments(from: source)
        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let sanitizedRange = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)

        let includeBackedSymbols = sourceBackedTextureDefinitionExpression.matches(in: source, range: sourceRange).map {
            substring(in: source, range: $0.range(at: 1))
        }
        let inlineArraySymbols = arrayExpression.matches(in: sanitized, range: sanitizedRange).map {
            substring(in: sanitized, range: $0.range(at: 2))
        }

        return Set(includeBackedSymbols + inlineArraySymbols)
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

        throw TextureExtractorError.unterminatedArray
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

    static func substring(in text: String, range: NSRange) -> String {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
            return ""
        }
        return String(text[swiftRange])
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
            let match = try? NSRegularExpression(pattern: #"/\*\s*(0[xX][0-9A-Fa-f]+)\s*\*/"#)
                .firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed))
        {
            return try parseIntegerLiteral(substring(in: trimmed, range: match.range(at: 1)))
        }

        return try parseIntegerLiteral(trimmed)
    }

    static func parseIntegerLiteral(_ literal: String) throws -> Int64 {
        let trimmed = trimExpression(literal)
        guard trimmed.isEmpty == false else {
            throw TextureExtractorError.invalidIntegerLiteral(literal)
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
            throw TextureExtractorError.invalidIntegerLiteral(literal)
        }

        if sign == -1 {
            guard magnitude <= UInt64(Int64.max) + 1 else {
                throw TextureExtractorError.invalidIntegerLiteral(literal)
            }
            if magnitude == UInt64(Int64.max) + 1 {
                return Int64.min
            }
            return -Int64(magnitude)
        }

        guard magnitude <= UInt64(Int64.max) else {
            throw TextureExtractorError.invalidIntegerLiteral(literal)
        }

        return Int64(magnitude)
    }

    static func trimExpression(_ expression: String) -> String {
        expression.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum TextureExtractorError: LocalizedError {
    case textureDecodingFailed(String, String, String)
    case invalidBinarySize(String, expected: Int, actual: Int)
    case invalidIntegerLiteral(String)
    case invalidMetadataDimensions(Int, Int)
    case invalidPNGDimensions(String, expectedWidth: Int, expectedHeight: Int, actualWidth: Int, actualHeight: Int)
    case invalidXML(String, String)
    case integerOutOfRange(Int64, bitWidth: Int, field: String, sourceFile: String)
    case missingArray(String, String)
    case missingSourceFile(String, String)
    case missingTextureBinary(String)
    case missingNamedTLUTDefinition(String, String, String)
    case missingTLUTDefinition(String, Int, String)
    case unreadablePNG(String)
    case unterminatedArray
    case unexpectedTLUTMetadata(String)

    var errorDescription: String? {
        switch self {
        case .textureDecodingFailed(let textureName, let sourceName, let message):
            return "Failed to decode texture '\(textureName)' from source '\(sourceName)': \(message)"
        case .invalidBinarySize(let path, let expected, let actual):
            return "Texture binary '\(path)' has size \(actual), expected \(expected) bytes."
        case .invalidIntegerLiteral(let literal):
            return "Unsupported integer literal: \(literal)"
        case .invalidMetadataDimensions(let width, let height):
            return "Texture metadata has invalid dimensions \(width)x\(height)."
        case .invalidPNGDimensions(let path, let expectedWidth, let expectedHeight, let actualWidth, let actualHeight):
            return "PNG texture '\(path)' has size \(actualWidth)x\(actualHeight), expected \(expectedWidth)x\(expectedHeight)."
        case .invalidXML(let path, let message):
            return "Failed to parse texture XML '\(path)': \(message)"
        case .integerOutOfRange(let value, let bitWidth, let field, let sourceFile):
            return "Value '\(value)' for array '\(field)' in '\(sourceFile)' does not fit \(bitWidth) bits."
        case .missingArray(let name, let sourceFile):
            return "Texture array '\(name)' was not found in '\(sourceFile)'."
        case .missingSourceFile(let sourceName, let xmlPath):
            return "Texture source '\(sourceName)' referenced by '\(xmlPath)' could not be resolved."
        case .missingTextureBinary(let path):
            return "Missing texture binary: \(path)"
        case .missingNamedTLUTDefinition(let textureName, let tlutName, let xmlPath):
            return "Texture '\(textureName)' references TLUT '\(tlutName)' that is not defined in '\(xmlPath)'."
        case .missingTLUTDefinition(let textureName, let offset, let xmlPath):
            return "Texture '\(textureName)' references TLUT offset \(String(format: "0x%X", offset)) that is not defined in '\(xmlPath)'."
        case .unreadablePNG(let path):
            return "PNG texture asset '\(path)' could not be decoded."
        case .unterminatedArray:
            return "Encountered an unterminated C array while parsing texture data."
        case .unexpectedTLUTMetadata(let format):
            return "Texture metadata reports TLUT data for unsupported format '\(format)'."
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

private extension Data {
    mutating func append<T: FixedWidthInteger>(bigEndian value: T) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { buffer in
            append(contentsOf: buffer)
        }
    }
}

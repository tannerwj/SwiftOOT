import Foundation
import OOTDataModel

extension TextureExtractor {
    public func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let sourceGroups = try Self.loadTextureSourceGroups(
            in: context.source,
            sceneName: context.sceneName,
            fileManager: fileManager
        )
        let decoder = N64TextureDecoder()
        var emittedTextures = 0

        for sourceGroup in sourceGroups {
            let sourceFile = try Self.resolveSourceFile(
                for: sourceGroup,
                sourceRoot: context.source,
                fileManager: fileManager
            )
            let expandedSource = try CMacroPreprocessor().preprocess(
                fileURL: sourceFile,
                sourceRoot: context.source
            )
            let arrays = try Self.parseTextureArrays(in: expandedSource, sourceFile: sourceFile)
            let outputDirectory = context.output
                .appendingPathComponent("Textures", isDirectory: true)
                .appendingPathComponent(sourceGroup.outputSource, isDirectory: true)
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            for texture in sourceGroup.textures {
                guard let textureArray = arrays[texture.name] else {
                    throw TextureExtractorError.missingArray(texture.name, sourceFile.path)
                }

                let tlutDataSource: N64TextureDataSource?
                let tlutFormat: TextureFormat?
                if let tlutOffset = texture.tlutOffset {
                    guard let tlut = sourceGroup.tlutByOffset[tlutOffset] else {
                        throw TextureExtractorError.missingTLUTDefinition(
                            texture.name,
                            tlutOffset,
                            sourceGroup.xmlURL.path
                        )
                    }
                    guard let tlutArray = arrays[tlut.name] else {
                        throw TextureExtractorError.missingArray(tlut.name, sourceFile.path)
                    }

                    tlutDataSource = tlutArray.dataSource
                    tlutFormat = tlut.format
                } else {
                    tlutDataSource = nil
                    tlutFormat = nil
                }

                let decoded = try decoder.decode(
                    format: texture.format,
                    width: texture.width,
                    height: texture.height,
                    texelData: textureArray.dataSource,
                    tlutData: tlutDataSource,
                    tlutFormat: tlutFormat
                )

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
    }

    struct TextureDefinition: Sendable {
        let name: String
        let format: TextureFormat
        let width: Int
        let height: Int
        let offset: Int
        let tlutOffset: Int?
    }

    struct TLUTDefinition: Sendable {
        let name: String
        let format: TextureFormat?
        let offset: Int
    }

    struct ParsedTextureArray: Sendable {
        let dataSource: N64TextureDataSource
    }

    enum AssetKind {
        case object
        case scene
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

    final class TextureXMLParserDelegate: NSObject, XMLParserDelegate {
        private let defaultSourceName: String
        private(set) var groupedTextures: [String: [TextureDefinition]] = [:]
        private(set) var groupedTLUTs: [String: [TLUTDefinition]] = [:]
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
            case "Texture":
                guard
                    let name = attributeDict["Name"],
                    let format = Self.parseTextureFormat(attributeDict["Format"]),
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
                        tlutOffset: Self.parseInteger(attributeDict["TlutOffset"])
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
                        format: Self.parseTextureFormat(attributeDict["Format"]),
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

    static let arrayExpression = try! NSRegularExpression(
        pattern: #"(?:^|\s)(?:static\s+)?(?:(?:const|volatile)\s+)*(s8|u8|s16|u16|s32|u32|s64|u64)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{"#,
        options: [.anchorsMatchLines]
    )

    static func loadTextureSourceGroups(
        in sourceRoot: URL,
        sceneName: String?,
        fileManager: FileManager
    ) throws -> [TextureSourceGroup] {
        var groups: [TextureSourceGroup] = []

        if sceneName == nil {
            groups.append(contentsOf: try loadTextureSourceGroups(
                in: sourceRoot,
                xmlSubdirectory: "assets/xml/objects",
                assetSubdirectory: "assets/objects",
                kind: .object,
                sceneName: nil,
                fileManager: fileManager
            ))
        }

        groups.append(contentsOf: try loadTextureSourceGroups(
            in: sourceRoot,
            xmlSubdirectory: "assets/xml/scenes",
            assetSubdirectory: "assets/scenes",
            kind: .scene,
            sceneName: sceneName,
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
        sceneName: String?,
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
            if let sceneName, kind == .scene, xmlURL.deletingPathExtension().lastPathComponent != sceneName {
                continue
            }

            groups.append(contentsOf: try parseTextureSourceGroups(
                from: xmlURL,
                xmlRoot: xmlRoot,
                assetSubdirectory: assetSubdirectory
            ))
        }

        return groups
    }

    static func parseTextureSourceGroups(
        from xmlURL: URL,
        xmlRoot: URL,
        assetSubdirectory: String
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

        var groups: [TextureSourceGroup] = []
        for (sourceName, textures) in delegate.groupedTextures {
            let tluts = delegate.groupedTLUTs[sourceName] ?? []
            let tlutByOffset = Dictionary(tluts.map { ($0.offset, $0) }, uniquingKeysWith: { current, _ in current })
            let assetDirectory = [assetSubdirectory, xmlRelativeDirectory, defaultSourceName]
                .filter { $0.isEmpty == false }
                .joined(separator: "/")
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
                    tlutByOffset: tlutByOffset
                )
            )
        }

        return groups.sorted { $0.sourceName < $1.sourceName }
    }

    static func resolveSourceFile(
        for sourceGroup: TextureSourceGroup,
        sourceRoot: URL,
        fileManager: FileManager
    ) throws -> URL {
        let directDirectories = [
            sourceRoot.appendingPathComponent("build", isDirectory: true).appendingPathComponent(sourceGroup.assetDirectory, isDirectory: true),
            sourceRoot.appendingPathComponent(sourceGroup.assetDirectory, isDirectory: true),
        ]
        let candidateBasenames = [sourceGroup.sourceName]
        let preferredExtensions = ["c", "inc.c"]

        for directory in directDirectories where fileManager.fileExists(atPath: directory.path) {
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

        throw TextureExtractorError.missingSourceFile(sourceGroup.sourceName, sourceGroup.xmlURL.path)
    }

    static func parseTextureArrays(
        in source: String,
        sourceFile: URL
    ) throws -> [String: ParsedTextureArray] {
        let sanitized = stripLineComments(from: source)
        let searchRange = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        let matches = arrayExpression.matches(in: sanitized, range: searchRange)
        var arrays: [String: ParsedTextureArray] = [:]

        for match in matches {
            let kindName = substring(in: sanitized, range: match.range(at: 1))
            let name = substring(in: sanitized, range: match.range(at: 2))
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
    case invalidBinarySize(String, expected: Int, actual: Int)
    case invalidIntegerLiteral(String)
    case invalidMetadataDimensions(Int, Int)
    case invalidXML(String, String)
    case integerOutOfRange(Int64, bitWidth: Int, field: String, sourceFile: String)
    case missingArray(String, String)
    case missingSourceFile(String, String)
    case missingTextureBinary(String)
    case missingTLUTDefinition(String, Int, String)
    case unterminatedArray
    case unexpectedTLUTMetadata(String)

    var errorDescription: String? {
        switch self {
        case .invalidBinarySize(let path, let expected, let actual):
            return "Texture binary '\(path)' has size \(actual), expected \(expected) bytes."
        case .invalidIntegerLiteral(let literal):
            return "Unsupported integer literal: \(literal)"
        case .invalidMetadataDimensions(let width, let height):
            return "Texture metadata has invalid dimensions \(width)x\(height)."
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
        case .missingTLUTDefinition(let textureName, let offset, let xmlPath):
            return "Texture '\(textureName)' references TLUT offset \(String(format: "0x%X", offset)) that is not defined in '\(xmlPath)'."
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

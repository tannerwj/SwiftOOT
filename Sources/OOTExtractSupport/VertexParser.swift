import Foundation
import OOTDataModel

extension VertexParser {
    public func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let sourceFiles = try Self.vertexSourceFiles(in: context.source, fileManager: fileManager)
        var extractedArrays = 0

        for sourceFile in sourceFiles {
            let contents = try String(contentsOf: sourceFile, encoding: .utf8)
            let arrays = try Self.parseVertexArrays(in: contents)
            guard arrays.isEmpty == false else {
                continue
            }

            let outputDirectory = try Self.outputDirectory(
                for: sourceFile,
                sourceRoot: context.source,
                outputRoot: context.output
            )
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            for array in arrays {
                let outputURL = outputDirectory.appendingPathComponent("\(array.name).vtx.bin")
                try Self.encode(array.vertices).write(to: outputURL, options: .atomic)
                extractedArrays += 1
            }
        }

        print("[\(name)] extracted \(extractedArrays) vertex array(s)")
    }

    public func verify(using context: OOTVerificationContext) throws {
        let fileManager = FileManager.default
        let vertexFiles = try Self.vertexBinaryFiles(in: context.content, fileManager: fileManager)

        for vertexFile in vertexFiles {
            let fileSize = try Self.fileSize(of: vertexFile)
            guard fileSize.isMultiple(of: MemoryLayout<N64Vertex>.size) else {
                throw VertexParserError.invalidBinarySize(vertexFile.path, fileSize)
            }
        }

        print("[\(name)] verified \(vertexFiles.count) vertex binary file(s)")
    }
}

private extension VertexParser {
    struct ParsedVertexArray {
        let name: String
        let vertices: [N64Vertex]
    }

    static let integerPattern = #"([+-]?(?:0[xX][0-9A-Fa-f]+|\d+))"#

    static let arrayExpression = try! NSRegularExpression(
        pattern: #"(?:static\s+)?Vtx\s+([A-Za-z_][A-Za-z0-9_]*)\s*\[[^\]]*\]\s*=\s*\{(.*?)\};"#,
        options: [.dotMatchesLineSeparators]
    )

    static let vertexExpression = try! NSRegularExpression(
        pattern: #"VTX\(\s*\#(integerPattern),\s*\#(integerPattern),\s*\#(integerPattern),\s*\#(integerPattern),\s*\#(integerPattern),\s*\#(integerPattern),\s*\#(integerPattern),\s*\#(integerPattern),\s*\#(integerPattern),\s*\#(integerPattern)\s*\)"#
    )

    static func vertexSourceFiles(in root: URL, fileManager: FileManager) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sourceFiles: [URL] = []

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else {
                continue
            }

            guard fileURL.lastPathComponent.hasSuffix(".inc.c") else {
                continue
            }

            sourceFiles.append(fileURL)
        }

        return sourceFiles.sorted { $0.path < $1.path }
    }

    static func vertexBinaryFiles(in root: URL, fileManager: FileManager) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var vertexFiles: [URL] = []

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else {
                continue
            }

            guard fileURL.lastPathComponent.hasSuffix(".vtx.bin") else {
                continue
            }

            vertexFiles.append(fileURL)
        }

        return vertexFiles.sorted { $0.path < $1.path }
    }

    static func parseVertexArrays(in contents: String) throws -> [ParsedVertexArray] {
        let searchRange = NSRange(contents.startIndex..<contents.endIndex, in: contents)

        return try arrayExpression.matches(in: contents, range: searchRange).map { match in
            let name = try capturedGroup(1, from: match, in: contents)
            let body = try capturedGroup(2, from: match, in: contents)
            let vertices = try parseVertices(in: body)

            guard vertices.isEmpty == false else {
                throw VertexParserError.emptyVertexArray(name)
            }

            return ParsedVertexArray(name: name, vertices: vertices)
        }
    }

    static func parseVertices(in body: String) throws -> [N64Vertex] {
        let searchRange = NSRange(body.startIndex..<body.endIndex, in: body)

        return try vertexExpression.matches(in: body, range: searchRange).map { match in
            let values = try (1...10).map { index in
                try parseIntegerLiteral(capturedGroup(index, from: match, in: body))
            }

            let color = RGBA8(
                red: try parseUInt8(values[6], field: "r"),
                green: try parseUInt8(values[7], field: "g"),
                blue: try parseUInt8(values[8], field: "b"),
                alpha: try parseUInt8(values[9], field: "a")
            )

            return N64Vertex(
                position: Vector3s(
                    x: try parseSigned16(values[0], field: "x"),
                    y: try parseSigned16(values[1], field: "y"),
                    z: try parseSigned16(values[2], field: "z")
                ),
                flag: try parseUnsigned16(values[3], field: "flag"),
                textureCoordinate: Vector2s(
                    x: try parseSigned16(values[4], field: "u"),
                    y: try parseSigned16(values[5], field: "v")
                ),
                colorOrNormal: color
            )
        }
    }

    static func parseIntegerLiteral(_ literal: String) throws -> Int64 {
        let trimmed = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw VertexParserError.invalidIntegerLiteral(literal)
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
            throw VertexParserError.invalidIntegerLiteral(literal)
        }

        if sign == -1 {
            guard magnitude <= UInt64(Int64.max) + 1 else {
                throw VertexParserError.invalidIntegerLiteral(literal)
            }

            if magnitude == UInt64(Int64.max) + 1 {
                return Int64.min
            }

            return -Int64(magnitude)
        }

        guard magnitude <= UInt64(Int64.max) else {
            throw VertexParserError.invalidIntegerLiteral(literal)
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

        throw VertexParserError.valueOutOfRange(field, String(value), "signed 16-bit")
    }

    static func parseUnsigned16(_ value: Int64, field: String) throws -> UInt16 {
        if 0...Int64(UInt16.max) ~= value {
            return UInt16(value)
        }

        if Int64(Int16.min)...Int64(Int16.max) ~= value {
            return UInt16(truncatingIfNeeded: value)
        }

        throw VertexParserError.valueOutOfRange(field, String(value), "unsigned 16-bit")
    }

    static func parseUInt8(_ value: Int64, field: String) throws -> UInt8 {
        guard 0...Int64(UInt8.max) ~= value else {
            throw VertexParserError.valueOutOfRange(field, String(value), "unsigned 8-bit")
        }

        return UInt8(value)
    }

    static func encode(_ vertices: [N64Vertex]) -> Data {
        var data = Data()
        data.reserveCapacity(vertices.count * MemoryLayout<N64Vertex>.size)

        for vertex in vertices {
            data.append(bigEndian: vertex.position.x)
            data.append(bigEndian: vertex.position.y)
            data.append(bigEndian: vertex.position.z)
            data.append(bigEndian: vertex.flag)
            data.append(bigEndian: vertex.textureCoordinate.x)
            data.append(bigEndian: vertex.textureCoordinate.y)
            data.append(contentsOf: [
                vertex.colorOrNormal.red,
                vertex.colorOrNormal.green,
                vertex.colorOrNormal.blue,
                vertex.colorOrNormal.alpha,
            ])
        }

        return data
    }

    static func outputDirectory(for sourceFile: URL, sourceRoot: URL, outputRoot: URL) throws -> URL {
        let rootPath = sourceRoot.standardizedFileURL.path
        let directoryPath = sourceFile.deletingLastPathComponent().standardizedFileURL.path

        guard directoryPath.hasPrefix(rootPath) else {
            throw VertexParserError.sourceOutsideRoot(sourceFile.path, sourceRoot.path)
        }

        let relativeDirectory = String(directoryPath.dropFirst(rootPath.count)).trimmingPrefix("/")
        guard relativeDirectory.isEmpty == false else {
            return outputRoot
        }

        return outputRoot.appendingPathComponent(relativeDirectory, isDirectory: true)
    }

    static func capturedGroup(_ index: Int, from match: NSTextCheckingResult, in string: String) throws -> String {
        guard let range = Range(match.range(at: index), in: string) else {
            throw VertexParserError.invalidCapture(index)
        }

        return String(string[range])
    }

    static func fileSize(of fileURL: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw VertexParserError.missingFileSize(fileURL.path)
        }

        return fileSize.intValue
    }
}

private enum VertexParserError: LocalizedError {
    case emptyVertexArray(String)
    case invalidBinarySize(String, Int)
    case invalidCapture(Int)
    case invalidIntegerLiteral(String)
    case missingFileSize(String)
    case sourceOutsideRoot(String, String)
    case valueOutOfRange(String, String, String)

    var errorDescription: String? {
        switch self {
        case .emptyVertexArray(let name):
            return "Vertex array '\(name)' did not contain any VTX macros."
        case .invalidBinarySize(let path, let size):
            return "Vertex binary '\(path)' has size \(size), which is not a multiple of 16 bytes."
        case .invalidCapture(let index):
            return "Failed to read regex capture group \(index)."
        case .invalidIntegerLiteral(let literal):
            return "Unsupported integer literal: \(literal)"
        case .missingFileSize(let path):
            return "Missing file size for path: \(path)"
        case .sourceOutsideRoot(let path, let root):
            return "Source path '\(path)' is not contained within source root '\(root)'."
        case .valueOutOfRange(let field, let literal, let expectedType):
            return "Value '\(literal)' for field '\(field)' does not fit \(expectedType)."
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

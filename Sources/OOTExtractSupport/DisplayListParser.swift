import Foundation
import OOTDataModel

struct DisplayListParser: OOTExtractionPipelineComponent {
    let name = "DisplayListParser"

    private let preprocessor: CMacroPreprocessor

    init(preprocessor: CMacroPreprocessor = CMacroPreprocessor()) {
        self.preprocessor = preprocessor
    }

    func extract(using context: OOTExtractionContext) throws {
        let fileManager = FileManager.default
        let files = try candidateFiles(in: context.source)
        let outputDirectory = context.output.appendingPathComponent("DisplayLists", isDirectory: true)
        var emittedCount = 0
        var skippedSourceCount = 0

        for fileURL in files {
            let displayLists: [ParsedDisplayList]
            do {
                displayLists = try parseDisplayLists(in: fileURL, sourceRoot: context.source)
            } catch let error as DisplayListParserError where error.isSkippableSourceFailure {
                skippedSourceCount += 1
                print("[\(name)] skipped \(relativePath(for: fileURL, sourceRoot: context.source)): \(error.localizedDescription)")
                continue
            }
            guard !displayLists.isEmpty else {
                continue
            }

            let relativeDirectory = relativeSourceDirectory(for: fileURL, sourceRoot: context.source)
            let destinationDirectory = relativeDirectory.map {
                outputDirectory.appendingPathComponent($0, isDirectory: true)
            } ?? outputDirectory
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            for displayList in displayLists {
                let destination = destinationDirectory.appendingPathComponent("\(displayList.name).json")
                let data = try encoder.encode(displayList.commands)
                try data.write(to: destination, options: .atomic)
                emittedCount += 1
            }
        }

        print("[\(name)] emitted \(emittedCount) display list JSON file(s)")
        if skippedSourceCount > 0 {
            print("[\(name)] skipped \(skippedSourceCount) source file(s) with unsupported or missing include-backed display lists")
        }
    }

    func parseDisplayLists(in fileURL: URL, sourceRoot: URL) throws -> [ParsedDisplayList] {
        let expandedSource = try preprocessor.preprocess(fileURL: fileURL, sourceRoot: sourceRoot)
        let arrays = try parseArrays(in: expandedSource)

        return try arrays.map { array in
            let commands: [F3DEX2Command]
            do {
                commands = try parseCommands(in: array.body)
            } catch let error as DisplayListParserError where error.isSkippableSourceFailure {
                throw error
            } catch {
                print("[\(name)] failed to parse display list array \(array.name) in \(fileURL.path): \(error.localizedDescription)")
                throw error
            }
            return ParsedDisplayList(name: array.name, commands: commands)
        }
    }

    static func stableID(for symbol: String) -> UInt32 {
        let normalized = symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "")

        var hash: UInt32 = 2_166_136_261
        for byte in normalized.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return hash
    }

    private func candidateFiles(in sourceRoot: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }

            let path = fileURL.path
            guard path.hasSuffix(".c") || path.hasSuffix(".inc.c") else {
                continue
            }

            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            guard contents.contains("Gfx"), contents.contains("gs") || contents.contains("#include") else {
                continue
            }

            files.append(fileURL)
        }

        return files.sorted { $0.path < $1.path }
    }

    private func relativeSourceDirectory(for fileURL: URL, sourceRoot: URL) -> String? {
        let relative = fileURL.deletingLastPathComponent().path.replacingOccurrences(of: sourceRoot.path, with: "")
        let trimmed = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }

    private func relativePath(for fileURL: URL, sourceRoot: URL) -> String {
        fileURL.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
    }

    private func parseArrays(in source: String) throws -> [DisplayListArray] {
        let pattern = #"(?:^|\s)(?:static\s+)?Gfx\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*=\s*\{"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let sourceNSString = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: sourceNSString.length))

        return try matches.map { match in
            let nameRange = match.range(at: 1)
            let name = sourceNSString.substring(with: nameRange)
            let braceLocation = match.range.location + match.range.length - 1
            let bodyRange = try matchingBraceRange(in: source, openingBraceLocation: braceLocation)
            let body = sourceNSString.substring(with: bodyRange)
            return DisplayListArray(name: name, body: body)
        }
    }

    private func matchingBraceRange(in source: String, openingBraceLocation: Int) throws -> NSRange {
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

        throw DisplayListParserError.unterminatedArray
    }

    private func parseCommands(in body: String) throws -> [F3DEX2Command] {
        let invocations = try MacroInvocation.parseAll(in: body)
        var commands: [F3DEX2Command] = []
        for invocation in invocations {
            if let expandedCommands = try expandCommand(from: invocation) {
                commands.append(contentsOf: expandedCommands)
            } else {
                commands.append(try buildCommand(from: invocation))
            }
        }
        return commands
    }

    private func expandCommand(from invocation: MacroInvocation) throws -> [F3DEX2Command]? {
        switch invocation.name {
        case "__SWIFTOOT_gsDPLoadTextureBlock":
            try invocation.requireCount(12)
            return try expandLoadTextureBlock(
                address: parseAddress(invocation.arguments[0]),
                formatExpression: invocation.arguments[1],
                texelSizeExpression: invocation.arguments[2],
                widthExpression: invocation.arguments[3],
                heightExpression: invocation.arguments[4],
                tmemExpression: "0",
                tileExpression: "0",
                paletteExpression: invocation.arguments[5],
                wrapSExpression: invocation.arguments[6],
                wrapTExpression: invocation.arguments[7],
                maskSExpression: invocation.arguments[8],
                maskTExpression: invocation.arguments[9],
                shiftSExpression: invocation.arguments[10],
                shiftTExpression: invocation.arguments[11]
            )
        case "__SWIFTOOT_gsDPLoadMultiBlock":
            try invocation.requireCount(14)
            return try expandLoadTextureBlock(
                address: parseAddress(invocation.arguments[0]),
                formatExpression: invocation.arguments[3],
                texelSizeExpression: invocation.arguments[4],
                widthExpression: invocation.arguments[5],
                heightExpression: invocation.arguments[6],
                tmemExpression: invocation.arguments[1],
                tileExpression: invocation.arguments[2],
                paletteExpression: invocation.arguments[7],
                wrapSExpression: invocation.arguments[8],
                wrapTExpression: invocation.arguments[9],
                maskSExpression: invocation.arguments[10],
                maskTExpression: invocation.arguments[11],
                shiftSExpression: invocation.arguments[12],
                shiftTExpression: invocation.arguments[13]
            )
        case "__SWIFTOOT_gsDPLoadTextureBlock_4b":
            try invocation.requireCount(11)
            return try expandLoadTextureBlock4b(
                address: parseAddress(invocation.arguments[0]),
                formatExpression: invocation.arguments[1],
                widthExpression: invocation.arguments[2],
                heightExpression: invocation.arguments[3],
                paletteExpression: invocation.arguments[4],
                wrapSExpression: invocation.arguments[5],
                wrapTExpression: invocation.arguments[6],
                maskSExpression: invocation.arguments[7],
                maskTExpression: invocation.arguments[8],
                shiftSExpression: invocation.arguments[9],
                shiftTExpression: invocation.arguments[10]
            )
        case "__SWIFTOOT_gsDPLoadMultiBlock_4b":
            try invocation.requireCount(13)
            return try expandLoadTextureBlock4b(
                address: parseAddress(invocation.arguments[0]),
                formatExpression: invocation.arguments[3],
                widthExpression: invocation.arguments[4],
                heightExpression: invocation.arguments[5],
                paletteExpression: invocation.arguments[6],
                wrapSExpression: invocation.arguments[7],
                wrapTExpression: invocation.arguments[8],
                maskSExpression: invocation.arguments[9],
                maskTExpression: invocation.arguments[10],
                shiftSExpression: invocation.arguments[11],
                shiftTExpression: invocation.arguments[12],
                tmemExpression: invocation.arguments[1],
                tileExpression: invocation.arguments[2]
            )
        case "__SWIFTOOT_gsDPLoadTLUT_pal256":
            try invocation.requireCount(1)
            let address = try parseAddress(invocation.arguments[0])
            return [
                .dpSetTextureImage(
                    ImageDescriptor(
                        format: .rgba16,
                        texelSize: .bits16,
                        width: 1,
                        address: address
                    )
                ),
                .dpTileSync,
                .dpLoadSync,
                .dpLoadTLUT(LoadTLUTCommand(tile: 7, colorCount: 255)),
                .dpPipeSync,
            ]
        case "__SWIFTOOT_gsDPLoadTLUT_pal16":
            try invocation.requireCount(2)
            let palette = try parseUInt16(invocation.arguments[0])
            let address = try parseAddress(invocation.arguments[1])
            return [
                .dpSetTextureImage(
                    ImageDescriptor(
                        format: .rgba16,
                        texelSize: .bits16,
                        width: 1,
                        address: address
                    )
                ),
                .dpTileSync,
                .dpSetTile(
                    makeTileDescriptor(
                        format: .rgba16,
                        texelSize: .bits16,
                        line: 0,
                        tmem: UInt16(256 + ((Int(palette & 0x000F)) * 16)),
                        tile: 7,
                        palette: 0,
                        wrapS: 0,
                        wrapT: 0,
                        maskS: 0,
                        maskT: 0,
                        shiftS: 0,
                        shiftT: 0
                    )
                ),
                .dpLoadSync,
                .dpLoadTLUT(LoadTLUTCommand(tile: 7, colorCount: 15)),
                .dpPipeSync,
            ]
        default:
            return nil
        }
    }

    private func buildCommand(from invocation: MacroInvocation) throws -> F3DEX2Command {
        switch invocation.name {
        case "__SWIFTOOT_gsSPVertex":
            try invocation.requireCount(3)
            return .spVertex(
                VertexCommand(
                    address: try parseAddress(invocation.arguments[0]),
                    count: try parseUInt16(invocation.arguments[1]),
                    destinationIndex: try parseUInt16(invocation.arguments[2])
                )
            )
        case "__SWIFTOOT_gsSP1Triangle":
            try invocation.requireCount(4)
            return .sp1Triangle(
                TriangleCommand(
                    vertex0: try parseUInt8(invocation.arguments[0]),
                    vertex1: try parseUInt8(invocation.arguments[1]),
                    vertex2: try parseUInt8(invocation.arguments[2]),
                    flag: try parseUInt8(invocation.arguments[3])
                )
            )
        case "__SWIFTOOT_gsSP2Triangles":
            try invocation.requireCount(8)
            return .sp2Triangles(
                TrianglePairCommand(
                    first: TriangleCommand(
                        vertex0: try parseUInt8(invocation.arguments[0]),
                        vertex1: try parseUInt8(invocation.arguments[1]),
                        vertex2: try parseUInt8(invocation.arguments[2]),
                        flag: try parseUInt8(invocation.arguments[3])
                    ),
                    second: TriangleCommand(
                        vertex0: try parseUInt8(invocation.arguments[4]),
                        vertex1: try parseUInt8(invocation.arguments[5]),
                        vertex2: try parseUInt8(invocation.arguments[6]),
                        flag: try parseUInt8(invocation.arguments[7])
                    )
                )
            )
        case "__SWIFTOOT_gsSPCullDisplayList":
            try invocation.requireCount(2)
            return .spCullDisplayList(
                CullDisplayListCommand(
                    firstVertex: try parseUInt16(invocation.arguments[0]),
                    lastVertex: try parseUInt16(invocation.arguments[1])
                )
            )
        case "__SWIFTOOT_gsSPDisplayList":
            try invocation.requireCount(1)
            return .spDisplayList(try parseAddress(invocation.arguments[0]))
        case "__SWIFTOOT_gsSPBranchList", "__SWIFTOOT_gsSPBranchDL":
            try invocation.requireCount(1)
            return .spBranchList(try parseAddress(invocation.arguments[0]))
        case "__SWIFTOOT_gsSPBranchLessZraw":
            try invocation.requireCount(3)
            return .spBranchLessZ(
                BranchLessZCommand(
                    branchAddress: try parseAddress(invocation.arguments[0]),
                    vertexIndex: try parseUInt16(invocation.arguments[1]),
                    zValue: try parseUInt32(invocation.arguments[2])
                )
            )
        case "__SWIFTOOT_gsSPEndDisplayList":
            try invocation.requireCount(0)
            return .spEndDisplayList
        case "__SWIFTOOT_gsSPMatrix":
            try invocation.requireCount(2)
            let flags = try parseUInt32(invocation.arguments[1])
            return .spMatrix(
                MatrixCommand(
                    address: try parseAddress(invocation.arguments[0]),
                    projection: (flags & 0x04) != 0,
                    load: (flags & 0x02) != 0,
                    push: (flags & 0x01) != 0
                )
            )
        case "__SWIFTOOT_gsSPPopMatrix":
            try invocation.requireCount(1)
            return .spPopMatrix(try parseUInt8(invocation.arguments[0]))
        case "__SWIFTOOT_gsSPTexture":
            try invocation.requireCount(5)
            return .spTexture(
                TextureState(
                    scaleS: try parseUInt16(invocation.arguments[0]),
                    scaleT: try parseUInt16(invocation.arguments[1]),
                    level: try parseUInt8(invocation.arguments[2]),
                    tile: try parseUInt8(invocation.arguments[3]),
                    enabled: try parseUInt8(invocation.arguments[4]) != 0
                )
            )
        case "__SWIFTOOT_gsDPSetTextureImage":
            try invocation.requireCount(4)
            return .dpSetTextureImage(
                ImageDescriptor(
                    format: try parseTextureFormat(format: invocation.arguments[0], texelSize: invocation.arguments[1]),
                    texelSize: try parseTexelSize(invocation.arguments[1]),
                    width: try parseUInt16(invocation.arguments[2]),
                    address: try parseAddress(invocation.arguments[3])
                )
            )
        case "__SWIFTOOT_gsDPLoadBlock":
            try invocation.requireCount(5)
            return .dpLoadBlock(
                LoadBlockCommand(
                    tile: try parseUInt8(invocation.arguments[0]),
                    upperLeftS: try parseUInt16(invocation.arguments[1]),
                    upperLeftT: try parseUInt16(invocation.arguments[2]),
                    texelCount: try parseUInt16(invocation.arguments[3]),
                    dxt: try parseUInt16(invocation.arguments[4])
                )
            )
        case "__SWIFTOOT_gsDPLoadTile":
            try invocation.requireCount(5)
            return .dpLoadTile(
                LoadTileCommand(
                    tile: try parseUInt8(invocation.arguments[0]),
                    upperLeftS: try parseUInt16(invocation.arguments[1]),
                    upperLeftT: try parseUInt16(invocation.arguments[2]),
                    lowerRightS: try parseUInt16(invocation.arguments[3]),
                    lowerRightT: try parseUInt16(invocation.arguments[4])
                )
            )
        case "__SWIFTOOT_gsDPSetTile":
            try invocation.requireCount(12)
            let wrapT = try parseUInt8(invocation.arguments[6])
            let wrapS = try parseUInt8(invocation.arguments[9])
            return .dpSetTile(
                TileDescriptor(
                    format: try parseTextureFormat(format: invocation.arguments[0], texelSize: invocation.arguments[1]),
                    texelSize: try parseTexelSize(invocation.arguments[1]),
                    line: try parseUInt16(invocation.arguments[2]),
                    tmem: try parseUInt16(invocation.arguments[3]),
                    tile: try parseUInt8(invocation.arguments[4]),
                    palette: try parseUInt8(invocation.arguments[5]),
                    clampS: (wrapS & 0x02) != 0,
                    mirrorS: (wrapS & 0x01) != 0,
                    maskS: try parseUInt8(invocation.arguments[10]),
                    shiftS: try parseUInt8(invocation.arguments[11]),
                    clampT: (wrapT & 0x02) != 0,
                    mirrorT: (wrapT & 0x01) != 0,
                    maskT: try parseUInt8(invocation.arguments[7]),
                    shiftT: try parseUInt8(invocation.arguments[8])
                )
            )
        case "__SWIFTOOT_gsDPSetTileSize":
            try invocation.requireCount(5)
            return .dpSetTileSize(
                TileSizeCommand(
                    tile: try parseUInt8(invocation.arguments[0]),
                    upperLeftS: try parseUInt16(invocation.arguments[1]),
                    upperLeftT: try parseUInt16(invocation.arguments[2]),
                    lowerRightS: try parseUInt16(invocation.arguments[3]),
                    lowerRightT: try parseUInt16(invocation.arguments[4])
                )
            )
        case "__SWIFTOOT_gsDPSetCombineLERP":
            try invocation.requireCount(16)
            return .dpSetCombineMode(try parseCombineMode(invocation.arguments))
        case "__SWIFTOOT_gsDPSetCombineMode":
            try invocation.requireCount(16)
            return .dpSetCombineMode(try parseCombineMode(invocation.arguments))
        case "__SWIFTOOT_gsDPSetRenderMode":
            try invocation.requireCount(2)
            let firstMode = try parseUInt32(invocation.arguments[0])
            let secondMode = try parseUInt32(invocation.arguments[1])
            let flags = firstMode | secondMode
            return .dpSetRenderMode(RenderMode(flags: flags))
        case "__SWIFTOOT_gsSPGeometryMode":
            try invocation.requireCount(2)
            return .spGeometryMode(
                GeometryModeCommand(
                    clearBits: try parseUInt32(invocation.arguments[0]),
                    setBits: try parseUInt32(invocation.arguments[1])
                )
            )
        case "__SWIFTOOT_gsSPSetGeometryMode":
            try invocation.requireCount(1)
            return .spGeometryMode(
                GeometryModeCommand(
                    clearBits: 0,
                    setBits: try parseUInt32(invocation.arguments[0])
                )
            )
        case "__SWIFTOOT_gsSPClearGeometryMode":
            try invocation.requireCount(1)
            return .spGeometryMode(
                GeometryModeCommand(
                    clearBits: try parseUInt32(invocation.arguments[0]),
                    setBits: 0
                )
            )
        case "__SWIFTOOT_gsDPSetTextureLUT":
            try invocation.requireCount(1)
            return .dpSetTextureLUT(try parseTextureLUTMode(invocation.arguments[0]))
        case "__SWIFTOOT_gsDPSetPrimColor":
            try invocation.requireCount(6)
            return .dpSetPrimColor(
                PrimitiveColor(
                    minimumLOD: try parseUInt8(invocation.arguments[0]),
                    level: try parseUInt8(invocation.arguments[1]),
                    color: RGBA8(
                        red: try parseUInt8(invocation.arguments[2]),
                        green: try parseUInt8(invocation.arguments[3]),
                        blue: try parseUInt8(invocation.arguments[4]),
                        alpha: try parseUInt8(invocation.arguments[5])
                    )
                )
            )
        case "__SWIFTOOT_gsDPSetEnvColor":
            try invocation.requireCount(4)
            return .dpSetEnvColor(try parseColor(invocation.arguments))
        case "__SWIFTOOT_gsDPSetFogColor":
            try invocation.requireCount(4)
            return .dpSetFogColor(try parseColor(invocation.arguments))
        case "__SWIFTOOT_gsDPPipeSync":
            try invocation.requireCount(0)
            return .dpPipeSync
        case "__SWIFTOOT_gsDPTileSync":
            try invocation.requireCount(0)
            return .dpTileSync
        case "__SWIFTOOT_gsDPLoadSync":
            try invocation.requireCount(0)
            return .dpLoadSync
        default:
            throw DisplayListParserError.unsupportedMacro(invocation.name)
        }
    }

    private func parseColor(_ arguments: [String]) throws -> RGBA8 {
        try RGBA8(
            red: parseUInt8(arguments[0]),
            green: parseUInt8(arguments[1]),
            blue: parseUInt8(arguments[2]),
            alpha: parseUInt8(arguments[3])
        )
    }

    private func parseTextureFormat(format expression: String, texelSize sizeExpression: String) throws -> TextureFormat {
        switch (try parseUInt32(expression), try parseUInt32(sizeExpression)) {
        case (0, 2):
            return .rgba16
        case (0, 3):
            return .rgba32
        case (2, 0):
            return .ci4
        case (2, 1):
            return .ci8
        case (3, 0):
            return .ia4
        case (3, 1):
            return .ia8
        case (3, 2):
            return .ia16
        case (4, 0):
            return .i4
        case (4, 1):
            return .i8
        default:
            throw DisplayListParserError.unsupportedTextureFormat("\(expression), \(sizeExpression)")
        }
    }

    private func parseTexelSize(_ expression: String) throws -> TexelSize {
        switch try parseUInt32(expression) {
        case 0:
            return .bits4
        case 1:
            return .bits8
        case 2:
            return .bits16
        case 3:
            return .bits32
        default:
            throw DisplayListParserError.unsupportedTexelSize(expression)
        }
    }

    private func parseTextureLUTMode(_ expression: String) throws -> TextureLUTMode {
        switch try parseUInt32(expression) {
        case 0:
            return .none
        case 2, 2 << 14:
            return .rgba16
        case 3, 3 << 14:
            return .ia16
        default:
            throw DisplayListParserError.invalidInvocation("Unsupported texture LUT mode: \(expression)")
        }
    }

    private func loadBlockTexelSize(for texelSize: TexelSize) throws -> TexelSize {
        switch texelSize {
        case .bits4, .bits8, .bits16:
            return .bits16
        case .bits32:
            return .bits32
        }
    }

    private func expandLoadTextureBlock(
        address: UInt32,
        formatExpression: String,
        texelSizeExpression: String,
        widthExpression: String,
        heightExpression: String,
        tmemExpression: String,
        tileExpression: String,
        paletteExpression: String,
        wrapSExpression: String,
        wrapTExpression: String,
        maskSExpression: String,
        maskTExpression: String,
        shiftSExpression: String,
        shiftTExpression: String
    ) throws -> [F3DEX2Command] {
        let format = try parseTextureFormat(format: formatExpression, texelSize: texelSizeExpression)
        let texelSize = try parseTexelSize(texelSizeExpression)
        let width = try parseUInt16(widthExpression)
        let height = try parseUInt16(heightExpression)
        let tmem = try parseUInt16(tmemExpression)
        let tile = try parseUInt8(tileExpression)
        let palette = try parseUInt8(paletteExpression)
        let wrapS = try parseUInt8(wrapSExpression)
        let wrapT = try parseUInt8(wrapTExpression)
        let maskS = try parseUInt8(maskSExpression)
        let maskT = try parseUInt8(maskTExpression)
        let shiftS = try parseUInt8(shiftSExpression)
        let shiftT = try parseUInt8(shiftTExpression)

        let loadBlockTexelSize = try loadBlockTexelSize(for: texelSize)
        let texelCount = try loadBlockTexelCount(width: width, height: height, texelSize: texelSize)
        let dxt = try loadBlockDXT(width: width, texelSize: texelSize)
        let line = try textureLine(width: width, texelSize: texelSize)

        return [
            .dpSetTextureImage(
                ImageDescriptor(
                    format: format,
                    texelSize: loadBlockTexelSize,
                    width: 1,
                    address: address
                )
            ),
            .dpSetTile(
                makeTileDescriptor(
                    format: format,
                    texelSize: loadBlockTexelSize,
                    line: 0,
                    tmem: tmem,
                    tile: 7,
                    palette: 0,
                    wrapS: wrapS,
                    wrapT: wrapT,
                    maskS: maskS,
                    maskT: maskT,
                    shiftS: shiftS,
                    shiftT: shiftT
                )
            ),
            .dpLoadSync,
            .dpLoadBlock(
                LoadBlockCommand(
                    tile: 7,
                    upperLeftS: 0,
                    upperLeftT: 0,
                    texelCount: texelCount,
                    dxt: dxt
                )
            ),
            .dpPipeSync,
            .dpSetTile(
                makeTileDescriptor(
                    format: format,
                    texelSize: texelSize,
                    line: line,
                    tmem: tmem,
                    tile: tile,
                    palette: palette,
                    wrapS: wrapS,
                    wrapT: wrapT,
                    maskS: maskS,
                    maskT: maskT,
                    shiftS: shiftS,
                    shiftT: shiftT
                )
            ),
            .dpSetTileSize(
                TileSizeCommand(
                    tile: tile,
                    upperLeftS: 0,
                    upperLeftT: 0,
                    lowerRightS: UInt16((Int(width) - 1) << 2),
                    lowerRightT: UInt16((Int(height) - 1) << 2)
                )
            ),
        ]
    }

    private func expandLoadTextureBlock4b(
        address: UInt32,
        formatExpression: String,
        widthExpression: String,
        heightExpression: String,
        paletteExpression: String,
        wrapSExpression: String,
        wrapTExpression: String,
        maskSExpression: String,
        maskTExpression: String,
        shiftSExpression: String,
        shiftTExpression: String,
        tmemExpression: String = "0",
        tileExpression: String = "0"
    ) throws -> [F3DEX2Command] {
        let format = try parseTextureFormat(format: formatExpression, texelSize: "0")
        let width = try parseUInt16(widthExpression)
        let height = try parseUInt16(heightExpression)
        let palette = try parseUInt8(paletteExpression)
        let wrapS = try parseUInt8(wrapSExpression)
        let wrapT = try parseUInt8(wrapTExpression)
        let maskS = try parseUInt8(maskSExpression)
        let maskT = try parseUInt8(maskTExpression)
        let shiftS = try parseUInt8(shiftSExpression)
        let shiftT = try parseUInt8(shiftTExpression)
        let tmem = try parseUInt16(tmemExpression)
        let tile = try parseUInt8(tileExpression)
        let dxt = try loadBlockDXT(width: width, texelSize: .bits4)
        let texelCount = try loadBlockTexelCount(width: width, height: height, texelSize: .bits4)
        let line = UInt16((((Int(width) >> 1) + 7) >> 3))

        return [
            .dpSetTextureImage(
                ImageDescriptor(
                    format: format,
                    texelSize: .bits16,
                    width: 1,
                    address: address
                )
            ),
            .dpSetTile(
                makeTileDescriptor(
                    format: format,
                    texelSize: .bits16,
                    line: 0,
                    tmem: tmem,
                    tile: 7,
                    palette: 0,
                    wrapS: wrapS,
                    wrapT: wrapT,
                    maskS: maskS,
                    maskT: maskT,
                    shiftS: shiftS,
                    shiftT: shiftT
                )
            ),
            .dpLoadSync,
            .dpLoadBlock(
                LoadBlockCommand(
                    tile: 7,
                    upperLeftS: 0,
                    upperLeftT: 0,
                    texelCount: texelCount,
                    dxt: dxt
                )
            ),
            .dpPipeSync,
            .dpSetTile(
                makeTileDescriptor(
                    format: format,
                    texelSize: .bits4,
                    line: line,
                    tmem: tmem,
                    tile: tile,
                    palette: palette,
                    wrapS: wrapS,
                    wrapT: wrapT,
                    maskS: maskS,
                    maskT: maskT,
                    shiftS: shiftS,
                    shiftT: shiftT
                )
            ),
            .dpSetTileSize(
                TileSizeCommand(
                    tile: tile,
                    upperLeftS: 0,
                    upperLeftT: 0,
                    lowerRightS: UInt16((Int(width) - 1) << 2),
                    lowerRightT: UInt16((Int(height) - 1) << 2)
                )
            ),
        ]
    }

    private func makeTileDescriptor(
        format: TextureFormat,
        texelSize: TexelSize,
        line: UInt16,
        tmem: UInt16,
        tile: UInt8,
        palette: UInt8,
        wrapS: UInt8,
        wrapT: UInt8,
        maskS: UInt8,
        maskT: UInt8,
        shiftS: UInt8,
        shiftT: UInt8
    ) -> TileDescriptor {
        TileDescriptor(
            format: format,
            texelSize: texelSize,
            line: line,
            tmem: tmem,
            tile: tile,
            palette: palette,
            clampS: (wrapS & 0x02) != 0,
            mirrorS: (wrapS & 0x01) != 0,
            maskS: maskS,
            shiftS: shiftS,
            clampT: (wrapT & 0x02) != 0,
            mirrorT: (wrapT & 0x01) != 0,
            maskT: maskT,
            shiftT: shiftT
        )
    }

    private func loadBlockTexelCount(width: UInt16, height: UInt16, texelSize: TexelSize) throws -> UInt16 {
        let texelProduct = Int(width) * Int(height)

        let count: Int
        switch texelSize {
        case .bits4:
            count = ((texelProduct + 3) >> 2) - 1
        case .bits8:
            count = ((texelProduct + 1) >> 1) - 1
        case .bits16, .bits32:
            count = texelProduct - 1
        }

        guard count >= 0, count <= Int(UInt16.max) else {
            throw DisplayListParserError.integerOutOfRange("\(width)x\(height)")
        }
        return UInt16(count)
    }

    private func loadBlockDXT(width: UInt16, texelSize: TexelSize) throws -> UInt16 {
        let wordsPerLine: Int
        switch texelSize {
        case .bits4:
            wordsPerLine = max(1, Int(width) / 16)
        case .bits8:
            wordsPerLine = max(1, Int(width) / 4)
        case .bits16:
            wordsPerLine = max(1, Int(width) * 2 / 8)
        case .bits32:
            wordsPerLine = max(1, Int(width) * 4 / 8)
        }

        return UInt16(((1 << 11) + wordsPerLine - 1) / wordsPerLine)
    }

    private func textureLine(width: UInt16, texelSize: TexelSize) throws -> UInt16 {
        let lineBytes: Int
        switch texelSize {
        case .bits4, .bits8:
            lineBytes = 1
        case .bits16, .bits32:
            lineBytes = 2
        }

        return UInt16((((Int(width) * lineBytes) + 7) >> 3))
    }

    private func parseCombineMode(_ arguments: [String]) throws -> CombineMode {
        func colorSource(_ value: String) throws -> UInt32 {
            switch normalizedIdentifier(value) {
            case "COMBINED":
                return 0
            case "TEXEL0":
                return 1
            case "TEXEL1":
                return 2
            case "PRIMITIVE":
                return 3
            case "SHADE":
                return 4
            case "ENVIRONMENT":
                return 5
            case "CENTER", "SCALE", "1":
                return 6
            case "COMBINED_ALPHA", "NOISE", "K4":
                return 7
            case "TEXEL0_ALPHA":
                return 8
            case "TEXEL1_ALPHA":
                return 9
            case "PRIMITIVE_ALPHA":
                return 10
            case "SHADE_ALPHA":
                return 11
            case "ENV_ALPHA":
                return 12
            case "LOD_FRACTION":
                return 13
            case "PRIM_LOD_FRAC":
                return 14
            case "K5":
                return 15
            case "0":
                return 31
            default:
                return try parseUInt32(value)
            }
        }

        func alphaSource(_ value: String) throws -> UInt32 {
            switch normalizedIdentifier(value) {
            case "COMBINED", "LOD_FRACTION":
                return 0
            case "TEXEL0":
                return 1
            case "TEXEL1":
                return 2
            case "PRIMITIVE":
                return 3
            case "SHADE":
                return 4
            case "ENVIRONMENT":
                return 5
            case "PRIM_LOD_FRAC", "1":
                return 6
            case "0":
                return 7
            default:
                return try parseUInt32(value)
            }
        }

        let colorA0 = try colorSource(arguments[0])
        let colorC0 = try colorSource(arguments[2])
        let alphaAa0 = try alphaSource(arguments[4])
        let alphaAc0 = try alphaSource(arguments[6])
        let colorA1 = try colorSource(arguments[8])
        let colorC1 = try colorSource(arguments[10])
        let colorMux =
            (colorA0 << 20) |
            (colorC0 << 15) |
            (alphaAa0 << 12) |
            (alphaAc0 << 9) |
            (colorA1 << 5) |
            colorC1

        let colorB0 = try colorSource(arguments[1])
        let colorD0 = try colorSource(arguments[3])
        let alphaAb0 = try alphaSource(arguments[5])
        let alphaAd0 = try alphaSource(arguments[7])
        let colorB1 = try colorSource(arguments[9])
        let alphaAa1 = try alphaSource(arguments[12])
        let alphaAc1 = try alphaSource(arguments[14])
        let colorD1 = try colorSource(arguments[11])
        let alphaAb1 = try alphaSource(arguments[13])
        let alphaAd1 = try alphaSource(arguments[15])
        let alphaMux =
            (colorB0 << 28) |
            (colorD0 << 15) |
            (alphaAb0 << 12) |
            (alphaAd0 << 9) |
            (colorB1 << 24) |
            (alphaAa1 << 21) |
            (alphaAc1 << 18) |
            (colorD1 << 6) |
            (alphaAb1 << 3) |
            alphaAd1

        return CombineMode(colorMux: colorMux, alphaMux: alphaMux)
    }

    private func normalizedIdentifier(_ expression: String) -> String {
        expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "")
    }

    private func parseAddress(_ expression: String) throws -> UInt32 {
        if let value = try? parseUInt32(expression) {
            return value
        }

        if let indexedIdentifier = try parseIndexedAddress(expression) {
            return Self.stableID(for: indexedIdentifier)
        }

        let identifier = normalizedIdentifier(expression)
        guard identifier.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            throw DisplayListParserError.invalidAddressExpression(expression)
        }
        return Self.stableID(for: identifier)
    }

    private func parseIndexedAddress(_ expression: String) throws -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = Self.indexedAddressExpression.firstMatch(in: trimmed, range: range) else {
            return nil
        }

        let base = try Self.capturedGroup(1, from: match, in: trimmed)
        let indexExpression = try Self.capturedGroup(2, from: match, in: trimmed)
        let index = try parseUInt32(indexExpression)
        return "\(base)[\(index)]"
    }

    private static let indexedAddressExpression = try! NSRegularExpression(
        pattern: #"^&?\s*([A-Za-z_][A-Za-z0-9_]*)\s*\[\s*(.+?)\s*\]$"#
    )

    private static func capturedGroup(_ index: Int, from match: NSTextCheckingResult, in string: String) throws -> String {
        let range = match.range(at: index)
        guard let swiftRange = Range(range, in: string) else {
            throw DisplayListParserError.invalidInvocation("Missing capture group \(index)")
        }
        return String(string[swiftRange])
    }

    private func parseUInt8(_ expression: String) throws -> UInt8 {
        try cast(parseInteger(expression), to: UInt8.self, expression: expression)
    }

    private func parseUInt16(_ expression: String) throws -> UInt16 {
        try cast(parseInteger(expression), to: UInt16.self, expression: expression)
    }

    private func parseUInt32(_ expression: String) throws -> UInt32 {
        try cast(parseInteger(expression), to: UInt32.self, expression: expression)
    }

    private func parseInteger(_ expression: String) throws -> Int64 {
        var parser = try IntegerExpressionParser(expression: normalizedIntegerExpression(expression))
        return try parser.parse()
    }

    private func normalizedIntegerExpression(_ expression: String) -> String {
        let replacements: [String: String] = [
            "G_TX_RENDERTILE": "0",
            "G_TX_LOADTILE": "7",
            "G_TX_NOMIRROR": "0",
            "G_TX_WRAP": "0",
            "G_TX_MIRROR": "1",
            "G_TX_CLAMP": "2",
            "G_TX_NOLOD": "0",
            "G_ON": "1",
            "G_OFF": "0",
        ]

        return replacements.reduce(expression) { partialResult, replacement in
            partialResult.replacingOccurrences(
                of: #"\b\#(replacement.key)\b"#,
                with: replacement.value,
                options: .regularExpression
            )
        }
    }

    private func cast<T: FixedWidthInteger>(_ value: Int64, to type: T.Type, expression: String) throws -> T {
        guard let casted = T(exactly: value) else {
            throw DisplayListParserError.integerOutOfRange(expression)
        }
        return casted
    }
}

struct ParsedDisplayList: Equatable, Sendable {
    let name: String
    let commands: [F3DEX2Command]
}

private struct DisplayListArray {
    let name: String
    let body: String
}

private enum DisplayListParserError: LocalizedError {
    case preprocessorFailure(String)
    case unsupportedMacro(String)
    case invalidAddressExpression(String)
    case unsupportedTextureFormat(String)
    case unsupportedTexelSize(String)
    case invalidInvocation(String)
    case unterminatedArray
    case integerOutOfRange(String)

    var isSkippableSourceFailure: Bool {
        switch self {
        case .unsupportedMacro:
            return true
        case .preprocessorFailure(let message):
            return message.contains("file not found")
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .preprocessorFailure(let message):
            return "C preprocessing failed: \(message)"
        case .unsupportedMacro(let name):
            return "Unsupported display list macro: \(name)"
        case .invalidAddressExpression(let expression):
            return "Unsupported address expression: \(expression)"
        case .unsupportedTextureFormat(let expression):
            return "Unsupported texture format expression: \(expression)"
        case .unsupportedTexelSize(let expression):
            return "Unsupported texel size expression: \(expression)"
        case .invalidInvocation(let message):
            return "Invalid macro invocation: \(message)"
        case .unterminatedArray:
            return "Encountered an unterminated display list array."
        case .integerOutOfRange(let expression):
            return "Integer result is out of range for expression: \(expression)"
        }
    }
}

private struct MacroInvocation {
    let name: String
    let arguments: [String]

    func requireCount(_ expected: Int) throws {
        guard arguments.count == expected else {
            throw DisplayListParserError.invalidInvocation("\(name) expected \(expected) arguments, found \(arguments.count)")
        }
    }

    static func parseAll(in source: String) throws -> [MacroInvocation] {
        let characters = Array(source)
        var index = 0
        var invocations: [MacroInvocation] = []

        func skipTrivia() {
            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace || character == "," || character == ";" {
                    index += 1
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

            let identifierStart = index
            guard characters[index].isLetter || characters[index] == "_" else {
                throw DisplayListParserError.invalidInvocation("Unexpected token in display list body: \(characters[index])")
            }

            index += 1
            while index < characters.count, (characters[index].isLetter || characters[index].isNumber || characters[index] == "_") {
                index += 1
            }

            let name = String(characters[identifierStart..<index])
            skipTrivia()
            guard index < characters.count, characters[index] == "(" else {
                throw DisplayListParserError.invalidInvocation("Missing opening parenthesis for \(name)")
            }

            index += 1
            var depth = 1
            let argumentsStart = index

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
                throw DisplayListParserError.invalidInvocation("Unterminated invocation for \(name)")
            }

            let argumentsSlice = String(characters[argumentsStart..<index])
            let arguments = splitArguments(argumentsSlice)
            invocations.append(MacroInvocation(name: name, arguments: arguments))
            index += 1
        }

        return invocations
    }

    private static func splitArguments(_ input: String) -> [String] {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var arguments: [String] = []
        var depth = 0
        var start = input.startIndex
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
            } else if character == ",", depth == 0 {
                arguments.append(input[start..<index].trimmingCharacters(in: .whitespacesAndNewlines))
                start = input.index(after: index)
            }
            index = input.index(after: index)
        }

        arguments.append(input[start..<input.endIndex].trimmingCharacters(in: .whitespacesAndNewlines))
        return arguments
    }
}

struct CMacroPreprocessor {
    private let shell: URL

    init(shell: URL = URL(fileURLWithPath: "/usr/bin/clang")) {
        self.shell = shell
    }

    func preprocess(fileURL: URL, sourceRoot: URL) throws -> String {
        let wrapper = makeWrapper(for: fileURL)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftoot-displaylist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let wrapperURL = temporaryDirectory.appendingPathComponent("wrapper.c")
        try wrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = shell
        process.arguments = [
            "-E",
            "-P",
            "-x",
            "c",
            wrapperURL.path,
        ] + includeDirectories(for: fileURL, sourceRoot: sourceRoot).flatMap { directory in
            ["-I", directory.path]
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let group = DispatchGroup()
        let outputCapture = PipeCapture()
        let errorCapture = PipeCapture()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputCapture.data = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorCapture.data = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        let output = String(data: outputCapture.data, encoding: .utf8) ?? ""
        let error = String(data: errorCapture.data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            // Extracted asset sources can reference unrelated blob includes that are absent
            // locally, but clang still emits enough expanded geometry/display-list output
            // before the failure for downstream parsing to succeed.
            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return output
            }

            throw DisplayListParserError.preprocessorFailure(error.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    private func includeDirectories(for fileURL: URL, sourceRoot: URL) -> [URL] {
        let candidates = [
            assetRoot(for: fileURL),
            sourceRoot.appendingPathComponent("build", isDirectory: true),
            sourceRoot,
            sourceRoot.appendingPathComponent("include", isDirectory: true),
            fileURL.deletingLastPathComponent(),
        ]

        var seenPaths = Set<String>()
        return candidates.compactMap { directory in
            guard let directory else {
                return nil
            }

            let path = directory.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else {
                return nil
            }

            return directory
        }
    }

    private func assetRoot(for fileURL: URL) -> URL? {
        let standardizedPath = fileURL.standardizedFileURL.path
        guard let assetsRange = standardizedPath.range(of: "/assets/") else {
            return nil
        }

        return URL(
            fileURLWithPath: String(standardizedPath[..<assetsRange.lowerBound]),
            isDirectory: true
        )
    }

    private func makeWrapper(for fileURL: URL) -> String {
        let escapedPath = fileURL.path.replacingOccurrences(of: "\\", with: "\\\\")
        let macroNames = [
            "gsSPVertex",
            "gsSPCullDisplayList",
            "gsSP1Triangle",
            "gsSP2Triangles",
            "gsSPDisplayList",
            "gsSPBranchList",
            "gsSPBranchDL",
            "gsSPBranchLessZraw",
            "gsSPEndDisplayList",
            "gsSPMatrix",
            "gsSPPopMatrix",
            "gsSPTexture",
            "gsDPSetTextureImage",
            "gsDPSetTextureLUT",
            "gsDPLoadTextureBlock",
            "gsDPLoadTextureBlock_4b",
            "gsDPLoadMultiBlock",
            "gsDPLoadMultiBlock_4b",
            "gsDPLoadTLUT_pal16",
            "gsDPLoadTLUT_pal256",
            "gsDPLoadBlock",
            "gsDPLoadTile",
            "gsDPSetTile",
            "gsDPSetTileSize",
            "gsDPSetCombineLERP",
            "gsDPSetCombineMode",
            "gsDPSetRenderMode",
            "gsSPGeometryMode",
            "gsSPSetGeometryMode",
            "gsSPClearGeometryMode",
            "gsDPSetPrimColor",
            "gsDPSetEnvColor",
            "gsDPSetFogColor",
            "gsDPPipeSync",
            "gsDPTileSync",
            "gsDPLoadSync",
        ]

        let definitions = macroNames.map { name in
            """
            #undef \(name)
            #define \(name)(...) __SWIFTOOT_\(name)(__VA_ARGS__)
            """
        }.joined(separator: "\n")

        return """
        #include "ultra64/gbi.h"
        \(definitions)
        #include "\(escapedPath)"
        """
    }
}

private final class PipeCapture: @unchecked Sendable {
    var data = Data()
}

private struct IntegerExpressionParser {
    private let tokens: [Token]
    private var index = 0

    init(expression: String) throws {
        self.tokens = try Tokenizer(expression: expression).tokenize()
    }

    mutating func parse() throws -> Int64 {
        let value = try parseBitwiseOr()
        guard current.kind == .end else {
            throw DisplayListParserError.invalidInvocation("Unexpected token in integer expression")
        }
        return value
    }

    private var current: Token {
        tokens[index]
    }

    @discardableResult
    private mutating func advance() -> Token {
        let token = tokens[index]
        index += 1
        return token
    }

    private mutating func parseBitwiseOr() throws -> Int64 {
        var value = try parseBitwiseXor()
        while current.kind == .pipe {
            advance()
            let rhs = try parseBitwiseXor()
            value |= rhs
        }
        return value
    }

    private mutating func parseBitwiseXor() throws -> Int64 {
        var value = try parseBitwiseAnd()
        while current.kind == .caret {
            advance()
            let rhs = try parseBitwiseAnd()
            value ^= rhs
        }
        return value
    }

    private mutating func parseBitwiseAnd() throws -> Int64 {
        var value = try parseShift()
        while current.kind == .ampersand {
            advance()
            let rhs = try parseShift()
            value &= rhs
        }
        return value
    }

    private mutating func parseShift() throws -> Int64 {
        var value = try parseAdditive()
        while current.kind == .shiftLeft || current.kind == .shiftRight {
            let operation = advance().kind
            let rhs = try parseAdditive()
            if operation == .shiftLeft {
                value <<= rhs
            } else {
                value >>= rhs
            }
        }
        return value
    }

    private mutating func parseAdditive() throws -> Int64 {
        var value = try parseMultiplicative()
        while current.kind == .plus || current.kind == .minus {
            let operation = advance().kind
            let rhs = try parseMultiplicative()
            if operation == .plus {
                value = value + rhs
            } else {
                value = value - rhs
            }
        }
        return value
    }

    private mutating func parseMultiplicative() throws -> Int64 {
        var value = try parseUnary()
        while current.kind == .star || current.kind == .slash {
            let operation = advance().kind
            let rhs = try parseUnary()
            if operation == .star {
                value = value * rhs
            } else {
                value = value / rhs
            }
        }
        return value
    }

    private mutating func parseUnary() throws -> Int64 {
        switch current.kind {
        case .plus:
            advance()
            return try parseUnary()
        case .minus:
            advance()
            return -(try parseUnary())
        case .tilde:
            advance()
            return ~(try parseUnary())
        default:
            return try parsePrimary()
        }
    }

    private mutating func parsePrimary() throws -> Int64 {
        switch current.kind {
        case .number(let value):
            advance()
            return value
        case .leftParen:
            advance()
            let value = try parseBitwiseOr()
            guard current.kind == .rightParen else {
                throw DisplayListParserError.invalidInvocation("Missing closing parenthesis in integer expression")
            }
            advance()
            return value
        default:
            throw DisplayListParserError.invalidInvocation("Unsupported token in integer expression")
        }
    }
}

private struct Tokenizer {
    let expression: String

    func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        let characters = Array(expression)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                index += 1
                continue
            }

            if character == "0", index + 1 < characters.count, (characters[index + 1] == "x" || characters[index + 1] == "X") {
                let start = index
                index += 2
                while index < characters.count, characters[index].isHexDigit {
                    index += 1
                }
                let literal = String(characters[start..<index])
                guard let value = Int64(literal.dropFirst(2), radix: 16) else {
                    throw DisplayListParserError.invalidInvocation("Invalid hexadecimal literal \(literal)")
                }
                tokens.append(Token(kind: .number(value)))
                continue
            }

            if character.isNumber {
                let start = index
                index += 1
                while index < characters.count, characters[index].isNumber {
                    index += 1
                }
                let literal = String(characters[start..<index])
                guard let value = Int64(literal) else {
                    throw DisplayListParserError.invalidInvocation("Invalid decimal literal \(literal)")
                }
                tokens.append(Token(kind: .number(value)))
                continue
            }

            if character == "<", index + 1 < characters.count, characters[index + 1] == "<" {
                tokens.append(Token(kind: .shiftLeft))
                index += 2
                continue
            }

            if character == ">", index + 1 < characters.count, characters[index + 1] == ">" {
                tokens.append(Token(kind: .shiftRight))
                index += 2
                continue
            }

            let kind: Token.Kind
            switch character {
            case "(":
                kind = .leftParen
            case ")":
                kind = .rightParen
            case "+":
                kind = .plus
            case "-":
                kind = .minus
            case "*":
                kind = .star
            case "/":
                kind = .slash
            case "|":
                kind = .pipe
            case "&":
                kind = .ampersand
            case "^":
                kind = .caret
            case "~":
                kind = .tilde
            default:
                throw DisplayListParserError.invalidInvocation("Unsupported token in integer expression: \(character)")
            }
            tokens.append(Token(kind: kind))
            index += 1
        }

        tokens.append(Token(kind: .end))
        return tokens
    }
}

private struct Token {
    enum Kind: Equatable {
        case number(Int64)
        case leftParen
        case rightParen
        case plus
        case minus
        case star
        case slash
        case pipe
        case ampersand
        case caret
        case tilde
        case shiftLeft
        case shiftRight
        case end
    }

    let kind: Kind
}

import Foundation
import Metal
import OOTDataModel
import simd

public enum F3DEX2InterpreterError: Error, Sendable, Equatable {
    case missingSegmentData(UInt8)
    case segmentedAddressOutOfRange(address: UInt32, length: Int)
    case invalidVertexReference(UInt8)
}

public final class F3DEX2Interpreter {
    public private(set) var rspState: RSPState
    public private(set) var rdpState: RDPState
    public private(set) var segmentTable: SegmentTable
    public private(set) var drawBatch: DrawBatch
    public private(set) var warnings: [String]
    public private(set) var projectionMatrix: simd_float4x4
    public private(set) var textureImage: ImageDescriptor?
    public private(set) var tileSizes: [TileSizeCommand?]
    public private(set) var lastLoadBlock: LoadBlockCommand?
    public private(set) var lastLoadTile: LoadTileCommand?

    private let drawBatchResources: DrawBatchResources?
    private let environmentFogColor: SIMD4<Float>?
    private let displayListResolver: (UInt32) -> [F3DEX2Command]?
    private let textureResolver: (UInt32) -> MTLTexture?
    private let warningSink: (String) -> Void
    private var rawCombineMode: CombineMode
    private var hasExplicitCombineMode: Bool

    public init(
        rspState: RSPState = RSPState(),
        rdpState: RDPState = RDPState(),
        segmentTable: SegmentTable = SegmentTable(),
        projectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        drawBatchResources: DrawBatchResources? = nil,
        environmentFogColor: SIMD4<Float>? = nil,
        displayListResolver: @escaping (UInt32) -> [F3DEX2Command]? = { _ in nil },
        textureResolver: @escaping (UInt32) -> MTLTexture? = { _ in nil },
        warningSink: @escaping (String) -> Void = { _ in }
    ) {
        self.rspState = rspState
        self.rdpState = rdpState
        self.segmentTable = segmentTable
        self.warnings = []
        self.projectionMatrix = projectionMatrix
        self.textureImage = nil
        self.tileSizes = Array(repeating: nil, count: RDPState.tileCount)
        self.lastLoadBlock = nil
        self.lastLoadTile = nil
        self.drawBatchResources = drawBatchResources
        self.environmentFogColor = environmentFogColor
        self.displayListResolver = displayListResolver
        self.textureResolver = textureResolver
        self.warningSink = warningSink
        self.rawCombineMode = CombineMode(colorMux: 0, alphaMux: 0)
        self.hasExplicitCombineMode = false
        self.drawBatch = DrawBatch(
            renderStateKey: Self.renderStateKey(
                geometryMode: rspState.geometryMode,
                renderMode: rdpState.renderMode,
                combineMode: CombineMode(colorMux: 0, alphaMux: 0)
            ),
            combinerUniforms: CombinerUniforms(),
            resources: drawBatchResources
        )
    }

    public func interpret(
        _ commands: [F3DEX2Command],
        encoder: MTLRenderCommandEncoder
    ) throws {
        var frames = [DisplayListFrame(commands: commands, nextIndex: 0)]

        while frames.isEmpty == false {
            let frameIndex = frames.count - 1
            if frames[frameIndex].nextIndex >= frames[frameIndex].commands.count {
                _ = frames.popLast()
                continue
            }

            let command = frames[frameIndex].commands[frames[frameIndex].nextIndex]
            frames[frameIndex].nextIndex += 1

            switch command {
            case .spNoOp, .dpNoOp, .dpPipeSync, .dpTileSync, .dpLoadSync, .dpFullSync:
                continue
            case .spMatrix(let matrixCommand):
                try applyMatrixCommand(matrixCommand)
            case .spPopMatrix:
                try rspState.popMatrix()
            case .spVertex(let vertexCommand):
                try loadVertices(vertexCommand)
            case .sp1Triangle(let triangleCommand):
                try emitTriangles([triangleCommand])
            case .sp2Triangles(let pairCommand):
                try emitTriangles([pairCommand.first, pairCommand.second])
            case .spDisplayList(let address):
                guard let nestedCommands = displayListResolver(address) else {
                    logWarning("Skipping unresolved display list 0x\(String(address, radix: 16)).")
                    continue
                }
                frames.append(DisplayListFrame(commands: nestedCommands, nextIndex: 0))
            case .spBranchList(let address):
                guard let nestedCommands = displayListResolver(address) else {
                    logWarning("Skipping unresolved branch display list 0x\(String(address, radix: 16)).")
                    continue
                }
                frames[frameIndex] = DisplayListFrame(commands: nestedCommands, nextIndex: 0)
            case .spEndDisplayList:
                _ = frames.popLast()
            case .spTexture(let textureState):
                try flushPendingTriangles(encoder: encoder)
                rspState.setTextureState(
                    enabled: textureState.enabled,
                    scaleS: textureState.scaleS,
                    scaleT: textureState.scaleT,
                    level: textureState.level,
                    tile: textureState.tile
                )
                if textureState.enabled == false {
                    drawBatch.texel0Texture = nil
                    drawBatch.texel1Texture = nil
                }
                synchronizeBatchState()
            case .dpSetTextureImage(let descriptor):
                try flushPendingTriangles(encoder: encoder)
                textureImage = descriptor
            case .dpLoadBlock(let command):
                try flushPendingTriangles(encoder: encoder)
                lastLoadBlock = command
                synchronizeTextures()
            case .dpLoadTile(let command):
                try flushPendingTriangles(encoder: encoder)
                lastLoadTile = command
                synchronizeTextures()
            case .dpSetTile(let descriptor):
                try flushPendingTriangles(encoder: encoder)
                try rdpState.setTileDescriptor(descriptor)
                synchronizeBatchState()
            case .dpSetTileSize(let command):
                try flushPendingTriangles(encoder: encoder)
                tileSizes[Int(command.tile)] = command
                synchronizeBatchState()
            case .dpSetCombineMode(let combineMode):
                try flushPendingTriangles(encoder: encoder)
                rawCombineMode = combineMode
                hasExplicitCombineMode = true
                rdpState.setCombineMode(Self.decodeCombineState(from: combineMode))
                synchronizeBatchState()
            case .dpSetRenderMode(let renderMode):
                try flushPendingTriangles(encoder: encoder)
                rdpState.renderMode = renderMode
                synchronizeBatchState()
            case .spGeometryMode(let geometryMode):
                try flushPendingTriangles(encoder: encoder)
                rspState.applyGeometryMode(
                    clearBits: geometryMode.clearBits,
                    setBits: geometryMode.setBits
                )
                synchronizeBatchState()
            case .dpSetPrimColor(let primitiveColor):
                try flushPendingTriangles(encoder: encoder)
                rdpState.primitiveColor = primitiveColor
                synchronizeBatchState()
            case .dpSetEnvColor(let color):
                try flushPendingTriangles(encoder: encoder)
                rdpState.environmentColor = color
                synchronizeBatchState()
            case .dpSetFogColor(let color):
                try flushPendingTriangles(encoder: encoder)
                rdpState.fogColor = color
                synchronizeBatchState()
            default:
                logWarning("Skipping unsupported F3DEX2 command: \(command.name).")
            }
        }

        try flushPendingTriangles(encoder: encoder)
    }

    public func flush(encoder: MTLRenderCommandEncoder) throws {
        try flushPendingTriangles(encoder: encoder)
    }
}

private extension F3DEX2Interpreter {
    struct DisplayListFrame {
        var commands: [F3DEX2Command]
        var nextIndex: Int
    }

    func loadVertices(_ command: VertexCommand) throws {
        let vertices = try decodeVertices(
            from: command.address,
            count: Int(command.count)
        )

        let transformedVertices = vertices.map(transform)
        try rspState.loadVertices(
            transformedVertices,
            startingAt: Int(command.destinationIndex)
        )
    }

    func transform(_ vertex: N64Vertex) -> TransformedVertex {
        let position = SIMD4<Float>(
            Float(vertex.position.x),
            Float(vertex.position.y),
            Float(vertex.position.z),
            1.0
        )

        let color = if rspState.geometryMode.contains(.lighting) {
            transformedNormal(from: vertex)
        } else {
            normalizedColor(from: vertex.colorOrNormal)
        }

        return TransformedVertex(
            clipPosition: simd_mul(currentTransformMatrix, position),
            textureCoordinates: SIMD2<Float>(
                Float(vertex.textureCoordinate.x) / 32.0,
                Float(vertex.textureCoordinate.y) / 32.0
            ),
            color: color
        )
    }

    var currentTransformMatrix: simd_float4x4 {
        simd_mul(projectionMatrix, rspState.currentMatrix)
    }

    func normalizedColor(from rgba: RGBA8) -> SIMD4<Float> {
        SIMD4<Float>(
            Float(rgba.red) / 255.0,
            Float(rgba.green) / 255.0,
            Float(rgba.blue) / 255.0,
            Float(rgba.alpha) / 255.0
        )
    }

    func transformedNormal(from vertex: N64Vertex) -> SIMD4<Float> {
        let normal = SIMD3<Float>(
            signedNormalized(vertex.colorOrNormal.red),
            signedNormalized(vertex.colorOrNormal.green),
            signedNormalized(vertex.colorOrNormal.blue)
        )
        let normalMatrix = simd_float3x3(
            SIMD3<Float>(rspState.currentMatrix.columns.0.x, rspState.currentMatrix.columns.0.y, rspState.currentMatrix.columns.0.z),
            SIMD3<Float>(rspState.currentMatrix.columns.1.x, rspState.currentMatrix.columns.1.y, rspState.currentMatrix.columns.1.z),
            SIMD3<Float>(rspState.currentMatrix.columns.2.x, rspState.currentMatrix.columns.2.y, rspState.currentMatrix.columns.2.z)
        )
        let transformed = simd_normalize(simd_mul(normalMatrix, normal))
        return SIMD4<Float>(
            transformed.x,
            transformed.y,
            transformed.z,
            Float(vertex.colorOrNormal.alpha) / 255.0
        )
    }

    func signedNormalized(_ value: UInt8) -> Float {
        Float(Int8(bitPattern: value)) / 127.0
    }

    func applyMatrixCommand(_ command: MatrixCommand) throws {
        let matrix = try decodeMatrix(from: command.address)

        if command.projection {
            if command.load {
                projectionMatrix = matrix
            } else {
                projectionMatrix = simd_mul(projectionMatrix, matrix)
            }
            return
        }

        if command.push {
            try rspState.pushMatrix()
        }

        if command.load {
            rspState.loadMatrix(matrix)
        } else {
            rspState.multiplyMatrix(by: matrix)
        }
    }

    func emitTriangles(_ commands: [TriangleCommand]) throws {
        synchronizeBatchState()

        var vertices: [TransformedVertex] = []
        var triangles: [SIMD3<UInt32>] = []
        vertices.reserveCapacity(commands.count * 3)
        triangles.reserveCapacity(commands.count)

        for command in commands {
            let vertexBase = UInt32(vertices.count)
            vertices.append(try resolvedVertex(at: command.vertex0))
            vertices.append(try resolvedVertex(at: command.vertex1))
            vertices.append(try resolvedVertex(at: command.vertex2))
            triangles.append(
                SIMD3<UInt32>(
                    vertexBase,
                    vertexBase + 1,
                    vertexBase + 2
                )
            )
        }

        try drawBatch.append(vertices: vertices, triangles: triangles)
    }

    func resolvedVertex(at index: UInt8) throws -> TransformedVertex {
        guard let vertex = try rspState.vertex(at: Int(index)) else {
            throw F3DEX2InterpreterError.invalidVertexReference(index)
        }

        return vertex
    }

    func decodeVertices(from address: UInt32, count: Int) throws -> [N64Vertex] {
        let byteCount = count * MemoryLayout<N64Vertex>.size
        let bytes = try resolveBytes(at: address, length: byteCount)
        var vertices: [N64Vertex] = []
        vertices.reserveCapacity(count)

        for vertexOffset in stride(from: 0, to: byteCount, by: MemoryLayout<N64Vertex>.size) {
            let base = bytes.startIndex + vertexOffset
            vertices.append(
                N64Vertex(
                    position: Vector3s(
                        x: readInteger(from: bytes, offset: base, as: Int16.self),
                        y: readInteger(from: bytes, offset: base + 2, as: Int16.self),
                        z: readInteger(from: bytes, offset: base + 4, as: Int16.self)
                    ),
                    flag: readInteger(from: bytes, offset: base + 6, as: UInt16.self),
                    textureCoordinate: Vector2s(
                        x: readInteger(from: bytes, offset: base + 8, as: Int16.self),
                        y: readInteger(from: bytes, offset: base + 10, as: Int16.self)
                    ),
                    colorOrNormal: RGBA8(
                        red: readInteger(from: bytes, offset: base + 12, as: UInt8.self),
                        green: readInteger(from: bytes, offset: base + 13, as: UInt8.self),
                        blue: readInteger(from: bytes, offset: base + 14, as: UInt8.self),
                        alpha: readInteger(from: bytes, offset: base + 15, as: UInt8.self)
                    )
                )
            )
        }

        return vertices
    }

    func decodeMatrix(from address: UInt32) throws -> simd_float4x4 {
        let bytes = try resolveBytes(at: address, length: 64)
        var columns = [SIMD4<Float>](repeating: .zero, count: 4)

        for elementIndex in 0..<16 {
            let upper = UInt32(readInteger(from: bytes, offset: bytes.startIndex + (elementIndex * 2), as: UInt16.self))
            let lower = UInt32(
                readInteger(
                    from: bytes,
                    offset: bytes.startIndex + 32 + (elementIndex * 2),
                    as: UInt16.self
                )
            )
            let fixedPoint = Int32(bitPattern: (upper << 16) | lower)
            let value = Float(fixedPoint) / 65_536.0
            let column = elementIndex / 4
            let row = elementIndex % 4
            columns[column][row] = value
        }

        return simd_float4x4(columns)
    }

    func resolveBytes(at address: UInt32, length: Int) throws -> Data {
        let segment = UInt8((address >> 24) & 0xFF)
        let offset = Int(address & 0x00FF_FFFF)

        guard let data = try segmentTable.data(for: segment) else {
            throw F3DEX2InterpreterError.missingSegmentData(segment)
        }

        let endOffset = offset + length
        guard offset >= 0, endOffset <= data.count else {
            throw F3DEX2InterpreterError.segmentedAddressOutOfRange(address: address, length: length)
        }

        return data.subdata(in: offset..<endOffset)
    }

    func readInteger<T: FixedWidthInteger>(
        from data: Data,
        offset: Int,
        as type: T.Type
    ) -> T {
        let range = offset..<(offset + MemoryLayout<T>.size)
        return data[range].withUnsafeBytes { rawBuffer in
            T(bigEndian: rawBuffer.load(as: T.self))
        }
    }

    func synchronizeBatchState() {
        drawBatch.renderStateKey = Self.renderStateKey(
            geometryMode: rspState.geometryMode,
            renderMode: rdpState.renderMode,
            combineMode: rawCombineMode
        )
        if hasExplicitCombineMode {
            drawBatch.combinerUniforms = CombinerUniforms(
                rdpState: rdpState,
                geometryMode: rspState.geometryMode,
                textureSamplingState: Self.textureSamplingState(
                    for: rspState.textureState,
                    tileDescriptor: try? rdpState.tileDescriptor(at: Int(rspState.textureState.tile)),
                    tileSize: tileSizes[safe: Int(rspState.textureState.tile)] ?? nil,
                    texture: drawBatch.texel0Texture
                )
            )
            if let environmentFogColor {
                drawBatch.combinerUniforms.fogColor = environmentFogColor
            }
        } else {
            drawBatch.combinerUniforms = CombinerUniforms()
        }
    }

    func synchronizeTextures() {
        guard rspState.textureState.enabled, let textureImage else {
            drawBatch.texel0Texture = nil
            drawBatch.texel1Texture = nil
            synchronizeBatchState()
            return
        }

        drawBatch.texel0Texture = textureResolver(textureImage.address)
        drawBatch.texel1Texture = nil
        synchronizeBatchState()
    }

    func flushPendingTriangles(encoder: MTLRenderCommandEncoder) throws {
        guard drawBatchResources != nil else {
            return
        }

        _ = try drawBatch.flush(encoder: encoder)
    }

    func logWarning(_ message: String) {
        warnings.append(message)
        warningSink(message)
    }

    static func renderStateKey(
        geometryMode: GeometryMode,
        renderMode: RenderMode,
        combineMode: CombineMode
    ) -> RenderStateKey {
        RenderStateKey(
            combinerHash: hashCombineMode(combineMode),
            geometryMode: geometryMode,
            renderMode: renderMode
        )
    }

    static func hashCombineMode(_ combineMode: CombineMode) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in combineMode.colorMux.bigEndianBytes + combineMode.alphaMux.bigEndianBytes {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func decodeCombineState(from combineMode: CombineMode) -> RDPCombineState {
        let colorMux = combineMode.colorMux
        let alphaMux = combineMode.alphaMux

        return RDPCombineState(
            firstCycle: RDPCombineCycle(
                color: RDPCombineSelectorGroup(
                    a: UInt8((colorMux >> 20) & 0x0F),
                    b: UInt8((alphaMux >> 28) & 0x0F),
                    c: UInt8((colorMux >> 15) & 0x1F),
                    d: UInt8((alphaMux >> 15) & 0x07)
                ),
                alpha: RDPCombineSelectorGroup(
                    a: UInt8((colorMux >> 12) & 0x07),
                    b: UInt8((alphaMux >> 12) & 0x07),
                    c: UInt8((colorMux >> 9) & 0x07),
                    d: UInt8((alphaMux >> 9) & 0x07)
                )
            ),
            secondCycle: RDPCombineCycle(
                color: RDPCombineSelectorGroup(
                    a: UInt8((colorMux >> 5) & 0x0F),
                    b: UInt8((alphaMux >> 24) & 0x0F),
                    c: UInt8(colorMux & 0x1F),
                    d: UInt8((alphaMux >> 6) & 0x07)
                ),
                alpha: RDPCombineSelectorGroup(
                    a: UInt8((alphaMux >> 21) & 0x07),
                    b: UInt8((alphaMux >> 3) & 0x07),
                    c: UInt8((alphaMux >> 18) & 0x07),
                    d: UInt8(alphaMux & 0x07)
                )
            )
        )
    }

    static func textureSamplingState(
        for textureState: TextureState,
        tileDescriptor: TileDescriptor?,
        tileSize: TileSizeCommand?,
        texture: MTLTexture?
    ) -> TextureSamplingState {
        guard textureState.enabled else {
            return TextureSamplingState()
        }

        let scaleS = textureState.scaleS == 0 ? 1.0 : Float(textureState.scaleS) / 65_536.0
        let scaleT = textureState.scaleT == 0 ? 1.0 : Float(textureState.scaleT) / 65_536.0
        let dimensions = SIMD2<Float>(
            Float(max(texture?.width ?? 1, 1)),
            Float(max(texture?.height ?? 1, 1))
        )
        let tileOrigin = tileOrigin(for: tileSize)
        let tileSpan = tileSpan(for: tileSize, texture: texture)

        return TextureSamplingState(
            scale: SIMD2<Float>(scaleS, scaleT),
            offset: -tileOrigin,
            dimensions: dimensions,
            tileSpan: tileSpan,
            clamp: SIMD2<UInt32>(
                tileDescriptor?.clampS == true ? 1 : 0,
                tileDescriptor?.clampT == true ? 1 : 0
            ),
            mirror: SIMD2<UInt32>(
                tileDescriptor?.mirrorS == true ? 1 : 0,
                tileDescriptor?.mirrorT == true ? 1 : 0
            )
        )
    }

    static func tileOrigin(for tileSize: TileSizeCommand?) -> SIMD2<Float> {
        guard let tileSize else {
            return .zero
        }

        return SIMD2<Float>(
            Float(tileSize.upperLeftS) / 4.0,
            Float(tileSize.upperLeftT) / 4.0
        )
    }

    static func tileSpan(
        for tileSize: TileSizeCommand?,
        texture: MTLTexture?
    ) -> SIMD2<Float> {
        guard let tileSize else {
            return SIMD2<Float>(
                Float(max(texture?.width ?? 1, 1)),
                Float(max(texture?.height ?? 1, 1))
            )
        }

        let width = max(
            (Float(tileSize.lowerRightS) - Float(tileSize.upperLeftS)) / 4.0 + 1.0,
            1.0
        )
        let height = max(
            (Float(tileSize.lowerRightT) - Float(tileSize.upperLeftT)) / 4.0 + 1.0,
            1.0
        )
        return SIMD2<Float>(width, height)
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF),
        ]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}

extension F3DEX2Interpreter {
    static func makeTextureSamplingState(
        for textureState: TextureState,
        tileDescriptor: TileDescriptor?,
        tileSize: TileSizeCommand?,
        texture: MTLTexture?
    ) -> TextureSamplingState {
        textureSamplingState(
            for: textureState,
            tileDescriptor: tileDescriptor,
            tileSize: tileSize,
            texture: texture
        )
    }
}

private extension F3DEX2Command {
    var name: String {
        switch self {
        case .spNoOp:
            return "spNoOp"
        case .spMatrix:
            return "spMatrix"
        case .spPopMatrix:
            return "spPopMatrix"
        case .spVertex:
            return "spVertex"
        case .spModifyVertex:
            return "spModifyVertex"
        case .sp1Triangle:
            return "sp1Triangle"
        case .sp2Triangles:
            return "sp2Triangles"
        case .spLine3D:
            return "spLine3D"
        case .spCullDisplayList:
            return "spCullDisplayList"
        case .spBranchList:
            return "spBranchList"
        case .spDisplayList:
            return "spDisplayList"
        case .spEndDisplayList:
            return "spEndDisplayList"
        case .spTexture:
            return "spTexture"
        case .spGeometryMode:
            return "spGeometryMode"
        case .spMoveWord:
            return "spMoveWord"
        case .spMoveMem:
            return "spMoveMem"
        case .spPerspNormalize:
            return "spPerspNormalize"
        case .spClipRatio:
            return "spClipRatio"
        case .spSegment:
            return "spSegment"
        case .spNumLights:
            return "spNumLights"
        case .spLight:
            return "spLight"
        case .spLookAt:
            return "spLookAt"
        case .spViewport:
            return "spViewport"
        case .spForceMatrix:
            return "spForceMatrix"
        case .spLoadUCode:
            return "spLoadUCode"
        case .spLoadUCodeEx:
            return "spLoadUCodeEx"
        case .spBranchLessZ:
            return "spBranchLessZ"
        case .dpNoOp:
            return "dpNoOp"
        case .dpSetOtherMode:
            return "dpSetOtherMode"
        case .dpSetCycleType:
            return "dpSetCycleType"
        case .dpSetTexturePersp:
            return "dpSetTexturePersp"
        case .dpSetTextureDetail:
            return "dpSetTextureDetail"
        case .dpSetTextureLOD:
            return "dpSetTextureLOD"
        case .dpSetTextureLUT:
            return "dpSetTextureLUT"
        case .dpSetTextureFilter:
            return "dpSetTextureFilter"
        case .dpSetTextureConvert:
            return "dpSetTextureConvert"
        case .dpSetCombineKey:
            return "dpSetCombineKey"
        case .dpSetColorDither:
            return "dpSetColorDither"
        case .dpSetAlphaDither:
            return "dpSetAlphaDither"
        case .dpSetAlphaCompare:
            return "dpSetAlphaCompare"
        case .dpSetRenderMode:
            return "dpSetRenderMode"
        case .dpSetCombineMode:
            return "dpSetCombineMode"
        case .dpSetPrimColor:
            return "dpSetPrimColor"
        case .dpSetEnvColor:
            return "dpSetEnvColor"
        case .dpSetFogColor:
            return "dpSetFogColor"
        case .dpSetBlendColor:
            return "dpSetBlendColor"
        case .dpSetFillColor:
            return "dpSetFillColor"
        case .dpSetKeyR:
            return "dpSetKeyR"
        case .dpSetKeyGB:
            return "dpSetKeyGB"
        case .dpSetConvert:
            return "dpSetConvert"
        case .dpSetPrimDepth:
            return "dpSetPrimDepth"
        case .dpSetScissor:
            return "dpSetScissor"
        case .dpSetTextureImage:
            return "dpSetTextureImage"
        case .dpSetDepthImage:
            return "dpSetDepthImage"
        case .dpSetColorImage:
            return "dpSetColorImage"
        case .dpSetTile:
            return "dpSetTile"
        case .dpSetTileSize:
            return "dpSetTileSize"
        case .dpLoadTile:
            return "dpLoadTile"
        case .dpLoadBlock:
            return "dpLoadBlock"
        case .dpLoadTLUT:
            return "dpLoadTLUT"
        case .dpFullSync:
            return "dpFullSync"
        case .dpTileSync:
            return "dpTileSync"
        case .dpPipeSync:
            return "dpPipeSync"
        case .dpLoadSync:
            return "dpLoadSync"
        case .dpTextureRectangle:
            return "dpTextureRectangle"
        case .dpTextureRectangleFlip:
            return "dpTextureRectangleFlip"
        case .dpFillRectangle:
            return "dpFillRectangle"
        }
    }
}

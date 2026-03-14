public enum F3DEX2Command: Codable, Sendable, Equatable {
    case spNoOp
    case spMatrix(MatrixCommand)
    case spPopMatrix(UInt8)
    case spVertex(VertexCommand)
    case spModifyVertex(ModifyVertexCommand)
    case sp1Triangle(TriangleCommand)
    case sp2Triangles(TrianglePairCommand)
    case spLine3D(Line3DCommand)
    case spCullDisplayList(CullDisplayListCommand)
    case spBranchList(UInt32)
    case spDisplayList(UInt32)
    case spEndDisplayList
    case spTexture(TextureState)
    case spGeometryMode(GeometryModeCommand)
    case spMoveWord(MoveWordCommand)
    case spMoveMem(MoveMemCommand)
    case spPerspNormalize(UInt16)
    case spClipRatio(UInt16)
    case spSegment(SegmentCommand)
    case spNumLights(UInt8)
    case spLight(LightCommand)
    case spLookAt(LookAtCommand)
    case spViewport(UInt32)
    case spForceMatrix(UInt32)
    case spLoadUCode(LoadUCodeCommand)
    case spLoadUCodeEx(LoadUCodeExCommand)
    case spBranchLessZ(BranchLessZCommand)
    case dpNoOp
    case dpSetOtherMode(OtherMode)
    case dpSetCycleType(CycleType)
    case dpSetTexturePersp(TexturePerspective)
    case dpSetTextureDetail(TextureDetail)
    case dpSetTextureLOD(TextureLODMode)
    case dpSetTextureLUT(TextureLUTMode)
    case dpSetTextureFilter(TextureFilter)
    case dpSetTextureConvert(TextureConvertMode)
    case dpSetCombineKey(CombineKeyMode)
    case dpSetColorDither(ColorDitherMode)
    case dpSetAlphaDither(AlphaDitherMode)
    case dpSetAlphaCompare(AlphaCompareMode)
    case dpSetRenderMode(RenderMode)
    case dpSetCombineMode(CombineMode)
    case dpSetPrimColor(PrimitiveColor)
    case dpSetEnvColor(RGBA8)
    case dpSetFogColor(RGBA8)
    case dpSetBlendColor(RGBA8)
    case dpSetFillColor(UInt32)
    case dpSetKeyR(KeyRCommand)
    case dpSetKeyGB(KeyGBCommand)
    case dpSetConvert(ConvertCommand)
    case dpSetPrimDepth(PrimDepthCommand)
    case dpSetScissor(ScissorCommand)
    case dpSetTextureImage(ImageDescriptor)
    case dpSetDepthImage(UInt32)
    case dpSetColorImage(ImageDescriptor)
    case dpSetTile(TileDescriptor)
    case dpSetTileSize(TileSizeCommand)
    case dpLoadTile(LoadTileCommand)
    case dpLoadBlock(LoadBlockCommand)
    case dpLoadTLUT(LoadTLUTCommand)
    case dpFullSync
    case dpTileSync
    case dpPipeSync
    case dpLoadSync
    case dpTextureRectangle(TextureRectangleCommand)
    case dpTextureRectangleFlip(TextureRectangleCommand)
    case dpFillRectangle(FillRectangleCommand)
}

public struct MatrixCommand: Codable, Sendable, Equatable {
    public var address: UInt32
    public var projection: Bool
    public var load: Bool
    public var push: Bool

    public init(address: UInt32, projection: Bool, load: Bool, push: Bool) {
        self.address = address
        self.projection = projection
        self.load = load
        self.push = push
    }
}

public struct VertexCommand: Codable, Sendable, Equatable {
    public var address: UInt32
    public var count: UInt16
    public var destinationIndex: UInt16

    public init(address: UInt32, count: UInt16, destinationIndex: UInt16) {
        self.address = address
        self.count = count
        self.destinationIndex = destinationIndex
    }
}

public struct ModifyVertexCommand: Codable, Sendable, Equatable {
    public var vertexIndex: UInt16
    public var attributeOffset: UInt16
    public var value: UInt32

    public init(vertexIndex: UInt16, attributeOffset: UInt16, value: UInt32) {
        self.vertexIndex = vertexIndex
        self.attributeOffset = attributeOffset
        self.value = value
    }
}

public struct TriangleCommand: Codable, Sendable, Equatable {
    public var vertex0: UInt8
    public var vertex1: UInt8
    public var vertex2: UInt8
    public var flag: UInt8

    public init(vertex0: UInt8, vertex1: UInt8, vertex2: UInt8, flag: UInt8 = 0) {
        self.vertex0 = vertex0
        self.vertex1 = vertex1
        self.vertex2 = vertex2
        self.flag = flag
    }
}

public struct TrianglePairCommand: Codable, Sendable, Equatable {
    public var first: TriangleCommand
    public var second: TriangleCommand

    public init(first: TriangleCommand, second: TriangleCommand) {
        self.first = first
        self.second = second
    }
}

public struct Line3DCommand: Codable, Sendable, Equatable {
    public var vertex0: UInt8
    public var vertex1: UInt8
    public var width: UInt8

    public init(vertex0: UInt8, vertex1: UInt8, width: UInt8 = 0) {
        self.vertex0 = vertex0
        self.vertex1 = vertex1
        self.width = width
    }
}

public struct CullDisplayListCommand: Codable, Sendable, Equatable {
    public var firstVertex: UInt16
    public var lastVertex: UInt16

    public init(firstVertex: UInt16, lastVertex: UInt16) {
        self.firstVertex = firstVertex
        self.lastVertex = lastVertex
    }
}

public struct TextureState: Codable, Sendable, Equatable {
    public var scaleS: UInt16
    public var scaleT: UInt16
    public var level: UInt8
    public var tile: UInt8
    public var enabled: Bool

    public init(scaleS: UInt16, scaleT: UInt16, level: UInt8, tile: UInt8, enabled: Bool) {
        self.scaleS = scaleS
        self.scaleT = scaleT
        self.level = level
        self.tile = tile
        self.enabled = enabled
    }
}

public struct GeometryModeCommand: Codable, Sendable, Equatable {
    public var clearBits: UInt32
    public var setBits: UInt32

    public init(clearBits: UInt32, setBits: UInt32) {
        self.clearBits = clearBits
        self.setBits = setBits
    }
}

public struct MoveWordCommand: Codable, Sendable, Equatable {
    public var index: UInt8
    public var offset: UInt16
    public var value: UInt32

    public init(index: UInt8, offset: UInt16, value: UInt32) {
        self.index = index
        self.offset = offset
        self.value = value
    }
}

public struct MoveMemCommand: Codable, Sendable, Equatable {
    public var target: UInt8
    public var offset: UInt16
    public var length: UInt16
    public var address: UInt32

    public init(target: UInt8, offset: UInt16, length: UInt16, address: UInt32) {
        self.target = target
        self.offset = offset
        self.length = length
        self.address = address
    }
}

public struct SegmentCommand: Codable, Sendable, Equatable {
    public var segment: UInt8
    public var baseAddress: UInt32

    public init(segment: UInt8, baseAddress: UInt32) {
        self.segment = segment
        self.baseAddress = baseAddress
    }
}

public struct LightCommand: Codable, Sendable, Equatable {
    public var index: UInt8
    public var color: RGBA8
    public var direction: Vector3s

    public init(index: UInt8, color: RGBA8, direction: Vector3s) {
        self.index = index
        self.color = color
        self.direction = direction
    }
}

public struct LookAtCommand: Codable, Sendable, Equatable {
    public var xAxis: Vector3s
    public var yAxis: Vector3s

    public init(xAxis: Vector3s, yAxis: Vector3s) {
        self.xAxis = xAxis
        self.yAxis = yAxis
    }
}

public struct LoadUCodeCommand: Codable, Sendable, Equatable {
    public var microcodeAddress: UInt32
    public var dataAddress: UInt32

    public init(microcodeAddress: UInt32, dataAddress: UInt32) {
        self.microcodeAddress = microcodeAddress
        self.dataAddress = dataAddress
    }
}

public struct LoadUCodeExCommand: Codable, Sendable, Equatable {
    public var microcodeAddress: UInt32
    public var dataAddress: UInt32
    public var dataSize: UInt16

    public init(microcodeAddress: UInt32, dataAddress: UInt32, dataSize: UInt16) {
        self.microcodeAddress = microcodeAddress
        self.dataAddress = dataAddress
        self.dataSize = dataSize
    }
}

public struct BranchLessZCommand: Codable, Sendable, Equatable {
    public var branchAddress: UInt32
    public var vertexIndex: UInt16
    public var zValue: UInt16

    public init(branchAddress: UInt32, vertexIndex: UInt16, zValue: UInt16) {
        self.branchAddress = branchAddress
        self.vertexIndex = vertexIndex
        self.zValue = zValue
    }
}

public struct OtherMode: Codable, Sendable, Equatable {
    public var high: UInt32
    public var low: UInt32

    public init(high: UInt32, low: UInt32) {
        self.high = high
        self.low = low
    }
}

public enum CycleType: String, Codable, Sendable, CaseIterable {
    case oneCycle
    case twoCycle
    case copy
    case fill
}

public enum TexturePerspective: String, Codable, Sendable, CaseIterable {
    case none
    case perspective
}

public enum TextureDetail: String, Codable, Sendable, CaseIterable {
    case clamp
    case sharpen
    case detail
}

public enum TextureLODMode: String, Codable, Sendable, CaseIterable {
    case tile
    case sharpen
    case detail
}

public enum TextureLUTMode: String, Codable, Sendable, CaseIterable {
    case none
    case rgba16
    case ia16
}

public enum TextureFilter: String, Codable, Sendable, CaseIterable {
    case point
    case bilerp
    case average
}

public enum TextureConvertMode: String, Codable, Sendable, CaseIterable {
    case filter
    case filterBilerp
    case filterAverage
    case key
}

public enum CombineKeyMode: String, Codable, Sendable, CaseIterable {
    case disabled
    case chroma
}

public enum ColorDitherMode: String, Codable, Sendable, CaseIterable {
    case magicSquare
    case bayer
    case noise
    case none
}

public enum AlphaDitherMode: String, Codable, Sendable, CaseIterable {
    case pattern
    case noise
    case none
}

public enum AlphaCompareMode: String, Codable, Sendable, CaseIterable {
    case none
    case threshold
    case dither
}

public struct RenderMode: Codable, Sendable, Equatable, Hashable {
    public var flags: UInt32

    public init(flags: UInt32) {
        self.flags = flags
    }
}

public struct CombineMode: Codable, Sendable, Equatable {
    public var colorMux: UInt32
    public var alphaMux: UInt32

    public init(colorMux: UInt32, alphaMux: UInt32) {
        self.colorMux = colorMux
        self.alphaMux = alphaMux
    }
}

public struct PrimitiveColor: Codable, Sendable, Equatable {
    public var minimumLOD: UInt8
    public var level: UInt8
    public var color: RGBA8

    public init(minimumLOD: UInt8, level: UInt8, color: RGBA8) {
        self.minimumLOD = minimumLOD
        self.level = level
        self.color = color
    }
}

public struct KeyRCommand: Codable, Sendable, Equatable {
    public var center: UInt8
    public var scale: UInt8
    public var width: UInt8

    public init(center: UInt8, scale: UInt8, width: UInt8) {
        self.center = center
        self.scale = scale
        self.width = width
    }
}

public struct KeyGBCommand: Codable, Sendable, Equatable {
    public var centerG: UInt8
    public var scaleG: UInt8
    public var widthG: UInt8
    public var centerB: UInt8
    public var scaleB: UInt8
    public var widthB: UInt8

    public init(
        centerG: UInt8,
        scaleG: UInt8,
        widthG: UInt8,
        centerB: UInt8,
        scaleB: UInt8,
        widthB: UInt8
    ) {
        self.centerG = centerG
        self.scaleG = scaleG
        self.widthG = widthG
        self.centerB = centerB
        self.scaleB = scaleB
        self.widthB = widthB
    }
}

public struct ConvertCommand: Codable, Sendable, Equatable {
    public var k0: Int16
    public var k1: Int16
    public var k2: Int16
    public var k3: Int16
    public var k4: Int16
    public var k5: Int16

    public init(k0: Int16, k1: Int16, k2: Int16, k3: Int16, k4: Int16, k5: Int16) {
        self.k0 = k0
        self.k1 = k1
        self.k2 = k2
        self.k3 = k3
        self.k4 = k4
        self.k5 = k5
    }
}

public struct PrimDepthCommand: Codable, Sendable, Equatable {
    public var z: UInt16
    public var deltaZ: UInt16

    public init(z: UInt16, deltaZ: UInt16) {
        self.z = z
        self.deltaZ = deltaZ
    }
}

public enum ScissorMode: String, Codable, Sendable, CaseIterable {
    case nonInterlace
    case evenInterlace
    case oddInterlace
}

public struct ScissorCommand: Codable, Sendable, Equatable {
    public var mode: ScissorMode
    public var upperLeftX: UInt16
    public var upperLeftY: UInt16
    public var lowerRightX: UInt16
    public var lowerRightY: UInt16

    public init(
        mode: ScissorMode,
        upperLeftX: UInt16,
        upperLeftY: UInt16,
        lowerRightX: UInt16,
        lowerRightY: UInt16
    ) {
        self.mode = mode
        self.upperLeftX = upperLeftX
        self.upperLeftY = upperLeftY
        self.lowerRightX = lowerRightX
        self.lowerRightY = lowerRightY
    }
}

public struct ImageDescriptor: Codable, Sendable, Equatable {
    public var format: TextureFormat
    public var texelSize: TexelSize
    public var width: UInt16
    public var address: UInt32

    public init(format: TextureFormat, texelSize: TexelSize, width: UInt16, address: UInt32) {
        self.format = format
        self.texelSize = texelSize
        self.width = width
        self.address = address
    }
}

public struct TileDescriptor: Codable, Sendable, Equatable {
    public var format: TextureFormat
    public var texelSize: TexelSize
    public var line: UInt16
    public var tmem: UInt16
    public var tile: UInt8
    public var palette: UInt8
    public var clampS: Bool
    public var mirrorS: Bool
    public var maskS: UInt8
    public var shiftS: UInt8
    public var clampT: Bool
    public var mirrorT: Bool
    public var maskT: UInt8
    public var shiftT: UInt8

    public init(
        format: TextureFormat,
        texelSize: TexelSize,
        line: UInt16,
        tmem: UInt16,
        tile: UInt8,
        palette: UInt8,
        clampS: Bool,
        mirrorS: Bool,
        maskS: UInt8,
        shiftS: UInt8,
        clampT: Bool,
        mirrorT: Bool,
        maskT: UInt8,
        shiftT: UInt8
    ) {
        self.format = format
        self.texelSize = texelSize
        self.line = line
        self.tmem = tmem
        self.tile = tile
        self.palette = palette
        self.clampS = clampS
        self.mirrorS = mirrorS
        self.maskS = maskS
        self.shiftS = shiftS
        self.clampT = clampT
        self.mirrorT = mirrorT
        self.maskT = maskT
        self.shiftT = shiftT
    }
}

public struct TileSizeCommand: Codable, Sendable, Equatable {
    public var tile: UInt8
    public var upperLeftS: UInt16
    public var upperLeftT: UInt16
    public var lowerRightS: UInt16
    public var lowerRightT: UInt16

    public init(tile: UInt8, upperLeftS: UInt16, upperLeftT: UInt16, lowerRightS: UInt16, lowerRightT: UInt16) {
        self.tile = tile
        self.upperLeftS = upperLeftS
        self.upperLeftT = upperLeftT
        self.lowerRightS = lowerRightS
        self.lowerRightT = lowerRightT
    }
}

public struct LoadTileCommand: Codable, Sendable, Equatable {
    public var tile: UInt8
    public var upperLeftS: UInt16
    public var upperLeftT: UInt16
    public var lowerRightS: UInt16
    public var lowerRightT: UInt16

    public init(tile: UInt8, upperLeftS: UInt16, upperLeftT: UInt16, lowerRightS: UInt16, lowerRightT: UInt16) {
        self.tile = tile
        self.upperLeftS = upperLeftS
        self.upperLeftT = upperLeftT
        self.lowerRightS = lowerRightS
        self.lowerRightT = lowerRightT
    }
}

public struct LoadBlockCommand: Codable, Sendable, Equatable {
    public var tile: UInt8
    public var upperLeftS: UInt16
    public var upperLeftT: UInt16
    public var texelCount: UInt16
    public var dxt: UInt16

    public init(tile: UInt8, upperLeftS: UInt16, upperLeftT: UInt16, texelCount: UInt16, dxt: UInt16) {
        self.tile = tile
        self.upperLeftS = upperLeftS
        self.upperLeftT = upperLeftT
        self.texelCount = texelCount
        self.dxt = dxt
    }
}

public struct LoadTLUTCommand: Codable, Sendable, Equatable {
    public var tile: UInt8
    public var colorCount: UInt16

    public init(tile: UInt8, colorCount: UInt16) {
        self.tile = tile
        self.colorCount = colorCount
    }
}

public struct TextureRectangleCommand: Codable, Sendable, Equatable {
    public var upperLeftX: UInt16
    public var upperLeftY: UInt16
    public var lowerRightX: UInt16
    public var lowerRightY: UInt16
    public var tile: UInt8
    public var s: Int16
    public var t: Int16
    public var dsdx: Int16
    public var dtdy: Int16

    public init(
        upperLeftX: UInt16,
        upperLeftY: UInt16,
        lowerRightX: UInt16,
        lowerRightY: UInt16,
        tile: UInt8,
        s: Int16,
        t: Int16,
        dsdx: Int16,
        dtdy: Int16
    ) {
        self.upperLeftX = upperLeftX
        self.upperLeftY = upperLeftY
        self.lowerRightX = lowerRightX
        self.lowerRightY = lowerRightY
        self.tile = tile
        self.s = s
        self.t = t
        self.dsdx = dsdx
        self.dtdy = dtdy
    }
}

public struct FillRectangleCommand: Codable, Sendable, Equatable {
    public var upperLeftX: UInt16
    public var upperLeftY: UInt16
    public var lowerRightX: UInt16
    public var lowerRightY: UInt16

    public init(upperLeftX: UInt16, upperLeftY: UInt16, lowerRightX: UInt16, lowerRightY: UInt16) {
        self.upperLeftX = upperLeftX
        self.upperLeftY = upperLeftY
        self.lowerRightX = lowerRightX
        self.lowerRightY = lowerRightY
    }
}

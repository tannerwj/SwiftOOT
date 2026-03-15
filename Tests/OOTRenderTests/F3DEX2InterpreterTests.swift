import Foundation
import Metal
import XCTest
import simd
@testable import OOTDataModel
@testable import OOTRender

final class F3DEX2InterpreterTests: XCTestCase {
    func testInterpretEmitsTrianglesForHandCraftedDisplayList() throws {
        let context = try makeRenderContext()
        var segmentTable = SegmentTable()
        try segmentTable.setSegment(0x01, data: encodeVertices(makeQuadVertices()))
        let combineMode = CombineMode(
            colorMux: 0x0017_24C0,
            alphaMux: 0x0F0A_5097
        )

        let interpreter = F3DEX2Interpreter(
            segmentTable: segmentTable,
            drawBatchResources: context.resources
        )

        try interpreter.interpret(
            [
                .dpSetCombineMode(combineMode),
                .spVertex(VertexCommand(address: 0x0100_0000, count: 4, destinationIndex: 0)),
                .sp2Triangles(
                    TrianglePairCommand(
                        first: TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2),
                        second: TriangleCommand(vertex0: 0, vertex1: 2, vertex2: 3)
                    )
                ),
                .spEndDisplayList,
            ],
            encoder: context.encoder
        )

        context.encoder.endEncoding()
        context.commandBuffer.commit()
        context.commandBuffer.waitUntilCompleted()

        XCTAssertEqual(interpreter.drawBatch.totalTriangleCount, 2)
        XCTAssertEqual(interpreter.drawBatch.pendingTriangleCount, 0)
        XCTAssertEqual(interpreter.drawBatch.drawCallCount, 1)
        XCTAssertEqual(interpreter.rdpState.combineMode.firstCycle.color.a, 1)
        XCTAssertTrue(interpreter.warnings.isEmpty)
    }

    func testNestedDisplayListResumesCallerAfterReturn() throws {
        let context = try makeRenderContext()
        var segmentTable = SegmentTable()
        try segmentTable.setSegment(0x01, data: encodeVertices(makeTriangleVertices()))
        let nestedAddress: UInt32 = 0x0A00_0040
        let interpreter = F3DEX2Interpreter(
            segmentTable: segmentTable,
            drawBatchResources: context.resources,
            displayListResolver: { address in
                guard address == nestedAddress else {
                    return nil
                }

                return [
                    .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2)),
                    .spEndDisplayList,
                ]
            }
        )

        try interpreter.interpret(
            [
                .spVertex(VertexCommand(address: 0x0100_0000, count: 3, destinationIndex: 0)),
                .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2)),
                .spDisplayList(nestedAddress),
                .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2)),
                .spEndDisplayList,
            ],
            encoder: context.encoder
        )

        context.encoder.endEncoding()
        context.commandBuffer.commit()
        context.commandBuffer.waitUntilCompleted()

        XCTAssertEqual(interpreter.drawBatch.totalTriangleCount, 3)
        XCTAssertEqual(interpreter.drawBatch.drawCallCount, 1)
        XCTAssertTrue(interpreter.warnings.isEmpty)
    }

    func testMatrixStackPushMultiplyAndPopAffectVertexTransforms() throws {
        let context = try makeRenderContext()
        var segmentTable = SegmentTable()
        try segmentTable.setSegment(0x01, data: encodeMatrices([makeTranslationMatrix(), makeScaleMatrix()]))
        try segmentTable.setSegment(0x02, data: encodeVertices([makeUnitVertex()]))

        let interpreter = F3DEX2Interpreter(
            segmentTable: segmentTable,
            drawBatchResources: context.resources
        )

        try interpreter.interpret(
            [
                .spMatrix(
                    MatrixCommand(
                        address: 0x0100_0000,
                        projection: false,
                        load: true,
                        push: false
                    )
                ),
                .spMatrix(
                    MatrixCommand(
                        address: 0x0100_0040,
                        projection: false,
                        load: false,
                        push: true
                    )
                ),
                .spVertex(VertexCommand(address: 0x0200_0000, count: 1, destinationIndex: 0)),
                .spPopMatrix(0),
                .spVertex(VertexCommand(address: 0x0200_0000, count: 1, destinationIndex: 1)),
                .spEndDisplayList,
            ],
            encoder: context.encoder
        )

        context.encoder.endEncoding()
        context.commandBuffer.commit()
        context.commandBuffer.waitUntilCompleted()

        let scaledThenTranslated = try XCTUnwrap(try interpreter.rspState.vertex(at: 0))
        let translatedOnly = try XCTUnwrap(try interpreter.rspState.vertex(at: 1))

        XCTAssertEqual(interpreter.rspState.matrixStack.depth, 1)
        XCTAssertEqual(
            scaledThenTranslated.clipPosition,
            SIMD4<Float>(7, 9, 11, 1)
        )
        XCTAssertEqual(
            translatedOnly.clipPosition,
            SIMD4<Float>(3, 4, 5, 1)
        )
    }

    func testUnsupportedCommandIsLoggedAndSkippedWithoutCrashing() throws {
        let context = try makeRenderContext()
        let interpreter = F3DEX2Interpreter(drawBatchResources: context.resources)

        try interpreter.interpret(
            [
                .spModifyVertex(
                    ModifyVertexCommand(
                        vertexIndex: 1,
                        attributeOffset: 0,
                        value: 0xDEAD_BEEF
                    )
                ),
                .spEndDisplayList,
            ],
            encoder: context.encoder
        )

        context.encoder.endEncoding()
        context.commandBuffer.commit()
        context.commandBuffer.waitUntilCompleted()

        XCTAssertEqual(interpreter.drawBatch.totalTriangleCount, 0)
        XCTAssertEqual(interpreter.warnings.count, 1)
        XCTAssertTrue(interpreter.warnings[0].contains("spModifyVertex"))
    }
}

private extension F3DEX2InterpreterTests {
    struct RenderContext {
        let commandBuffer: MTLCommandBuffer
        let encoder: MTLRenderCommandEncoder
        let resources: DrawBatchResources
    }

    func makeRenderContext() throws -> RenderContext {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let renderStateKey = RenderStateKey(
            combinerHash: 0,
            geometryMode: [],
            renderMode: RenderMode(flags: 0)
        )
        let pipelineState = try makeDrawBatchPipelineState(
            device: device,
            renderStateKey: renderStateKey
        )
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .lessEqual
        depthStencilDescriptor.isDepthWriteEnabled = true
        let depthStencilState = try XCTUnwrap(
            device.makeDepthStencilState(descriptor: depthStencilDescriptor)
        )
        let fallbackTexture = try makeSourceTexture(device: device)
        let resources = DrawBatchResources(
            device: device,
            pipelineLookup: AnyRenderPipelineStateLookup { _ in pipelineState },
            depthStencilLookup: AnyDepthStencilStateLookup { _ in depthStencilState },
            fallbackTexture: fallbackTexture
        )
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 64,
            height: 64,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.storageMode = .shared

        let texture = try XCTUnwrap(device.makeTexture(descriptor: textureDescriptor))
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let encoder = try XCTUnwrap(
            commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        )

        return RenderContext(
            commandBuffer: commandBuffer,
            encoder: encoder,
            resources: resources
        )
    }

    func makeTriangleVertices() -> [N64Vertex] {
        [
            N64Vertex(
                position: Vector3s(x: -8, y: -8, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 0, y: 0),
                colorOrNormal: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)
            ),
            N64Vertex(
                position: Vector3s(x: 8, y: -8, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 32, y: 0),
                colorOrNormal: RGBA8(red: 0, green: 255, blue: 0, alpha: 255)
            ),
            N64Vertex(
                position: Vector3s(x: 0, y: 8, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 16, y: 32),
                colorOrNormal: RGBA8(red: 0, green: 0, blue: 255, alpha: 255)
            ),
        ]
    }

    func makeSourceTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    func makeQuadVertices() -> [N64Vertex] {
        [
            N64Vertex(
                position: Vector3s(x: -8, y: -8, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 0, y: 0),
                colorOrNormal: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)
            ),
            N64Vertex(
                position: Vector3s(x: 8, y: -8, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 32, y: 0),
                colorOrNormal: RGBA8(red: 0, green: 255, blue: 0, alpha: 255)
            ),
            N64Vertex(
                position: Vector3s(x: 8, y: 8, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 32, y: 32),
                colorOrNormal: RGBA8(red: 0, green: 0, blue: 255, alpha: 255)
            ),
            N64Vertex(
                position: Vector3s(x: -8, y: 8, z: 0),
                flag: 0,
                textureCoordinate: Vector2s(x: 0, y: 32),
                colorOrNormal: RGBA8(red: 255, green: 255, blue: 0, alpha: 255)
            ),
        ]
    }

    func makeUnitVertex() -> N64Vertex {
        N64Vertex(
            position: Vector3s(x: 1, y: 1, z: 1),
            flag: 0,
            textureCoordinate: Vector2s(x: 0, y: 0),
            colorOrNormal: RGBA8(red: 255, green: 255, blue: 255, alpha: 255)
        )
    }

    func makeTranslationMatrix() -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(2, 3, 4, 1)
        )
    }

    func makeScaleMatrix() -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(5, 0, 0, 0),
            SIMD4<Float>(0, 6, 0, 0),
            SIMD4<Float>(0, 0, 7, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    func encodeVertices(_ vertices: [N64Vertex]) -> Data {
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

    func encodeMatrices(_ matrices: [simd_float4x4]) -> Data {
        var data = Data()
        data.reserveCapacity(matrices.count * 64)

        for matrix in matrices {
            var highWords: [UInt16] = []
            var lowWords: [UInt16] = []
            highWords.reserveCapacity(16)
            lowWords.reserveCapacity(16)

            for column in 0..<4 {
                for row in 0..<4 {
                    let fixedPoint = Int32((matrix[column][row] * 65_536.0).rounded())
                    highWords.append(UInt16(bitPattern: Int16(truncatingIfNeeded: fixedPoint >> 16)))
                    lowWords.append(UInt16(truncatingIfNeeded: fixedPoint))
                }
            }

            for word in highWords {
                data.append(bigEndian: word)
            }
            for word in lowWords {
                data.append(bigEndian: word)
            }
        }

        return data
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(bigEndian value: T) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { bytes in
            append(contentsOf: bytes)
        }
    }
}

import Metal
import XCTest
import OOTDataModel
import simd
@testable import OOTRender

final class SkelAnimeRendererTests: XCTestCase {
    func testAnimationStateAdvancesWithLoopAndHoldModes() {
        let animation = ObjectAnimationData(
            name: "AdvanceAnim",
            kind: .standard,
            frameCount: 2,
            values: [],
            jointIndices: []
        )

        let loopingState = OOTSkeletonAnimationState(
            animation: animation,
            currentFrame: 1.5,
            playbackSpeed: 1,
            playbackMode: .loop
        )
        let holdingState = OOTSkeletonAnimationState(
            animation: animation,
            currentFrame: 1.5,
            playbackSpeed: 1,
            playbackMode: .hold
        )

        XCTAssertEqual(loopingState.advanced(by: 1).currentFrame, 0.5, accuracy: 0.000_1)
        XCTAssertEqual(holdingState.advanced(by: 1).currentFrame, 1.0, accuracy: 0.000_1)
    }

    func testAnimationStateSamplesStandardAndPlayerFormatsWithInterpolationAndMorphing() {
        let skeleton = makeSkeleton()
        let jointIndices = [
            AnimationJointIndex(x: 0, y: 2, z: 4),
            AnimationJointIndex(x: 6, y: 8, z: 10),
            AnimationJointIndex(x: 12, y: 14, z: 16),
        ]
        let baseAnimation = ObjectAnimationData(
            name: "Base",
            kind: .standard,
            frameCount: 2,
            values: [
                0, 20,
                0, 0,
                0, 0,
                0, 0,
                0, 0,
                0, 16_384,
                0, 0,
                0, 0,
                0, 0,
            ],
            jointIndices: jointIndices,
            staticIndexMax: 0
        )
        let morphAnimation = ObjectAnimationData(
            name: "Morph",
            kind: .standard,
            frameCount: 2,
            values: [
                0, 20,
                0, 0,
                0, 0,
                0, 0,
                0, 0,
                0, 32_767,
                0, 0,
                0, 0,
                0, 0,
            ],
            jointIndices: jointIndices,
            staticIndexMax: 0
        )
        let standardState = OOTSkeletonAnimationState(
            animation: baseAnimation,
            currentFrame: 0.5,
            playbackMode: .hold,
            morphAnimation: morphAnimation,
            morphWeight: 0.5
        )

        let standardPose = standardState.sampledPose(for: skeleton)
        XCTAssertEqual(standardPose.rootTranslation.x, 10, accuracy: 0.000_1)
        XCTAssertEqual(standardPose.limbRotations[0].z, 12_287.75, accuracy: 0.001)

        let playerAnimation = ObjectAnimationData(
            name: "Player",
            kind: .player,
            frameCount: 2,
            values: [
                0, 0, 0, 0, 0, 0, 0,
                10, 100, 200, 300, 400, 500, 600,
            ],
            limbCount: 2
        )
        let playerState = OOTSkeletonAnimationState(
            animation: playerAnimation,
            currentFrame: 0.5,
            playbackMode: .hold
        )

        let playerPose = playerState.sampledPose(for: skeleton)
        XCTAssertEqual(playerPose.rootTranslation.y, 5, accuracy: 0.000_1)
        XCTAssertEqual(playerPose.limbRotations[0].x, 50, accuracy: 0.000_1)
        XCTAssertEqual(playerPose.limbRotations[1].z, 300, accuracy: 0.000_1)
    }

    func testPlanDrawCommandsTraversesHierarchyAndAppliesCallbacks() throws {
        let context = try makeRenderContext()
        defer {
            context.encoder.endEncoding()
            context.commandBuffer.commit()
            context.commandBuffer.waitUntilCompleted()
        }
        let renderer = SkelAnimeRenderer(drawBatchResources: context.resources)
        let skeletonEntry = makeSkeletonEntry()

        let commands = try renderer.planDrawCommands(
            for: skeletonEntry,
            overrideLimbDraw: { command in
                guard command.limbIndex == 1 else {
                    return command
                }

                var overridden = command
                overridden.translation += SIMD3<Float>(0, 2, 0)
                overridden.displayListPath = "green-root"
                return overridden
            }
        )

        XCTAssertEqual(commands.map(\.limbIndex), [0, 1])
        XCTAssertEqual(commands[0].displayListPath, "red-root")
        XCTAssertEqual(commands[1].displayListPath, "green-root")
        XCTAssertEqual(commands[0].modelMatrix.columns.3.x, -2, accuracy: 0.000_1)
        XCTAssertEqual(commands[1].modelMatrix.columns.3.x, 2, accuracy: 0.000_1)
        XCTAssertEqual(commands[1].modelMatrix.columns.3.y, 2, accuracy: 0.000_1)
    }

    func testRendererInvokesCallbacksAndDrawsSkeletonsAlongsideRooms() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal is unavailable on this host")
        }

        let callbackContext = try makeRenderContext()
        let skelAnimeRenderer = SkelAnimeRenderer(drawBatchResources: callbackContext.resources)
        let callbackEntry = makeSkeletonEntry()
        let postDrawRecorder = PostDrawRecorder()

        let callbackCommands = try skelAnimeRenderer.render(
            callbackEntry,
            encoder: callbackContext.encoder,
            projectionMatrix: makeScaleMatrix(x: 0.25, y: 0.25),
            overrideLimbDraw: { command in
                var overridden = command
                if overridden.limbIndex == 0 {
                    overridden.displayListPath = "green-root"
                } else if overridden.limbIndex == 1 {
                    overridden.skipDraw = true
                }
                return overridden
            },
            postLimbDraw: { command in
                postDrawRecorder.limbIndices.append(command.limbIndex)
            }
        )

        callbackContext.encoder.endEncoding()
        callbackContext.commandBuffer.commit()
        callbackContext.commandBuffer.waitUntilCompleted()

        XCTAssertEqual(callbackCommands[0].displayListPath, "green-root")
        XCTAssertTrue(callbackCommands[1].skipDraw)
        XCTAssertEqual(postDrawRecorder.limbIndices, [0, 1])

        let room = OOTRenderRoom(
            name: "RoomTriangle",
            displayList: makeDisplayList(
                address: 0x0300_0000,
                vertexCount: 3
            ),
            vertexData: encodeVertices([
                makeTriangleVertex(x: -1, y: -1, color: RGBA8(red: 0, green: 255, blue: 0, alpha: 255)),
                makeTriangleVertex(x: 1, y: -1, color: RGBA8(red: 0, green: 255, blue: 0, alpha: 255)),
                makeTriangleVertex(x: 0, y: 1, color: RGBA8(red: 0, green: 255, blue: 0, alpha: 255)),
            ])
        )
        let scene = OOTRenderScene(
            rooms: [room],
            skeletons: [makeSkeletonEntry()],
            skyColor: SIMD4<Float>(0, 0, 0, 1)
        )
        let renderer = try OOTRenderer(scene: scene)
        let texture = try makeRenderTargetTexture(renderer: renderer)

        try renderer.renderCurrentSceneToTexture(
            texture,
            frameUniforms: FrameUniforms(mvp: makeScaleMatrix(x: 0.25, y: 0.25))
        )

        XCTAssertEqual(pixel(in: texture, x: 16, y: 32), [0, 0, 255, 255])
        XCTAssertEqual(pixel(in: texture, x: 32, y: 32), [0, 255, 0, 255])
        XCTAssertEqual(pixel(in: texture, x: 48, y: 32), [255, 0, 0, 255])
    }
}

private extension SkelAnimeRendererTests {
    struct RenderContext {
        let commandBuffer: MTLCommandBuffer
        let encoder: MTLRenderCommandEncoder
        let resources: DrawBatchResources
    }

    final class PostDrawRecorder: @unchecked Sendable {
        var limbIndices: [Int] = []
    }

    func makeSkeleton() -> SkeletonData {
        SkeletonData(
            type: .flex,
            limbs: [
                LimbData(
                    translation: Vector3s(x: -2, y: 0, z: 0),
                    childIndex: 1,
                    displayListPath: "red-root"
                ),
                LimbData(
                    translation: Vector3s(x: 4, y: 0, z: 0),
                    displayListPath: "blue-child",
                    lowDetailDisplayListPath: "green-root"
                ),
            ]
        )
    }

    func makeSkeletonEntry() -> OOTRenderSkeleton {
        let vertices = [
            makeTriangleVertex(x: -1, y: -1, color: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)),
            makeTriangleVertex(x: 1, y: -1, color: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)),
            makeTriangleVertex(x: 0, y: 1, color: RGBA8(red: 255, green: 0, blue: 0, alpha: 255)),
            makeTriangleVertex(x: -1, y: -1, color: RGBA8(red: 0, green: 0, blue: 255, alpha: 255)),
            makeTriangleVertex(x: 1, y: -1, color: RGBA8(red: 0, green: 0, blue: 255, alpha: 255)),
            makeTriangleVertex(x: 0, y: 1, color: RGBA8(red: 0, green: 0, blue: 255, alpha: 255)),
            makeTriangleVertex(x: -1, y: -1, color: RGBA8(red: 0, green: 255, blue: 0, alpha: 255)),
            makeTriangleVertex(x: 1, y: -1, color: RGBA8(red: 0, green: 255, blue: 0, alpha: 255)),
            makeTriangleVertex(x: 0, y: 1, color: RGBA8(red: 0, green: 255, blue: 0, alpha: 255)),
        ]
        let asset = OOTRenderSkeletonAsset(
            displayListsByPath: [
                "red-root": makeDisplayList(address: 0x0600_0000, vertexCount: 3),
                "blue-child": makeDisplayList(address: 0x0600_0030, vertexCount: 3),
                "green-root": makeDisplayList(address: 0x0600_0060, vertexCount: 3),
            ],
            segmentData: [
                0x06: encodeVertices(vertices),
            ]
        )

        return OOTRenderSkeleton(
            name: "LinkLikeSkeleton",
            skeleton: makeSkeleton(),
            asset: asset
        )
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

        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: texture.width,
            height: texture.height,
            mipmapped: false
        )
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .shared
        renderPassDescriptor.depthAttachment.texture = try XCTUnwrap(
            device.makeTexture(descriptor: depthDescriptor)
        )
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        renderPassDescriptor.depthAttachment.clearDepth = 1.0

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

    func makeRenderTargetTexture(renderer: OOTRenderer) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 64,
            height: 64,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return try XCTUnwrap(renderer.device.makeTexture(descriptor: descriptor))
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

    func makeTriangleVertex(x: Int16, y: Int16, color: RGBA8) -> N64Vertex {
        N64Vertex(
            position: Vector3s(x: x, y: y, z: 0),
            flag: 0,
            textureCoordinate: Vector2s(x: 0, y: 0),
            colorOrNormal: color
        )
    }

    func makeDisplayList(address: UInt32, vertexCount: UInt16) -> [F3DEX2Command] {
        [
            .spVertex(
                VertexCommand(
                    address: address,
                    count: vertexCount,
                    destinationIndex: 0
                )
            ),
            .sp1Triangle(TriangleCommand(vertex0: 0, vertex1: 1, vertex2: 2)),
            .spEndDisplayList,
        ]
    }

    func encodeVertices(_ vertices: [N64Vertex]) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(vertices.count * MemoryLayout<N64Vertex>.stride)

        for vertex in vertices {
            append(&bytes, vertex.position.x)
            append(&bytes, vertex.position.y)
            append(&bytes, vertex.position.z)
            append(&bytes, vertex.flag)
            append(&bytes, vertex.textureCoordinate.x)
            append(&bytes, vertex.textureCoordinate.y)
            bytes.append(vertex.colorOrNormal.red)
            bytes.append(vertex.colorOrNormal.green)
            bytes.append(vertex.colorOrNormal.blue)
            bytes.append(vertex.colorOrNormal.alpha)
        }

        return Data(bytes)
    }

    func append<T: FixedWidthInteger>(_ bytes: inout [UInt8], _ value: T) {
        let bigEndianValue = value.bigEndian
        withUnsafeBytes(of: bigEndianValue) { buffer in
            bytes.append(contentsOf: buffer)
        }
    }

    func makeScaleMatrix(x: Float, y: Float) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(x, 0.0, 0.0, 0.0),
            SIMD4<Float>(0.0, y, 0.0, 0.0),
            SIMD4<Float>(0.0, 0.0, 1.0, 0.0),
            SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
        )
    }

    func pixel(in texture: MTLTexture, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            texture.getBytes(
                buffer.baseAddress!,
                bytesPerRow: 4,
                from: MTLRegionMake2D(x, y, 1, 1),
                mipmapLevel: 0
            )
        }
        return pixel
    }
}

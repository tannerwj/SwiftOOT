import Metal
import OOTDataModel
import simd

public enum SkelAnimationPlaybackMode: String, Sendable, Equatable, CaseIterable {
    case loop
    case hold
}

public struct SkelAnimationPose: Sendable, Equatable {
    public var rootTranslation: SIMD3<Float>
    public var limbRotations: [SIMD3<Float>]

    public init(
        rootTranslation: SIMD3<Float> = .zero,
        limbRotations: [SIMD3<Float>] = []
    ) {
        self.rootTranslation = rootTranslation
        self.limbRotations = limbRotations
    }
}

public struct OOTSkeletonAnimationState: Sendable, Equatable {
    public var animation: ObjectAnimationData?
    public var currentFrame: Float
    public var playbackSpeed: Float
    public var playbackMode: SkelAnimationPlaybackMode
    public var morphAnimation: ObjectAnimationData?
    public var morphWeight: Float

    public init(
        animation: ObjectAnimationData? = nil,
        currentFrame: Float = 0,
        playbackSpeed: Float = 1,
        playbackMode: SkelAnimationPlaybackMode = .loop,
        morphAnimation: ObjectAnimationData? = nil,
        morphWeight: Float = 0
    ) {
        self.animation = animation
        self.currentFrame = currentFrame
        self.playbackSpeed = playbackSpeed
        self.playbackMode = playbackMode
        self.morphAnimation = morphAnimation
        self.morphWeight = morphWeight
    }

    public func advanced(by deltaFrames: Float) -> OOTSkeletonAnimationState {
        var advancedState = self
        advancedState.currentFrame = clampedFrame(
            currentFrame + (deltaFrames * playbackSpeed),
            frameCount: animation?.frameCount ?? morphAnimation?.frameCount ?? 0,
            playbackMode: playbackMode
        )
        return advancedState
    }

    public func sampledPose(for skeleton: SkeletonData) -> SkelAnimationPose {
        let basePose = samplePose(
            animation: animation,
            currentFrame: currentFrame,
            playbackMode: playbackMode,
            limbCount: skeleton.limbs.count
        )

        guard let morphAnimation, morphWeight > 0 else {
            return basePose
        }

        let targetPose = samplePose(
            animation: morphAnimation,
            currentFrame: currentFrame,
            playbackMode: playbackMode,
            limbCount: skeleton.limbs.count
        )
        return blendPoses(basePose, targetPose, weight: morphWeight)
    }
}

public struct OOTRenderSkeletonAsset: Sendable, Equatable {
    public var displayListsByPath: [String: [F3DEX2Command]]
    public var displayListsByAddress: [UInt32: [F3DEX2Command]]
    public var segmentData: [UInt8: Data]

    public init(
        displayListsByPath: [String: [F3DEX2Command]] = [:],
        displayListsByAddress: [UInt32: [F3DEX2Command]] = [:],
        segmentData: [UInt8: Data] = [:]
    ) {
        self.displayListsByPath = displayListsByPath
        self.displayListsByAddress = displayListsByAddress
        self.segmentData = segmentData
    }
}

public struct OOTRenderSkeleton: Sendable, Equatable {
    public var name: String
    public var skeleton: SkeletonData
    public var asset: OOTRenderSkeletonAsset
    public var animationState: OOTSkeletonAnimationState
    public var modelMatrix: simd_float4x4
    public var rootLimbIndex: Int
    public var useLowDetailDisplayLists: Bool

    public init(
        name: String,
        skeleton: SkeletonData,
        asset: OOTRenderSkeletonAsset,
        animationState: OOTSkeletonAnimationState = OOTSkeletonAnimationState(),
        modelMatrix: simd_float4x4 = matrix_identity_float4x4,
        rootLimbIndex: Int = 0,
        useLowDetailDisplayLists: Bool = false
    ) {
        self.name = name
        self.skeleton = skeleton
        self.asset = asset
        self.animationState = animationState
        self.modelMatrix = modelMatrix
        self.rootLimbIndex = rootLimbIndex
        self.useLowDetailDisplayLists = useLowDetailDisplayLists
    }
}

public struct SkelLimbDrawCommand: Sendable, Equatable {
    public var limbIndex: Int
    public var translation: SIMD3<Float>
    public var rotation: SIMD3<Float>
    public var modelMatrix: simd_float4x4
    public var displayListPath: String?
    public var useLowDetailDisplayList: Bool
    public var skipDraw: Bool

    public init(
        limbIndex: Int,
        translation: SIMD3<Float>,
        rotation: SIMD3<Float>,
        modelMatrix: simd_float4x4,
        displayListPath: String?,
        useLowDetailDisplayList: Bool = false,
        skipDraw: Bool = false
    ) {
        self.limbIndex = limbIndex
        self.translation = translation
        self.rotation = rotation
        self.modelMatrix = modelMatrix
        self.displayListPath = displayListPath
        self.useLowDetailDisplayList = useLowDetailDisplayList
        self.skipDraw = skipDraw
    }
}

public enum SkelAnimeRendererError: Error, Sendable, Equatable {
    case invalidRootLimbIndex(Int)
    case missingDisplayList(String)
}

public final class SkelAnimeRenderer {
    public typealias OverrideLimbDraw = @Sendable (SkelLimbDrawCommand) -> SkelLimbDrawCommand
    public typealias PostLimbDraw = @Sendable (SkelLimbDrawCommand) -> Void

    private let drawBatchResources: DrawBatchResources

    public init(drawBatchResources: DrawBatchResources) {
        self.drawBatchResources = drawBatchResources
    }

    @discardableResult
    public func render(
        _ skeletonEntry: OOTRenderSkeleton,
        encoder: MTLRenderCommandEncoder,
        projectionMatrix: simd_float4x4,
        overrideLimbDraw: OverrideLimbDraw? = nil,
        postLimbDraw: PostLimbDraw? = nil
    ) throws -> [SkelLimbDrawCommand] {
        let drawCommands = try planDrawCommands(
            for: skeletonEntry,
            overrideLimbDraw: overrideLimbDraw
        )
        let interpreter = F3DEX2Interpreter(
            segmentTable: try makeSegmentTable(for: skeletonEntry, drawCommands: drawCommands),
            projectionMatrix: projectionMatrix,
            drawBatchResources: drawBatchResources,
            displayListResolver: { skeletonEntry.asset.displayListsByAddress[$0] }
        )

        for command in drawCommands {
            guard command.skipDraw == false else {
                postLimbDraw?(command)
                continue
            }

            guard let displayListPath = command.displayListPath else {
                postLimbDraw?(command)
                continue
            }
            guard let displayList = skeletonEntry.asset.displayListsByPath[displayListPath] else {
                throw SkelAnimeRendererError.missingDisplayList(displayListPath)
            }

            let matrixAddress = matrixSegmentAddress(for: command.limbIndex)
            try interpreter.interpret(
                [
                    .spMatrix(
                        MatrixCommand(
                            address: matrixAddress,
                            projection: false,
                            load: true,
                            push: false
                        )
                    ),
                ] + displayList,
                encoder: encoder
            )
            postLimbDraw?(command)
        }

        try interpreter.flush(encoder: encoder)
        return drawCommands
    }

    func planDrawCommands(
        for skeletonEntry: OOTRenderSkeleton,
        overrideLimbDraw: OverrideLimbDraw? = nil
    ) throws -> [SkelLimbDrawCommand] {
        guard skeletonEntry.skeleton.limbs.indices.contains(skeletonEntry.rootLimbIndex) else {
            throw SkelAnimeRendererError.invalidRootLimbIndex(skeletonEntry.rootLimbIndex)
        }

        guard skeletonEntry.skeleton.limbs.isEmpty == false else {
            return []
        }

        let pose = skeletonEntry.animationState.sampledPose(for: skeletonEntry.skeleton)
        var drawCommands: [SkelLimbDrawCommand] = []

        try appendDrawCommands(
            startingAt: skeletonEntry.rootLimbIndex,
            parentMatrix: skeletonEntry.modelMatrix,
            skeletonEntry: skeletonEntry,
            pose: pose,
            overrideLimbDraw: overrideLimbDraw,
            drawCommands: &drawCommands
        )

        return drawCommands
    }
}

private struct FrameSample {
    let lowerFrame: Int
    let upperFrame: Int
    let fraction: Float
}

private extension OOTSkeletonAnimationState {
    func samplePose(
        animation: ObjectAnimationData?,
        currentFrame: Float,
        playbackMode: SkelAnimationPlaybackMode,
        limbCount: Int
    ) -> SkelAnimationPose {
        guard let animation else {
            return SkelAnimationPose(
                rootTranslation: .zero,
                limbRotations: Array(repeating: .zero, count: limbCount)
            )
        }

        let frameSample = framePair(
            frame: currentFrame,
            frameCount: animation.frameCount,
            playbackMode: playbackMode
        )

        switch animation.kind {
        case .standard:
            return sampleStandardPose(
                animation: animation,
                frameSample: frameSample,
                limbCount: limbCount
            )
        case .player:
            return samplePlayerPose(
                animation: animation,
                frameSample: frameSample,
                limbCount: limbCount
            )
        }
    }

    func sampleStandardPose(
        animation: ObjectAnimationData,
        frameSample: FrameSample,
        limbCount: Int
    ) -> SkelAnimationPose {
        let jointIndices = animation.jointIndices
        let rootTranslation: SIMD3<Float>
        var limbRotations = Array(repeating: SIMD3<Float>.zero, count: limbCount)

        if jointIndices.count >= (limbCount + 1) {
            rootTranslation = sampleTrack(
                jointIndices[0],
                animation: animation,
                frameSample: frameSample
            )

            for limbIndex in 0..<limbCount {
                limbRotations[limbIndex] = sampleTrack(
                    jointIndices[limbIndex + 1],
                    animation: animation,
                    frameSample: frameSample
                )
            }
        } else {
            rootTranslation = .zero
            for limbIndex in 0..<min(limbCount, jointIndices.count) {
                limbRotations[limbIndex] = sampleTrack(
                    jointIndices[limbIndex],
                    animation: animation,
                    frameSample: frameSample
                )
            }
        }

        return SkelAnimationPose(
            rootTranslation: rootTranslation,
            limbRotations: limbRotations
        )
    }

    func samplePlayerPose(
        animation: ObjectAnimationData,
        frameSample: FrameSample,
        limbCount: Int
    ) -> SkelAnimationPose {
        let sampledLimbCount = animation.limbCount ?? limbCount
        let stride = max(1 + (sampledLimbCount * 3), 0)
        guard stride > 0 else {
            return SkelAnimationPose(
                rootTranslation: .zero,
                limbRotations: Array(repeating: .zero, count: limbCount)
            )
        }

        let lowerBase = frameSample.lowerFrame * stride
        let upperBase = frameSample.upperFrame * stride
        var limbRotations = Array(repeating: SIMD3<Float>.zero, count: limbCount)

        for limbIndex in 0..<min(limbCount, sampledLimbCount) {
            let rotationBase = 1 + (limbIndex * 3)
            limbRotations[limbIndex] = SIMD3<Float>(
                interpolatePlayerValue(
                    animation.values,
                    lowerBase: lowerBase,
                    upperBase: upperBase,
                    offset: rotationBase,
                    fraction: frameSample.fraction
                ),
                interpolatePlayerValue(
                    animation.values,
                    lowerBase: lowerBase,
                    upperBase: upperBase,
                    offset: rotationBase + 1,
                    fraction: frameSample.fraction
                ),
                interpolatePlayerValue(
                    animation.values,
                    lowerBase: lowerBase,
                    upperBase: upperBase,
                    offset: rotationBase + 2,
                    fraction: frameSample.fraction
                )
            )
        }

        return SkelAnimationPose(
            // Link animation headers only carry a root Y translation in the extracted format.
            rootTranslation: SIMD3<Float>(
                0,
                interpolatePlayerValue(
                    animation.values,
                    lowerBase: lowerBase,
                    upperBase: upperBase,
                    offset: 0,
                    fraction: frameSample.fraction
                ),
                0
            ),
            limbRotations: limbRotations
        )
    }

    func sampleTrack(
        _ jointIndex: AnimationJointIndex,
        animation: ObjectAnimationData,
        frameSample: FrameSample
    ) -> SIMD3<Float> {
        SIMD3<Float>(
            sampleStandardValue(
                at: jointIndex.x,
                animation: animation,
                frameSample: frameSample
            ),
            sampleStandardValue(
                at: jointIndex.y,
                animation: animation,
                frameSample: frameSample
            ),
            sampleStandardValue(
                at: jointIndex.z,
                animation: animation,
                frameSample: frameSample
            )
        )
    }

    func sampleStandardValue(
        at valueIndex: Int,
        animation: ObjectAnimationData,
        frameSample: FrameSample
    ) -> Float {
        guard valueIndex >= 0 else {
            return 0
        }

        if let staticIndexMax = animation.staticIndexMax, valueIndex < staticIndexMax {
            return animation.values.indices.contains(valueIndex)
                ? Float(animation.values[valueIndex])
                : 0
        }

        let lowerIndex = valueIndex + frameSample.lowerFrame
        let upperIndex = valueIndex + frameSample.upperFrame
        let lowerValue = animation.values.indices.contains(lowerIndex) ? Float(animation.values[lowerIndex]) : 0
        let upperValue = animation.values.indices.contains(upperIndex) ? Float(animation.values[upperIndex]) : lowerValue
        return interpolate(lowerValue, upperValue, fraction: frameSample.fraction)
    }

    func interpolatePlayerValue(
        _ values: [Int16],
        lowerBase: Int,
        upperBase: Int,
        offset: Int,
        fraction: Float
    ) -> Float {
        let lowerIndex = lowerBase + offset
        let upperIndex = upperBase + offset
        let lowerValue = values.indices.contains(lowerIndex) ? Float(values[lowerIndex]) : 0
        let upperValue = values.indices.contains(upperIndex) ? Float(values[upperIndex]) : lowerValue
        return interpolate(lowerValue, upperValue, fraction: fraction)
    }

    func blendPoses(
        _ basePose: SkelAnimationPose,
        _ targetPose: SkelAnimationPose,
        weight: Float
    ) -> SkelAnimationPose {
        let clampedWeight = min(max(weight, 0), 1)
        let baseRotations = basePose.limbRotations
        let targetRotations = targetPose.limbRotations
        let limbCount = max(baseRotations.count, targetRotations.count)
        var blendedRotations = Array(repeating: SIMD3<Float>.zero, count: limbCount)

        for limbIndex in 0..<limbCount {
            let baseRotation = limbIndex < baseRotations.count ? baseRotations[limbIndex] : .zero
            let targetRotation = limbIndex < targetRotations.count ? targetRotations[limbIndex] : .zero
            blendedRotations[limbIndex] = simd_mix(baseRotation, targetRotation, SIMD3<Float>(repeating: clampedWeight))
        }

        return SkelAnimationPose(
            rootTranslation: simd_mix(
                basePose.rootTranslation,
                targetPose.rootTranslation,
                SIMD3<Float>(repeating: clampedWeight)
            ),
            limbRotations: blendedRotations
        )
    }

    func clampedFrame(
        _ frame: Float,
        frameCount: Int,
        playbackMode: SkelAnimationPlaybackMode
    ) -> Float {
        guard frameCount > 0 else {
            return 0
        }

        switch playbackMode {
        case .hold:
            return min(max(frame, 0), Float(max(frameCount - 1, 0)))
        case .loop:
            let wrappedFrame = frame.truncatingRemainder(dividingBy: Float(frameCount))
            return wrappedFrame >= 0 ? wrappedFrame : wrappedFrame + Float(frameCount)
        }
    }

    func framePair(
        frame: Float,
        frameCount: Int,
        playbackMode: SkelAnimationPlaybackMode
    ) -> FrameSample {
        guard frameCount > 0 else {
            return FrameSample(lowerFrame: 0, upperFrame: 0, fraction: 0)
        }

        let resolvedFrame = clampedFrame(frame, frameCount: frameCount, playbackMode: playbackMode)
        let lowerFrame = Int(floor(resolvedFrame))
        let upperFrame: Int

        switch playbackMode {
        case .hold:
            upperFrame = min(lowerFrame + 1, max(frameCount - 1, 0))
        case .loop:
            upperFrame = (lowerFrame + 1) % frameCount
        }

        return FrameSample(
            lowerFrame: lowerFrame,
            upperFrame: upperFrame,
            fraction: resolvedFrame - floor(resolvedFrame)
        )
    }
}

private extension SkelAnimeRenderer {
    func appendDrawCommands(
        startingAt limbIndex: Int,
        parentMatrix: simd_float4x4,
        skeletonEntry: OOTRenderSkeleton,
        pose: SkelAnimationPose,
        overrideLimbDraw: OverrideLimbDraw?,
        drawCommands: inout [SkelLimbDrawCommand]
    ) throws {
        let limb = skeletonEntry.skeleton.limbs[limbIndex]
        var translation = SIMD3<Float>(
            Float(limb.translation.x),
            Float(limb.translation.y),
            Float(limb.translation.z)
        )
        if limbIndex == skeletonEntry.rootLimbIndex {
            translation += pose.rootTranslation
        }

        let rotation = limbIndex < pose.limbRotations.count
            ? pose.limbRotations[limbIndex]
            : .zero
        let displayListPath = resolveDisplayListPath(
            for: limb,
            useLowDetailDisplayLists: skeletonEntry.useLowDetailDisplayLists
        )
        var drawCommand = SkelLimbDrawCommand(
            limbIndex: limbIndex,
            translation: translation,
            rotation: rotation,
            modelMatrix: parentMatrix * limbTransformMatrix(
                translation: translation,
                rotation: rotation
            ),
            displayListPath: displayListPath,
            useLowDetailDisplayList: skeletonEntry.useLowDetailDisplayLists && limb.lowDetailDisplayListPath != nil
        )

        if let overrideLimbDraw {
            let overriddenCommand = overrideLimbDraw(drawCommand)
            drawCommand = SkelLimbDrawCommand(
                limbIndex: overriddenCommand.limbIndex,
                translation: overriddenCommand.translation,
                rotation: overriddenCommand.rotation,
                modelMatrix: parentMatrix * limbTransformMatrix(
                    translation: overriddenCommand.translation,
                    rotation: overriddenCommand.rotation
                ),
                displayListPath: overriddenCommand.displayListPath,
                useLowDetailDisplayList: overriddenCommand.useLowDetailDisplayList,
                skipDraw: overriddenCommand.skipDraw
            )
        }

        drawCommands.append(drawCommand)

        if let childIndex = limb.childIndex {
            try appendDrawCommands(
                startingAt: childIndex,
                parentMatrix: drawCommand.modelMatrix,
                skeletonEntry: skeletonEntry,
                pose: pose,
                overrideLimbDraw: overrideLimbDraw,
                drawCommands: &drawCommands
            )
        }

        if let siblingIndex = limb.siblingIndex {
            try appendDrawCommands(
                startingAt: siblingIndex,
                parentMatrix: parentMatrix,
                skeletonEntry: skeletonEntry,
                pose: pose,
                overrideLimbDraw: overrideLimbDraw,
                drawCommands: &drawCommands
            )
        }
    }

    func resolveDisplayListPath(
        for limb: LimbData,
        useLowDetailDisplayLists: Bool
    ) -> String? {
        if useLowDetailDisplayLists, let lowDetailDisplayListPath = limb.lowDetailDisplayListPath {
            return lowDetailDisplayListPath
        }

        return limb.displayListPath
    }

    func makeSegmentTable(
        for skeletonEntry: OOTRenderSkeleton,
        drawCommands: [SkelLimbDrawCommand]
    ) throws -> SegmentTable {
        var segmentTable = SegmentTable()
        for (segmentID, data) in skeletonEntry.asset.segmentData {
            try segmentTable.setSegment(segmentID, data: data)
        }

        let paletteData = encodeMatrixPalette(
            limbCount: skeletonEntry.skeleton.limbs.count,
            drawCommands: drawCommands
        )
        try segmentTable.setSegment(0x0D, data: paletteData)
        return segmentTable
    }

    func encodeMatrixPalette(
        limbCount: Int,
        drawCommands: [SkelLimbDrawCommand]
    ) -> Data {
        var matrices = Array(
            repeating: matrix_identity_float4x4,
            count: limbCount
        )
        for command in drawCommands where matrices.indices.contains(command.limbIndex) {
            matrices[command.limbIndex] = command.modelMatrix
        }

        return encodeMatrices(matrices)
    }

    func matrixSegmentAddress(for limbIndex: Int) -> UInt32 {
        0x0D00_0000 + UInt32(limbIndex * 64)
    }
}

private func limbTransformMatrix(
    translation: SIMD3<Float>,
    rotation: SIMD3<Float>
) -> simd_float4x4 {
    makeTranslationMatrix(translation)
        * makeRotationMatrixZ(rawAngle: rotation.z)
        * makeRotationMatrixY(rawAngle: rotation.y)
        * makeRotationMatrixX(rawAngle: rotation.x)
}

private func makeTranslationMatrix(_ translation: SIMD3<Float>) -> simd_float4x4 {
    simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    )
}

private func makeRotationMatrixX(rawAngle: Float) -> simd_float4x4 {
    let radians = rawAngleToRadians(rawAngle)
    let cosine = cos(radians)
    let sine = sin(radians)
    return simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, cosine, sine, 0),
        SIMD4<Float>(0, -sine, cosine, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

private func makeRotationMatrixY(rawAngle: Float) -> simd_float4x4 {
    let radians = rawAngleToRadians(rawAngle)
    let cosine = cos(radians)
    let sine = sin(radians)
    return simd_float4x4(
        SIMD4<Float>(cosine, 0, -sine, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(sine, 0, cosine, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

private func makeRotationMatrixZ(rawAngle: Float) -> simd_float4x4 {
    let radians = rawAngleToRadians(rawAngle)
    let cosine = cos(radians)
    let sine = sin(radians)
    return simd_float4x4(
        SIMD4<Float>(cosine, sine, 0, 0),
        SIMD4<Float>(-sine, cosine, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
}

private func rawAngleToRadians(_ rawAngle: Float) -> Float {
    rawAngle * (.pi / 32_768.0)
}

private func interpolate(
    _ lowerValue: Float,
    _ upperValue: Float,
    fraction: Float
) -> Float {
    lowerValue + ((upperValue - lowerValue) * fraction)
}

private func encodeMatrices(_ matrices: [simd_float4x4]) -> Data {
    var bytes = Data(count: matrices.count * 64)

    for (matrixIndex, matrix) in matrices.enumerated() {
        for elementIndex in 0..<16 {
            let column = elementIndex / 4
            let row = elementIndex % 4
            let fixedPoint = Int32((matrix[column][row] * 65_536.0).rounded())
            let upper = UInt16(truncatingIfNeeded: UInt32(bitPattern: fixedPoint) >> 16)
            let lower = UInt16(truncatingIfNeeded: UInt32(bitPattern: fixedPoint))
            let upperOffset = (matrixIndex * 64) + (elementIndex * 2)
            let lowerOffset = (matrixIndex * 64) + 32 + (elementIndex * 2)
            write(bigEndian: upper, to: &bytes, offset: upperOffset)
            write(bigEndian: lower, to: &bytes, offset: lowerOffset)
        }
    }

    return bytes
}

private func write<T: FixedWidthInteger>(
    bigEndian value: T,
    to data: inout Data,
    offset: Int
) {
    var bigEndianValue = value.bigEndian
    withUnsafeBytes(of: &bigEndianValue) { rawBuffer in
        data.replaceSubrange(offset..<(offset + rawBuffer.count), with: rawBuffer)
    }
}

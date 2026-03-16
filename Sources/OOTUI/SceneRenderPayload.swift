import Foundation
import Metal
import OOTContent
import OOTCore
import OOTDataModel
import OOTRender
import simd

struct SceneRenderPayload {
    let sceneID: Int
    let baseScene: OOTRenderScene
    let textureBindings: [UInt32: MTLTexture]
    let gameplayCameraConfiguration: GameplayCameraConfiguration?
    let roomCount: Int
    let vertexCount: Int
    let playerRenderAssets: PlayerRenderAssets?
    let chestRenderAssets: ChestRenderAssets?
}

struct PlayerRenderAssets {
    struct AnimationLibrary {
        let idle: ObjectAnimationData
        let walk: ObjectAnimationData
        let run: ObjectAnimationData
        let itemGetA: ObjectAnimationData
        let itemGetB: ObjectAnimationData
    }

    let skeleton: SkeletonData
    let skeletonAsset: OOTRenderSkeletonAsset
    let animationLibrary: AnimationLibrary

    func makeSkeleton(for playerState: PlayerState) -> OOTRenderSkeleton {
        OOTRenderSkeleton(
            name: "Link",
            skeleton: skeleton,
            asset: skeletonAsset,
            animationState: OOTSkeletonAnimationState(
                animation: animation(for: playerState.animationState.currentClip),
                currentFrame: playerState.animationState.currentFrame,
                playbackMode: .loop,
                morphAnimation: playerState.animationState.previousClip.map(animation(for:)),
                morphWeight: playerState.animationState.morphWeight
            ),
            modelMatrix: makeModelMatrix(for: playerState),
            rootLimbIndex: 0
        )
    }

    private func animation(for clip: PlayerAnimationClip) -> ObjectAnimationData {
        switch clip {
        case .idle:
            return animationLibrary.idle
        case .walk:
            return animationLibrary.walk
        case .run:
            return animationLibrary.run
        case .itemGetA:
            return animationLibrary.itemGetA
        case .itemGetB:
            return animationLibrary.itemGetB
        }
    }

    private func makeModelMatrix(for playerState: PlayerState) -> simd_float4x4 {
        let translation = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(playerState.position.x, playerState.position.y, playerState.position.z, 1)
        )
        let cosine = cos(playerState.facingRadians)
        let sine = sin(playerState.facingRadians)
        let rotation = simd_float4x4(
            SIMD4<Float>(cosine, 0, -sine, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(sine, 0, cosine, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        return translation * rotation
    }
}

struct ChestRenderAssets {
    let skeleton: SkeletonData
    let skeletonAsset: OOTRenderSkeletonAsset
    let openAnimation: ObjectAnimationData?

    @MainActor
    func makeSkeleton(for chest: TreasureChestActor) -> OOTRenderSkeleton {
        OOTRenderSkeleton(
            name: "Chest-\(chest.position.x)-\(chest.position.z)",
            skeleton: skeleton,
            asset: skeletonAsset,
            animationState: OOTSkeletonAnimationState(
                animation: openAnimation,
                currentFrame: Float(openAnimation?.frameCount ?? 1) * chest.lidOpenProgress,
                playbackMode: .hold
            ),
            modelMatrix: makeModelMatrix(for: chest),
            rootLimbIndex: 0
        )
    }

    @MainActor
    private func makeModelMatrix(for chest: TreasureChestActor) -> simd_float4x4 {
        let scale = chest.renderScale
        let translation = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(chest.position.x, chest.position.y, chest.position.z, 1)
        )
        let cosine = cos(chest.renderYawRadians)
        let sine = sin(chest.renderYawRadians)
        let rotation = simd_float4x4(
            SIMD4<Float>(cosine, 0, -sine, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(sine, 0, cosine, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        let scaling = simd_float4x4(
            SIMD4<Float>(scale, 0, 0, 0),
            SIMD4<Float>(0, scale, 0, 0),
            SIMD4<Float>(0, 0, scale, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        return translation * rotation * scaling
    }
}

enum SceneRenderPayloadBuilder {
    @MainActor
    static func makePayload(
        scene: LoadedScene,
        textureAssetURLs: [UInt32: URL],
        contentLoader: any ContentLoading
    ) throws -> SceneRenderPayload {
        let baseScene = OOTRenderScene(
            rooms: scene.rooms.map { room in
                OOTRenderRoom(
                    name: room.manifest.name,
                    displayList: room.displayList,
                    vertexData: room.vertexData
                )
            },
            environment: scene.environment,
            skyColor: EnvironmentRenderer(environment: scene.environment).currentState(timeOfDay: 6.0).skyColor
        )

        var mergedTextureAssetURLs = textureAssetURLs
        let playerRenderAssets = try makePlayerRenderAssets(contentLoader: contentLoader)
        let chestRenderAssets = try makeChestRenderAssets(contentLoader: contentLoader)
        if let playerRenderAssets {
            for (assetID, url) in playerRenderAssets.textureAssetURLs {
                mergedTextureAssetURLs[assetID] = url
            }
        }
        if let chestRenderAssets {
            for (assetID, url) in chestRenderAssets.textureAssetURLs {
                mergedTextureAssetURLs[assetID] = url
            }
        }

        let textureBindings = try makeTextureBindings(textureAssetURLs: mergedTextureAssetURLs)
        let gameplayCameraConfiguration = makeGameplayCameraConfiguration(scene: scene, playerState: nil)
        let vertexCount = scene.rooms.reduce(0) { partialResult, room in
            partialResult + (room.vertexData.count / MemoryLayout<N64Vertex>.stride)
        }

        return SceneRenderPayload(
            sceneID: scene.manifest.id,
            baseScene: baseScene,
            textureBindings: textureBindings,
            gameplayCameraConfiguration: gameplayCameraConfiguration,
            roomCount: scene.rooms.count,
            vertexCount: vertexCount,
            playerRenderAssets: playerRenderAssets?.assets,
            chestRenderAssets: chestRenderAssets?.assets
        )
    }

    @MainActor
    static func renderScene(
        from payload: SceneRenderPayload,
        playerState: PlayerState?,
        actors: [any Actor] = []
    ) -> OOTRenderScene {
        var scene = payload.baseScene
        var skeletons: [OOTRenderSkeleton] = []

        if let playerState, let playerRenderAssets = payload.playerRenderAssets {
            skeletons.append(playerRenderAssets.makeSkeleton(for: playerState))
        }
        if let chestRenderAssets = payload.chestRenderAssets {
            skeletons.append(
                contentsOf: actors.compactMap { actor in
                    guard let chest = actor as? TreasureChestActor else {
                        return nil
                    }

                    return chestRenderAssets.makeSkeleton(for: chest)
                }
            )
        }
        scene.skeletons = skeletons
        return scene
    }

    static func makeGameplayCameraConfiguration(
        scene: LoadedScene,
        playerState: PlayerState?,
        itemGetSequence: ItemGetSequenceState? = nil
    ) -> GameplayCameraConfiguration? {
        if let playerState {
            return GameplayCameraConfiguration(
                playerPosition: SIMD3<Float>(
                    playerState.position.x,
                    playerState.position.y,
                    playerState.position.z
                ),
                playerYaw: playerState.facingRadians,
                presentationOverride: itemGetSequence.map {
                    GameplayCameraPresentationOverride.itemGet(
                        itemPosition: $0.itemWorldPosition.simd,
                        playerYaw: playerState.facingRadians
                    )
                },
                collision: scene.collision
            )
        }

        guard let spawn = scene.spawns?.spawns.first else {
            return nil
        }

        return GameplayCameraConfiguration(
            playerPosition: SIMD3<Float>(
                Float(spawn.position.x),
                Float(spawn.position.y),
                Float(spawn.position.z)
            ),
            playerYaw: Float(spawn.rotation.y) * (.pi / 32_768.0),
            collision: scene.collision
        )
    }
    @MainActor
    private static func makeTextureBindings(
        textureAssetURLs: [UInt32: URL]
    ) throws -> [UInt32: MTLTexture] {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SceneRenderPayloadError.metalUnavailable
        }

        let loader = MetalTextureLoader(device: device)
        var textureBindings: [UInt32: MTLTexture] = [:]

        for (assetID, url) in textureAssetURLs.sorted(by: { $0.key < $1.key }) {
            textureBindings[assetID] = try loader.loadTexture(at: url)
        }

        return textureBindings
    }

    private static func makePlayerRenderAssets(
        contentLoader: any ContentLoading
    ) throws -> (assets: PlayerRenderAssets, textureAssetURLs: [UInt32: URL])? {
        guard let loadedObject = try? contentLoader.loadObject(named: "object_link_boy") else {
            return nil
        }

        guard
            let skeleton = loadedObject.skeletonsByName["gLinkAdultSkel"] ??
                loadedObject.skeletonsByName.sorted(by: { $0.key < $1.key }).first?.value
        else {
            return nil
        }

        let displayListsByAddress: [UInt32: [F3DEX2Command]] = Dictionary(
            uniqueKeysWithValues: loadedObject.manifest.meshes.compactMap { mesh in
                guard let displayList = loadedObject.displayListsByPath[mesh.displayListPath] else {
                    return nil
                }

                return (OOTAssetID.stableID(for: mesh.name), displayList)
            }
        )

        let animationLibrary = makeAnimationLibrary(from: loadedObject.animationsByName)
        let assets = PlayerRenderAssets(
            skeleton: skeleton,
            skeletonAsset: OOTRenderSkeletonAsset(
                displayListsByPath: loadedObject.displayListsByPath,
                displayListsByAddress: displayListsByAddress,
                segmentData: makeSegmentData(vertexDataByPath: loadedObject.vertexDataByPath)
            ),
            animationLibrary: animationLibrary
        )

        return (assets, loadedObject.textureAssetURLs)
    }

    private static func makeChestRenderAssets(
        contentLoader: any ContentLoading
    ) throws -> (assets: ChestRenderAssets, textureAssetURLs: [UInt32: URL])? {
        guard let loadedObject = try? contentLoader.loadObject(named: "object_box") else {
            return nil
        }

        guard
            let skeleton = loadedObject.skeletonsByName.sorted(by: { $0.key < $1.key }).first?.value
        else {
            return nil
        }

        let displayListsByAddress: [UInt32: [F3DEX2Command]] = Dictionary(
            uniqueKeysWithValues: loadedObject.manifest.meshes.compactMap { mesh in
                guard let displayList = loadedObject.displayListsByPath[mesh.displayListPath] else {
                    return nil
                }

                return (OOTAssetID.stableID(for: mesh.name), displayList)
            }
        )

        let animations = loadedObject.animationsByName.values.sorted { $0.name < $1.name }
        let assets = ChestRenderAssets(
            skeleton: skeleton,
            skeletonAsset: OOTRenderSkeletonAsset(
                displayListsByPath: loadedObject.displayListsByPath,
                displayListsByAddress: displayListsByAddress,
                segmentData: makeSegmentData(vertexDataByPath: loadedObject.vertexDataByPath)
            ),
            openAnimation: selectAnimation(
                matching: ["treasurechestanim", "open"],
                from: animations
            ) ?? animations.first
        )

        return (assets, loadedObject.textureAssetURLs)
    }

    private static func makeAnimationLibrary(
        from animationsByName: [String: ObjectAnimationData]
    ) -> PlayerRenderAssets.AnimationLibrary {
        let playerAnimations = animationsByName.values.filter { $0.kind == .player }
        let candidates = playerAnimations.isEmpty ? Array(animationsByName.values) : playerAnimations
        let sortedAnimations = candidates.sorted { $0.name < $1.name }
        let fallback = sortedAnimations.first ?? ObjectAnimationData(
            name: "LinkIdleFallback",
            kind: .player,
            frameCount: 1,
            values: [0]
        )

        return PlayerRenderAssets.AnimationLibrary(
            idle: selectAnimation(matching: ["idle", "wait"], from: sortedAnimations) ?? fallback,
            walk: selectAnimation(matching: ["walk"], from: sortedAnimations) ?? fallback,
            run: selectAnimation(matching: ["run"], from: sortedAnimations) ?? selectAnimation(matching: ["jog"], from: sortedAnimations) ?? fallback,
            itemGetA: selectAnimation(matching: ["get_itema", "getitema", "itema", "demo_get_itema"], from: sortedAnimations) ?? fallback,
            itemGetB: selectAnimation(matching: ["get_itemb", "getitemb", "itemb", "demo_get_itemb"], from: sortedAnimations) ?? fallback
        )
    }

    private static func selectAnimation(
        matching terms: [String],
        from animations: [ObjectAnimationData]
    ) -> ObjectAnimationData? {
        animations.first { animation in
            let lowercasedName = animation.name.lowercased()
            return terms.contains { lowercasedName.contains($0) }
        }
    }

    private static func makeSegmentData(vertexDataByPath: [String: Data]) -> [UInt8: Data] {
        var buffers: [UInt8: Data] = [:]

        for (path, data) in vertexDataByPath {
            let symbolName = URL(fileURLWithPath: path)
                .deletingPathExtension()
                .deletingPathExtension()
                .lastPathComponent
            let address = OOTAssetID.stableID(for: symbolName)
            let segmentID = UInt8((address >> 24) & 0xFF)
            let offset = Int(address & 0x00FF_FFFF)
            let requiredLength = offset + data.count

            var segmentBuffer = buffers[segmentID] ?? Data()
            if segmentBuffer.count < requiredLength {
                segmentBuffer.append(contentsOf: repeatElement(0, count: requiredLength - segmentBuffer.count))
            }
            segmentBuffer.replaceSubrange(offset..<(offset + data.count), with: data)
            buffers[segmentID] = segmentBuffer
        }

        return buffers
    }
}

enum SceneRenderPayloadError: LocalizedError {
    case metalUnavailable

    var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Metal is unavailable on this host."
        }
    }
}

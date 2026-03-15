import Foundation
import Metal
import OOTContent
import OOTDataModel
import OOTRender

struct SceneRenderPayload {
    let sceneID: Int
    let renderScene: OOTRenderScene
    let textureBindings: [UInt32: MTLTexture]
    let roomCount: Int
    let vertexCount: Int
}

enum SceneRenderPayloadBuilder {
    @MainActor
    static func makePayload(
        scene: LoadedScene,
        textureAssetURLs: [UInt32: URL]
    ) throws -> SceneRenderPayload {
        let renderScene = OOTRenderScene(
            rooms: scene.rooms.map { room in
                OOTRenderRoom(
                    name: room.manifest.name,
                    displayList: room.displayList,
                    vertexData: room.vertexData
                )
            }
        )

        let textureBindings = try makeTextureBindings(textureAssetURLs: textureAssetURLs)
        let vertexCount = scene.rooms.reduce(0) { partialResult, room in
            partialResult + (room.vertexData.count / MemoryLayout<N64Vertex>.stride)
        }

        return SceneRenderPayload(
            sceneID: scene.manifest.id,
            renderScene: renderScene,
            textureBindings: textureBindings,
            roomCount: scene.rooms.count,
            vertexCount: vertexCount
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

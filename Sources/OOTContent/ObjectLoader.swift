import Foundation
import OOTDataModel

public struct LoadedObject: Sendable, Equatable {
    public var manifest: ObjectManifest
    public var skeletonsByName: [String: SkeletonData]
    public var animationsByName: [String: ObjectAnimationData]
    public var displayListsByPath: [String: [F3DEX2Command]]
    public var vertexDataByPath: [String: Data]
    public var textureAssetURLs: [UInt32: URL]

    public init(
        manifest: ObjectManifest,
        skeletonsByName: [String: SkeletonData] = [:],
        animationsByName: [String: ObjectAnimationData] = [:],
        displayListsByPath: [String: [F3DEX2Command]] = [:],
        vertexDataByPath: [String: Data] = [:],
        textureAssetURLs: [UInt32: URL] = [:]
    ) {
        self.manifest = manifest
        self.skeletonsByName = skeletonsByName
        self.animationsByName = animationsByName
        self.displayListsByPath = displayListsByPath
        self.vertexDataByPath = vertexDataByPath
        self.textureAssetURLs = textureAssetURLs
    }
}

public extension SceneLoader {
    func loadObjectTable() throws -> [ObjectTableEntry] {
        try decodeJSON(
            [ObjectTableEntry].self,
            from: contentRoot
                .appendingPathComponent("Manifests", isDirectory: true)
                .appendingPathComponent("tables", isDirectory: true)
                .appendingPathComponent("object-table.json")
        )
    }

    func loadObject(named name: String) throws -> LoadedObject {
        let directory = contentRoot
            .appendingPathComponent("Objects", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        let manifest = try decodeJSON(
            ObjectManifest.self,
            from: directory.appendingPathComponent("object_manifest.json")
        )

        let skeletonsByName: [String: SkeletonData]
        if let skeletonPath = manifest.skeletonPath, skeletonPath.isEmpty == false {
            let file = try decodeJSON(
                ObjectSkeletonFile.self,
                from: directory.appendingPathComponent(skeletonPath)
            )
            skeletonsByName = Dictionary(uniqueKeysWithValues: file.skeletons.map { ($0.name, $0.skeleton) })
        } else {
            skeletonsByName = [:]
        }

        let animationsByName = try Dictionary(
            uniqueKeysWithValues: manifest.animations.map { reference in
                (
                    reference.name,
                    try decodeJSON(
                        ObjectAnimationData.self,
                        from: directory.appendingPathComponent(reference.path)
                    )
                )
            }
        )

        let displayListsByPath = try Dictionary(
            uniqueKeysWithValues: manifest.meshes.map { mesh in
                (
                    mesh.displayListPath,
                    try decodeJSON(
                        [F3DEX2Command].self,
                        from: directory.appendingPathComponent(mesh.displayListPath)
                    )
                )
            }
        )

        var vertexDataByPath: [String: Data] = [:]
        for mesh in manifest.meshes {
            for vertexPath in mesh.vertexPaths where vertexDataByPath[vertexPath] == nil {
                vertexDataByPath[vertexPath] = try Data(
                    contentsOf: directory.appendingPathComponent(vertexPath)
                )
            }
        }

        let textureAssetURLs = Dictionary(
            uniqueKeysWithValues: manifest.textures.map { descriptor in
                let textureURL = directory.appendingPathComponent(descriptor.path)
                let assetName = textureURL.deletingPathExtension().deletingPathExtension().lastPathComponent
                return (OOTAssetID.stableID(for: assetName), textureURL)
            }
        )

        return LoadedObject(
            manifest: manifest,
            skeletonsByName: skeletonsByName,
            animationsByName: animationsByName,
            displayListsByPath: displayListsByPath,
            vertexDataByPath: vertexDataByPath,
            textureAssetURLs: textureAssetURLs
        )
    }
}

private func decodeJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(T.self, from: data)
}

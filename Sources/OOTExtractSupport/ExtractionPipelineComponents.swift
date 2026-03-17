import Foundation

public struct OOTExtractionContext: Sendable {
    public let source: URL
    public let output: URL
    public let sceneNames: Set<String>?

    public init(source: URL, output: URL, sceneName: String? = nil) {
        self.init(
            source: source,
            output: output,
            sceneNames: sceneName.map { [$0] }
        )
    }

    public init(source: URL, output: URL, sceneNames: [String]?) {
        self.source = source.resolvingSymlinksInPath().standardizedFileURL
        self.output = output
        self.sceneNames = SceneSelection.normalizedSceneNames(sceneNames)
    }

    public var sceneName: String? {
        guard let sceneNames, sceneNames.count == 1 else {
            return nil
        }
        return sceneNames.first
    }

    public var isSceneScoped: Bool {
        sceneNames != nil
    }
}

public struct OOTVerificationContext: Sendable {
    public let content: URL

    public init(content: URL) {
        self.content = content
    }
}

public protocol OOTExtractionPipelineComponent: Sendable {
    var name: String { get }

    func extract(using context: OOTExtractionContext) throws
    func verify(using context: OOTVerificationContext) throws
}

public extension OOTExtractionPipelineComponent {
    func extract(using context: OOTExtractionContext) throws {
        print("[\(name)] extract \(context.source.path) -> \(context.output.path)")
    }

    func verify(using context: OOTVerificationContext) throws {
        print("[\(name)] verify \(context.content.path)")
    }
}

public struct SceneExtractor: OOTExtractionPipelineComponent {
    public let name = "SceneExtractor"

    public init() {}
}

public struct ObjectExtractor: OOTExtractionPipelineComponent {
    public let name = "ObjectExtractor"

    public init() {}
}

public struct TextureExtractor: OOTExtractionPipelineComponent {
    public let name = "TextureExtractor"

    public init() {}
}

public struct ActorExtractor: OOTExtractionPipelineComponent {
    public let name = "ActorExtractor"

    public init() {}
}

public struct AudioExtractor: OOTExtractionPipelineComponent {
    public let name = "AudioExtractor"

    public init() {}
}

public struct TextExtractor: OOTExtractionPipelineComponent {
    public let name = "TextExtractor"

    public init() {}
}

public struct CollisionExtractor: OOTExtractionPipelineComponent {
    public let name = "CollisionExtractor"

    public init() {}
}

public struct SceneManifestExtractor: OOTExtractionPipelineComponent {
    public let name = "SceneManifestExtractor"

    public init() {}
}

public struct VertexParser: OOTExtractionPipelineComponent {
    public let name = "VertexParser"

    public init() {}
}

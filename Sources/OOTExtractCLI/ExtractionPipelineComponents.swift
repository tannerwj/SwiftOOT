import Foundation

struct OOTExtractionContext: Sendable {
    let source: URL
    let output: URL
}

struct OOTVerificationContext: Sendable {
    let content: URL
}

protocol OOTExtractionPipelineComponent: Sendable {
    var name: String { get }

    func extract(using context: OOTExtractionContext) throws
    func verify(using context: OOTVerificationContext) throws
}

extension OOTExtractionPipelineComponent {
    func extract(using context: OOTExtractionContext) throws {
        print("[\(name)] extract \(context.source.path) -> \(context.output.path)")
    }

    func verify(using context: OOTVerificationContext) throws {
        print("[\(name)] verify \(context.content.path)")
    }
}

struct SceneExtractor: OOTExtractionPipelineComponent {
    let name = "SceneExtractor"
}

struct ObjectExtractor: OOTExtractionPipelineComponent {
    let name = "ObjectExtractor"
}

struct TextureExtractor: OOTExtractionPipelineComponent {
    let name = "TextureExtractor"
}

struct ActorExtractor: OOTExtractionPipelineComponent {
    let name = "ActorExtractor"
}

struct AudioExtractor: OOTExtractionPipelineComponent {
    let name = "AudioExtractor"
}

struct TextExtractor: OOTExtractionPipelineComponent {
    let name = "TextExtractor"
}

struct CollisionExtractor: OOTExtractionPipelineComponent {
    let name = "CollisionExtractor"
}

struct DisplayListParser: OOTExtractionPipelineComponent {
    let name = "DisplayListParser"
}

struct VertexParser: OOTExtractionPipelineComponent {
    let name = "VertexParser"
}

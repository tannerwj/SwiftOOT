import Foundation

public final class OOTContentExtractor {
    private let pipeline: [any OOTExtractionPipelineComponent]
    private let fileManager: FileManager

    public init(
        pipeline: [any OOTExtractionPipelineComponent]? = nil,
        fileManager: FileManager = .default
    ) {
        self.pipeline = pipeline ?? Self.makeDefaultPipeline()
        self.fileManager = fileManager
    }

    public func extract(from source: URL, to output: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            throw OOTContentExtractorError.missingPath(source.path)
        }

        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

        let context = OOTExtractionContext(source: source, output: output)
        print("Starting extraction pipeline")

        for component in pipeline {
            try component.extract(using: context)
        }

        print("Extraction pipeline complete")
    }

    public func verify(contentAt content: URL) throws {
        guard fileManager.fileExists(atPath: content.path) else {
            throw OOTContentExtractorError.missingPath(content.path)
        }

        let context = OOTVerificationContext(content: content)
        print("Starting content verification")

        for component in pipeline {
            try component.verify(using: context)
        }

        print("Content verification complete")
    }

    private static func makeDefaultPipeline() -> [any OOTExtractionPipelineComponent] {
        [
            TableExtractor(),
            SceneExtractor(),
            ObjectExtractor(),
            TextureExtractor(),
            ActorExtractor(),
            AudioExtractor(),
            TextExtractor(),
            CollisionExtractor(),
            DisplayListParser(),
            VertexParser(),
        ]
    }
}

private enum OOTContentExtractorError: LocalizedError {
    case missingPath(String)

    var errorDescription: String? {
        switch self {
        case .missingPath(let path):
            return "Path does not exist: \(path)"
        }
    }
}

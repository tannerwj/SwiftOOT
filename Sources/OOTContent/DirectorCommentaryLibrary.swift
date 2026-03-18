import Foundation
import OOTDataModel

public enum DirectorCommentaryLibrary {
    public static func bundledCatalog() -> DirectorCommentaryCatalog {
        do {
            return try loadBundledCatalog()
        } catch {
            return DirectorCommentaryCatalog(annotations: [])
        }
    }

    static func loadBundledCatalog(
        bundle: Bundle = .module
    ) throws -> DirectorCommentaryCatalog {
        let catalogURL = try resourceURL(
            named: "annotations",
            withExtension: "json",
            bundle: bundle
        )
        let data = try Data(contentsOf: catalogURL)
        let decoder = JSONDecoder()
        let catalogSeed = try decoder.decode(SeedCatalog.self, from: data)

        return DirectorCommentaryCatalog(
            annotations: try catalogSeed.annotations.map { seed in
                DirectorCommentaryAnnotation(
                    id: seed.id,
                    kind: seed.kind,
                    title: seed.title,
                    summary: seed.summary,
                    priority: seed.priority,
                    sceneIDs: seed.sceneIDs,
                    actorIDs: seed.actorIDs,
                    eventIDs: seed.eventIDs,
                    tags: seed.tags,
                    bodyMarkdown: try loadMarkdown(
                        at: seed.markdownPath,
                        bundle: bundle
                    ),
                    sourceLinks: seed.sourceLinks,
                    worldMarkers: seed.worldMarkers
                )
            }
        )
    }
}

private extension DirectorCommentaryLibrary {
    struct SeedCatalog: Codable {
        var annotations: [SeedAnnotation]
    }

    struct SeedAnnotation: Codable {
        var id: String
        var kind: DirectorCommentaryAnnotation.Kind
        var title: String
        var summary: String
        var priority: Int
        var sceneIDs: [Int]
        var actorIDs: [Int]
        var eventIDs: [String]
        var tags: [String]
        var markdownPath: String
        var sourceLinks: [DirectorCommentarySourceLink]
        var worldMarkers: [DirectorCommentaryWorldMarker]
    }

    static func loadMarkdown(
        at relativePath: String,
        bundle: Bundle
    ) throws -> String {
        let resourceURL = try resourceURL(for: relativePath, bundle: bundle)
        return try String(contentsOf: resourceURL, encoding: .utf8)
    }

    static func resourceURL(
        named name: String,
        withExtension fileExtension: String,
        bundle: Bundle
    ) throws -> URL {
        guard let url = bundle.url(
            forResource: name,
            withExtension: fileExtension
        ) ?? bundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Resources/DirectorCommentary"
        ) ?? bundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "DirectorCommentary"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return url
    }

    static func resourceURL(
        for relativePath: String,
        bundle: Bundle
    ) throws -> URL {
        let normalized = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileExtension = URL(fileURLWithPath: normalized).pathExtension
        let name = URL(fileURLWithPath: normalized).deletingPathExtension().lastPathComponent
        let subdirectory = URL(fileURLWithPath: normalized).deletingLastPathComponent().path
        let combinedSubdirectory = ["Resources/DirectorCommentary", subdirectory]
            .filter { !$0.isEmpty && $0 != "." }
            .joined(separator: "/")
        let fallbackSubdirectory = ["DirectorCommentary", subdirectory]
            .filter { !$0.isEmpty && $0 != "." }
            .joined(separator: "/")

        guard let url = bundle.url(
            forResource: name,
            withExtension: fileExtension.isEmpty ? nil : fileExtension
        ) ?? bundle.url(
            forResource: name,
            withExtension: fileExtension.isEmpty ? nil : fileExtension,
            subdirectory: combinedSubdirectory
        ) ?? bundle.url(
            forResource: name,
            withExtension: fileExtension.isEmpty ? nil : fileExtension,
            subdirectory: fallbackSubdirectory
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        return url
    }
}

import Foundation

public enum ContentRootConfiguration: Sendable {
    public static let contentRootEnvironmentVariable = "SWIFTOOT_CONTENT_ROOT"

    public static func resolveConfiguredContentRoot(
        from selectedURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let normalizedURL = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        let candidates = [
            normalizedURL,
            normalizedURL
                .appendingPathComponent("Content", isDirectory: true)
                .appendingPathComponent("OOT", isDirectory: true),
        ]

        return candidates.first { isContentRoot($0, fileManager: fileManager) }
    }

    public static func sceneTableURL(for contentRoot: URL) -> URL {
        contentRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("tables", isDirectory: true)
            .appendingPathComponent("scene-table.json")
    }

    public static func isContentRoot(
        _ contentRoot: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: sceneTableURL(for: contentRoot).path)
    }
}

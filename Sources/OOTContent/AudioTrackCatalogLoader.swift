import Foundation
import OOTDataModel

public protocol AudioTrackCatalogLoading: Sendable {
    func loadAudioTrackCatalog() throws -> AudioTrackCatalog
}

public enum AudioTrackCatalogLoaderError: Error, LocalizedError, Equatable, Sendable {
    case missingFile([String])
    case unreadableFile(String, String)
    case invalidJSON(String, String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let candidates):
            "Unable to locate bgm-tracks.json under any supported content path: \(candidates.joined(separator: ", "))."
        case .unreadableFile(let path, let message):
            "Unable to read audio catalog at \(path): \(message)"
        case .invalidJSON(let path, let message):
            "Invalid audio catalog at \(path): \(message)"
        }
    }
}

public struct AudioTrackCatalogLoader: AudioTrackCatalogLoading {
    public let contentRoot: URL

    public init(contentRoot: URL? = nil) {
        self.contentRoot = SceneLoader(contentRoot: contentRoot).contentRoot
    }

    public func loadAudioTrackCatalog() throws -> AudioTrackCatalog {
        let fileURL = try resolveCatalogURL()

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AudioTrackCatalogLoaderError.unreadableFile(
                fileURL.path,
                error.localizedDescription
            )
        }

        do {
            return try JSONDecoder().decode(AudioTrackCatalog.self, from: data)
        } catch {
            throw AudioTrackCatalogLoaderError.invalidJSON(
                fileURL.path,
                error.localizedDescription
            )
        }
    }
}

private extension AudioTrackCatalogLoader {
    func resolveCatalogURL() throws -> URL {
        let candidates = Self.catalogCandidates.map {
            contentRoot.appendingPathComponent($0)
        }

        if let existingURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existingURL
        }

        throw AudioTrackCatalogLoaderError.missingFile(candidates.map(\.path))
    }

    static let catalogCandidates = [
        "Manifests/audio/bgm-tracks.json",
    ]
}

import Foundation
import OOTDataModel

public protocol SoundEffectLoading: Sendable {
    func loadSoundEffectCatalog() throws -> SoundEffectCatalog
}

public enum SoundEffectLoaderError: Error, LocalizedError, Equatable, Sendable {
    case missingFile([String])
    case unreadableFile(String, String)
    case invalidJSON(String, String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let candidates):
            "Unable to locate sfx.json under any supported content path: \(candidates.joined(separator: ", "))."
        case .unreadableFile(let path, let message):
            "Unable to read sound effect catalog at \(path): \(message)"
        case .invalidJSON(let path, let message):
            "Invalid JSON at \(path): \(message)"
        }
    }
}

public struct SoundEffectLoader: SoundEffectLoading {
    public let contentRoot: URL

    public init(contentRoot: URL? = nil) {
        self.contentRoot = SceneLoader(contentRoot: contentRoot).contentRoot
    }

    public func loadSoundEffectCatalog() throws -> SoundEffectCatalog {
        let fileURL = try resolveCatalogURL()

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SoundEffectLoaderError.unreadableFile(fileURL.path, error.localizedDescription)
        }

        do {
            return try JSONDecoder().decode(SoundEffectCatalog.self, from: data)
        } catch {
            throw SoundEffectLoaderError.invalidJSON(fileURL.path, error.localizedDescription)
        }
    }
}

private extension SoundEffectLoader {
    func resolveCatalogURL() throws -> URL {
        let candidates = Self.catalogCandidates.map {
            contentRoot.appendingPathComponent($0)
        }

        if let existingURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existingURL
        }

        throw SoundEffectLoaderError.missingFile(candidates.map(\.path))
    }

    static let catalogCandidates = [
        "Manifests/audio/sfx.json",
        "Audio/SFX/sfx.json",
    ]
}

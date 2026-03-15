import Foundation
import OOTDataModel

public protocol MessageLoading: Sendable {
    func loadMessageCatalog() throws -> MessageCatalog
}

public enum MessageLoaderError: Error, LocalizedError, Equatable, Sendable {
    case missingFile([String])
    case unreadableFile(String, String)
    case invalidJSON(String, String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let candidates):
            "Unable to locate messages.json under any supported content path: \(candidates.joined(separator: ", "))."
        case .unreadableFile(let path, let message):
            "Unable to read message content file at \(path): \(message)"
        case .invalidJSON(let path, let message):
            "Invalid JSON at \(path): \(message)"
        }
    }
}

public struct MessageLoader: MessageLoading {
    public let contentRoot: URL

    public init(contentRoot: URL? = nil) {
        self.contentRoot = SceneLoader(contentRoot: contentRoot).contentRoot
    }

    public func loadMessageCatalog() throws -> MessageCatalog {
        let fileURL = try resolveCatalogURL()

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw MessageLoaderError.unreadableFile(fileURL.path, error.localizedDescription)
        }

        do {
            return try JSONDecoder().decode(MessageCatalog.self, from: data)
        } catch {
            throw MessageLoaderError.invalidJSON(fileURL.path, error.localizedDescription)
        }
    }
}

private extension MessageLoader {
    func resolveCatalogURL() throws -> URL {
        let candidates = Self.catalogCandidates.map {
            contentRoot.appendingPathComponent($0)
        }

        if let existingURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existingURL
        }

        throw MessageLoaderError.missingFile(candidates.map(\.path))
    }

    static let catalogCandidates = [
        "messages.json",
        "Messages/messages.json",
        "Manifests/messages.json",
        "Manifests/messages/messages.json",
        "Manifests/text/messages.json",
    ]
}

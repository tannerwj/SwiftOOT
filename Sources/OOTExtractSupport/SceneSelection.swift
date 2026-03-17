import Foundation
import OOTDataModel

enum SceneSelection {
    private static let runtimeObjectNames: Set<String> = [
        "object_link_boy",
    ]

    static func normalizedSceneNames(_ sceneNames: [String]?) -> Set<String>? {
        guard let sceneNames else {
            return nil
        }

        let normalized = Set(
            sceneNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
        )
        return normalized.isEmpty ? nil : normalized
    }

    static func includes(_ candidate: String, in sceneNames: Set<String>?) -> Bool {
        guard let sceneNames else {
            return true
        }
        return sceneNames.contains(candidate)
    }

    static func requiredObjectNames(
        for sceneNames: Set<String>,
        outputRoot: URL,
        fileManager: FileManager
    ) throws -> Set<String> {
        var requiredNames = runtimeObjectNames

        let tablesRoot = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("tables", isDirectory: true)
        let objectTableURL = tablesRoot.appendingPathComponent("object-table.json")
        let actorTableURL = tablesRoot.appendingPathComponent("actor-table.json")
        guard
            fileManager.fileExists(atPath: objectTableURL.path),
            fileManager.fileExists(atPath: actorTableURL.path)
        else {
            return requiredNames
        }

        let objectTable: [ObjectTableEntry] = try readJSON(from: objectTableURL)
        let actorTable: [ActorTableEntry] = try readJSON(from: actorTableURL)
        let objectNameByID = Dictionary(
            uniqueKeysWithValues: objectTable.map { entry in
                (entry.id, URL(fileURLWithPath: entry.assetPath).lastPathComponent)
            }
        )
        let actorTableByID = Dictionary(uniqueKeysWithValues: actorTable.map { ($0.id, $0) })

        for sceneDirectory in try sceneMetadataDirectories(
            for: sceneNames,
            outputRoot: outputRoot,
            fileManager: fileManager
        ) {
            let sceneHeaderURL = sceneDirectory.appendingPathComponent("scene-header.json")
            let sceneHeader: SceneHeaderDefinition = try readJSON(from: sceneHeaderURL)

            for objectID in sceneHeader.sceneObjectIDs {
                appendObjectName(objectNameByID[objectID], into: &requiredNames)
            }
            for room in sceneHeader.rooms {
                for objectID in room.objectIDs {
                    appendObjectName(objectNameByID[objectID], into: &requiredNames)
                }
            }
            appendObjectName(sceneHeader.specialFiles?.keepObjectName, into: &requiredNames)

            let actorsURL = sceneDirectory.appendingPathComponent("actors.json")
            guard fileManager.fileExists(atPath: actorsURL.path) else {
                continue
            }

            let actorsFile: SceneActorsFile = try readJSON(from: actorsURL)
            for room in actorsFile.rooms {
                for actor in room.actors {
                    guard let objectID = actorTableByID[actor.actorID]?.profile.objectID else {
                        continue
                    }
                    appendObjectName(objectNameByID[objectID], into: &requiredNames)
                }
            }
        }

        return requiredNames
    }

    private static func sceneMetadataDirectories(
        for sceneNames: Set<String>,
        outputRoot: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        let scenesRoot = outputRoot
            .appendingPathComponent("Manifests", isDirectory: true)
            .appendingPathComponent("scenes", isDirectory: true)
        guard fileManager.fileExists(atPath: scenesRoot.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: scenesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var directories: [URL] = []
        for case let directory as URL in enumerator {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                continue
            }
            guard sceneNames.contains(directory.lastPathComponent) else {
                continue
            }
            let sceneHeaderURL = directory.appendingPathComponent("scene-header.json")
            guard fileManager.fileExists(atPath: sceneHeaderURL.path) else {
                continue
            }
            directories.append(directory)
        }

        return directories.sorted { $0.path < $1.path }
    }

    private static func appendObjectName(_ name: String?, into objectNames: inout Set<String>) {
        guard let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines), trimmedName.isEmpty == false else {
            return
        }
        objectNames.insert(URL(fileURLWithPath: trimmedName).lastPathComponent)
    }

    private static func readJSON<T: Decodable>(from url: URL) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

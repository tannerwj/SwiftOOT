public struct DirectorCommentaryCatalog: Codable, Sendable, Equatable {
    public var annotations: [DirectorCommentaryAnnotation]

    public init(annotations: [DirectorCommentaryAnnotation]) {
        self.annotations = annotations
    }
}

public struct DirectorCommentaryAnnotation: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case scene
        case actor
        case mechanic
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var summary: String
    public var priority: Int
    public var sceneIDs: [Int]
    public var actorIDs: [Int]
    public var eventIDs: [String]
    public var tags: [String]
    public var bodyMarkdown: String
    public var sourceLinks: [DirectorCommentarySourceLink]
    public var worldMarkers: [DirectorCommentaryWorldMarker]

    public init(
        id: String,
        kind: Kind,
        title: String,
        summary: String,
        priority: Int = 0,
        sceneIDs: [Int] = [],
        actorIDs: [Int] = [],
        eventIDs: [String] = [],
        tags: [String] = [],
        bodyMarkdown: String,
        sourceLinks: [DirectorCommentarySourceLink] = [],
        worldMarkers: [DirectorCommentaryWorldMarker] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.priority = priority
        self.sceneIDs = sceneIDs
        self.actorIDs = actorIDs
        self.eventIDs = eventIDs
        self.tags = tags
        self.bodyMarkdown = bodyMarkdown
        self.sourceLinks = sourceLinks
        self.worldMarkers = worldMarkers
    }
}

public struct DirectorCommentarySourceLink: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var url: String

    public init(
        id: String,
        title: String,
        url: String
    ) {
        self.id = id
        self.title = title
        self.url = url
    }
}

public struct DirectorCommentaryWorldMarker: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var sceneID: Int
    public var position: DirectorCommentaryPoint3D

    public init(
        id: String,
        title: String,
        sceneID: Int,
        position: DirectorCommentaryPoint3D
    ) {
        self.id = id
        self.title = title
        self.sceneID = sceneID
        self.position = position
    }
}

public struct DirectorCommentaryPoint3D: Codable, Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(
        x: Float,
        y: Float,
        z: Float
    ) {
        self.x = x
        self.y = y
        self.z = z
    }
}

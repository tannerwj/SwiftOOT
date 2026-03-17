import Foundation
import OOTDataModel

public struct DirectorCommentaryResolvedWorldMarker: Sendable, Equatable, Identifiable {
    public var id: String
    public var annotationID: String
    public var title: String
    public var position: Vec3f

    public init(
        id: String,
        annotationID: String,
        title: String,
        position: Vec3f
    ) {
        self.id = id
        self.annotationID = annotationID
        self.title = title
        self.position = position
    }
}

public extension GameRuntime {
    var directorCommentaryAnnotations: [DirectorCommentaryAnnotation] {
        directorCommentaryCatalog.annotations.sorted {
            if $0.priority != $1.priority {
                return $0.priority > $1.priority
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var activeDirectorCommentaryAnnotations: [DirectorCommentaryAnnotation] {
        directorCommentaryAnnotations.filter { activeDirectorCommentaryIDs().contains($0.id) }
    }

    var selectedDirectorCommentaryAnnotation: DirectorCommentaryAnnotation? {
        guard let selectedDirectorCommentaryAnnotationID else {
            return directorCommentaryAnnotations.first
        }

        return directorCommentaryCatalog.annotations.first(where: {
            $0.id == selectedDirectorCommentaryAnnotationID
        }) ?? directorCommentaryAnnotations.first
    }

    var activeDirectorCommentaryAnnotation: DirectorCommentaryAnnotation? {
        guard let activeDirectorCommentaryAnnotationID else {
            return nil
        }

        return directorCommentaryCatalog.annotations.first(where: {
            $0.id == activeDirectorCommentaryAnnotationID
        })
    }

    var directorCommentaryVisibleWorldMarkers: [DirectorCommentaryResolvedWorldMarker] {
        guard
            isDirectorCommentaryEnabled,
            directorCommentaryShowsWorldMarkers,
            let currentSceneID = currentDirectorCommentarySceneID
        else {
            return []
        }

        let relevantStaticAnnotations = directorCommentaryAnnotations.filter { annotation in
            annotation.sceneIDs.contains(currentSceneID) || activeDirectorCommentaryIDs().contains(annotation.id)
        }
        let staticMarkers: [DirectorCommentaryResolvedWorldMarker] = relevantStaticAnnotations.flatMap { annotation in
            annotation.worldMarkers.compactMap { marker -> DirectorCommentaryResolvedWorldMarker? in
                guard marker.sceneID == currentSceneID else {
                    return nil
                }

                return DirectorCommentaryResolvedWorldMarker(
                    id: "static:\(annotation.id):\(marker.id)",
                    annotationID: annotation.id,
                    title: marker.title,
                    position: Vec3f(
                        x: marker.position.x,
                        y: marker.position.y,
                        z: marker.position.z
                    )
                )
            }
        }

        let annotatedActorIDs = Set(
            directorCommentaryAnnotations.flatMap(\.actorIDs)
        )
        let dynamicMarkers = actors.enumerated().compactMap { index, actor -> DirectorCommentaryResolvedWorldMarker? in
            guard
                annotatedActorIDs.contains(actor.profile.id),
                let annotation = directorCommentaryAnnotations.first(where: { annotation in
                    annotation.actorIDs.contains(actor.profile.id)
                })
            else {
                return nil
            }

            return DirectorCommentaryResolvedWorldMarker(
                id: "actor:\(annotation.id):\(index)",
                annotationID: annotation.id,
                title: annotation.title,
                position: actor.position
            )
        }

        return staticMarkers + dynamicMarkers
    }

    var currentDirectorCommentarySceneID: Int? {
        playState?.currentSceneID ?? loadedScene?.manifest.id ?? selectedSceneID
    }

    func toggleDirectorCommentaryEnabled() {
        setDirectorCommentaryEnabled(!isDirectorCommentaryEnabled)
    }

    func setDirectorCommentaryEnabled(_ isEnabled: Bool) {
        isDirectorCommentaryEnabled = isEnabled
        if isEnabled {
            refreshDirectorCommentary(forcePresentation: true)
        } else {
            activeDirectorCommentaryAnnotationID = nil
            previousDirectorCommentaryAnnotationIDs = []
        }
    }

    func selectDirectorCommentaryAnnotation(id: String?) {
        selectedDirectorCommentaryAnnotationID = id
    }

    func refreshDirectorCommentary(forcePresentation: Bool = false) {
        guard isDirectorCommentaryEnabled else {
            activeDirectorCommentaryAnnotationID = nil
            if forcePresentation {
                previousDirectorCommentaryAnnotationIDs = []
            }
            return
        }

        let activeIDs = activeDirectorCommentaryIDs()
        let newlyActiveIDs = activeIDs.subtracting(previousDirectorCommentaryAnnotationIDs)

        guard activeIDs.isEmpty == false else {
            activeDirectorCommentaryAnnotationID = nil
            previousDirectorCommentaryAnnotationIDs = []
            return
        }

        let activeAnnotations = directorCommentaryAnnotations.filter { activeIDs.contains($0.id) }
        let newlyActiveAnnotations = activeAnnotations.filter { newlyActiveIDs.contains($0.id) }
        let currentIsStillActive = activeDirectorCommentaryAnnotationID.map(activeIDs.contains) == true

        if forcePresentation || currentIsStillActive == false {
            activeDirectorCommentaryAnnotationID = (newlyActiveAnnotations.first ?? activeAnnotations.first)?.id
        } else if let newest = newlyActiveAnnotations.first {
            activeDirectorCommentaryAnnotationID = newest.id
        }

        previousDirectorCommentaryAnnotationIDs = activeIDs
    }
}

private extension GameRuntime {
    enum DirectorCommentaryEventID {
        static let followCamera = "follow-camera"
        static let collisionFloorSnap = "collision-floor-snap"
        static let zTargeting = "z-targeting"
    }

    func activeDirectorCommentaryIDs() -> Set<String> {
        let sceneIDs = Set(currentDirectorCommentarySceneID.map { [$0] } ?? [])
        let actorIDs = Set(actors.map(\.profile.id))
        let eventIDs = activeDirectorCommentaryEventIDs()

        return Set(
            directorCommentaryCatalog.annotations.compactMap { annotation in
                let matchesScene = annotation.sceneIDs.isEmpty == false && !sceneIDs.isDisjoint(with: annotation.sceneIDs)
                let matchesActor = annotation.actorIDs.isEmpty == false && !actorIDs.isDisjoint(with: annotation.actorIDs)
                let matchesEvent = annotation.eventIDs.isEmpty == false && !eventIDs.isDisjoint(with: annotation.eventIDs)
                return (matchesScene || matchesActor || matchesEvent) ? annotation.id : nil
            }
        )
    }

    func activeDirectorCommentaryEventIDs() -> Set<String> {
        var eventIDs: Set<String> = []

        if loadedScene != nil, playerState != nil {
            eventIDs.insert(DirectorCommentaryEventID.followCamera)
        }

        if loadedScene?.collision != nil, playerState != nil {
            eventIDs.insert(DirectorCommentaryEventID.collisionFloorSnap)
        }

        if combatState.lockOnTarget != nil {
            eventIDs.insert(DirectorCommentaryEventID.zTargeting)
        }

        return eventIDs
    }
}

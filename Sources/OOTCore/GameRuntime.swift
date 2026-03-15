import Observation
import OOTContent
import OOTDataModel
import OOTTelemetry

@MainActor
@Observable
public final class GameRuntime {
    public enum State: Sendable, Equatable {
        case idle
        case loadingContent
        case running
    }

    public var state: State
    public private(set) var playState: PlayState?

    @ObservationIgnored
    public let contentLoader: any ContentLoading

    @ObservationIgnored
    public let telemetryPublisher: any TelemetryPublishing

    @ObservationIgnored
    private let actorRegistry: ActorRegistry?

    public init(
        state: State = .idle,
        contentLoader: any ContentLoading = ContentLoader(),
        telemetryPublisher: any TelemetryPublishing = TelemetryPublisher(),
        actorRegistry: ActorRegistry? = nil
    ) {
        self.state = state
        self.contentLoader = contentLoader
        self.telemetryPublisher = telemetryPublisher
        self.actorRegistry = actorRegistry
    }

    public var actors: [any Actor] {
        playState?.actorContext.allActors ?? []
    }

    public func loadScene(
        id sceneID: Int,
        activeRoomIDs: Set<Int>? = nil
    ) async throws {
        state = .loadingContent

        do {
            try await contentLoader.loadInitialContent()
            let loadedScene = try await contentLoader.loadScene(id: sceneID)
            let actorTableEntries = try await contentLoader.loadActorTable()
            let actorTable = Dictionary(uniqueKeysWithValues: actorTableEntries.map { ($0.id, $0) })
            let selectedRooms = activeRoomIDs ?? Set(loadedScene.manifest.rooms.prefix(1).map(\.id))
            let registry = actorRegistry ?? ActorRegistry.default(actorTable: actorTableEntries)
            let actorContext = ActorContext(
                registry: registry,
                telemetryPublisher: telemetryPublisher
            )
            let playState = PlayState(
                scene: loadedScene,
                actorTable: actorTable,
                activeRoomIDs: selectedRooms,
                actorContext: actorContext
            )

            actorContext.spawnActors(
                for: selectedRooms,
                in: loadedScene,
                actorTable: actorTable,
                playState: playState
            )

            self.playState = playState
            state = .running
        } catch {
            playState = nil
            state = .idle
            throw error
        }
    }

    public func setActiveRooms(_ roomIDs: Set<Int>) {
        guard let playState else {
            return
        }

        playState.setActiveRooms(roomIDs)
        playState.actorContext.syncActiveRooms(
            roomIDs,
            in: playState.scene,
            actorTable: playState.actorTable,
            playState: playState
        )
    }

    public func updateFrame() {
        guard let playState else {
            return
        }

        playState.actorContext.updateAll(playState: playState)
    }

    public func drawActors(in pass: ActorDrawPass) {
        guard let playState else {
            return
        }

        playState.actorContext.drawActors(in: pass, playState: playState)
    }
}

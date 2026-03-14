import Observation
import OOTContent
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

    @ObservationIgnored
    public let contentLoader: any ContentLoading

    @ObservationIgnored
    public let telemetryPublisher: any TelemetryPublishing

    public init(
        state: State = .idle,
        contentLoader: any ContentLoading = ContentLoader(),
        telemetryPublisher: any TelemetryPublishing = TelemetryPublisher()
    ) {
        self.state = state
        self.contentLoader = contentLoader
        self.telemetryPublisher = telemetryPublisher
    }
}

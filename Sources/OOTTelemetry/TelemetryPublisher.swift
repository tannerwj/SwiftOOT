public protocol TelemetryPublishing: Sendable {
    func publish(_ event: String)
}

public struct TelemetryPublisher: TelemetryPublishing {
    public init() {}

    public func publish(_ event: String) {}
}

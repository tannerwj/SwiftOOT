import Foundation

public protocol TelemetryPublishing: Sendable {
    func publish(_ event: String)
    func publish(xraySnapshot: XRayTelemetrySnapshot?)
}

public final class TelemetryPublisher: TelemetryPublishing, @unchecked Sendable {
    public private(set) var events: [String]
    public private(set) var xraySnapshot: XRayTelemetrySnapshot?

    public init(
        events: [String] = [],
        xraySnapshot: XRayTelemetrySnapshot? = nil
    ) {
        self.events = events
        self.xraySnapshot = xraySnapshot
    }

    public func publish(_ event: String) {
        events.append(event)
    }

    public func publish(xraySnapshot: XRayTelemetrySnapshot?) {
        self.xraySnapshot = xraySnapshot
    }
}

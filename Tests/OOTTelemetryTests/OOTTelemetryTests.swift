import XCTest
@testable import OOTTelemetry

final class OOTTelemetryTests: XCTestCase {
    func testTelemetryPublisherConformsToProtocol() {
        let publisher: any TelemetryPublishing = TelemetryPublisher()

        XCTAssertNotNil(publisher)
    }

    func testTelemetryPublisherRetainsLatestXRaySnapshotAndEvents() {
        let publisher = TelemetryPublisher()
        let snapshot = XRayTelemetrySnapshot(
            scene: XRaySceneSnapshot(
                collisionPolygons: [
                    XRayCollisionPolygon(
                        kind: .walkable,
                        surfaceTypeIndex: 0,
                        vertices: [
                            XRayVector3(x: -1, y: 0, z: -1),
                            XRayVector3(x: 1, y: 0, z: -1),
                            XRayVector3(x: 0, y: 0, z: 1),
                        ]
                    )
                ]
            ),
            activeActors: [
                XRayActorSnapshot(
                    profileID: 1,
                    actorType: "Player",
                    category: "player",
                    roomID: 0,
                    position: XRayVector3(x: 0, y: 0, z: 0),
                    rotation: XRayVector3(x: 0, y: 0, z: 0)
                )
            ]
        )

        publisher.publish("gameRuntime.start")
        publisher.publish(xraySnapshot: snapshot)

        XCTAssertEqual(publisher.events, ["gameRuntime.start"])
        XCTAssertEqual(publisher.xraySnapshot, snapshot)
    }
}

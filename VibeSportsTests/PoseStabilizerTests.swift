import XCTest
@testable import VibeSports

final class PoseStabilizerTests: XCTestCase {
    func test_hysteresisPreventsFlickerNearThreshold() {
        var stabilizer = PoseStabilizer()
        stabilizer.configuration.onConfidenceThreshold = 0.35
        stabilizer.configuration.offConfidenceThreshold = 0.20
        stabilizer.configuration.holdDuration = 1.0
        stabilizer.configuration.smoothingAlpha = 1.0

        let t0 = Date(timeIntervalSince1970: 0)
        let onPose = Pose(joints: [
            .leftWrist: PoseJoint(location: .init(x: 0.5, y: 0.5), confidence: 0.36),
        ])
        XCTAssertNotNil(stabilizer.ingest(pose: onPose, now: t0)?.joint(.leftWrist))

        // Confidence dips below on-threshold but remains above off-threshold: should stay visible.
        let t1 = t0.addingTimeInterval(0.05)
        let midPose = Pose(joints: [
            .leftWrist: PoseJoint(location: .init(x: 0.5, y: 0.5), confidence: 0.25),
        ])
        XCTAssertNotNil(stabilizer.ingest(pose: midPose, now: t1)?.joint(.leftWrist))
    }

    func test_holdKeepsJointVisibleForShortDropouts() {
        var stabilizer = PoseStabilizer()
        stabilizer.configuration.onConfidenceThreshold = 0.35
        stabilizer.configuration.offConfidenceThreshold = 0.20
        stabilizer.configuration.holdDuration = 0.20
        stabilizer.configuration.smoothingAlpha = 1.0

        let t0 = Date(timeIntervalSince1970: 0)
        let pose = Pose(joints: [
            .leftElbow: PoseJoint(location: .init(x: 0.4, y: 0.4), confidence: 0.9),
        ])
        XCTAssertNotNil(stabilizer.ingest(pose: pose, now: t0)?.joint(.leftElbow))

        // Short dropout: nil pose should still output last-known joint within holdDuration.
        let t1 = t0.addingTimeInterval(0.10)
        XCTAssertNotNil(stabilizer.ingest(pose: nil, now: t1)?.joint(.leftElbow))

        // Past hold window: joint should disappear.
        let t2 = t0.addingTimeInterval(0.25)
        XCTAssertNil(stabilizer.ingest(pose: nil, now: t2)?.joint(.leftElbow))
    }

    func test_smoothingMovesTowardMeasurement() {
        var stabilizer = PoseStabilizer()
        stabilizer.configuration.onConfidenceThreshold = 0.0
        stabilizer.configuration.offConfidenceThreshold = 0.0
        stabilizer.configuration.holdDuration = 1.0
        stabilizer.configuration.smoothingAlpha = 0.5

        let t0 = Date(timeIntervalSince1970: 0)
        let p0 = Pose(joints: [
            .rightWrist: PoseJoint(location: .init(x: 0.0, y: 0.0), confidence: 1.0),
        ])
        _ = stabilizer.ingest(pose: p0, now: t0)

        let t1 = t0.addingTimeInterval(0.05)
        let p1 = Pose(joints: [
            .rightWrist: PoseJoint(location: .init(x: 1.0, y: 1.0), confidence: 1.0),
        ])
        let out = stabilizer.ingest(pose: p1, now: t1)
        let loc = out?.joint(.rightWrist)?.location
        XCTAssertEqual(Double(loc?.x ?? 0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Double(loc?.y ?? 0), 0.5, accuracy: 0.0001)
    }
}

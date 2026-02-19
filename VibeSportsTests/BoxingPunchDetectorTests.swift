import XCTest
@testable import VibeSports

final class BoxingPunchDetectorTests: XCTestCase {
    func test_emitsLeftUppercutWhenWristMovesUpAndReturns() {
        var detector = BoxingPunchDetector()
        detector.configuration.minPunchInterval = 0.0
        detector.configuration.minNormalizedDistanceToArm = 0.18
        detector.configuration.returnNormalizedDistance = 0.10
        detector.configuration.uppercutNormalizedDyThreshold = 0.18
        detector.configuration.minJointConfidence = 0

        let baseline = BoxingCalibrationBaseline(
            leftNeutralWrist: .init(x: 0.45, y: 0.50),
            rightNeutralWrist: .init(x: 0.55, y: 0.50),
            shoulderDistance: 0.30
        )

        let t0 = Date(timeIntervalSince1970: 0)

        func pose(leftWrist: CGPoint) -> Pose {
            Pose(joints: [
                .leftWrist: PoseJoint(location: leftWrist, confidence: 1),
                .rightWrist: PoseJoint(location: .init(x: 0.55, y: 0.50), confidence: 1),
            ])
        }

        _ = detector.ingest(pose: pose(leftWrist: .init(x: 0.45, y: 0.50)), baseline: baseline, now: t0)
        _ = detector.ingest(pose: pose(leftWrist: .init(x: 0.45, y: 0.60)), baseline: baseline, now: t0.addingTimeInterval(0.05))
        _ = detector.ingest(pose: pose(leftWrist: .init(x: 0.45, y: 0.56)), baseline: baseline, now: t0.addingTimeInterval(0.10))

        let event = detector.ingest(pose: pose(leftWrist: .init(x: 0.45, y: 0.50)), baseline: baseline, now: t0.addingTimeInterval(0.15))
        XCTAssertEqual(event?.kind, .leftUppercut)
    }

    func test_debouncesPunchesByMinInterval() {
        var detector = BoxingPunchDetector()
        detector.configuration.minPunchInterval = 1.0
        detector.configuration.minNormalizedDistanceToArm = 0.18
        detector.configuration.returnNormalizedDistance = 0.10
        detector.configuration.uppercutNormalizedDyThreshold = 0.18
        detector.configuration.minJointConfidence = 0

        let baseline = BoxingCalibrationBaseline(
            leftNeutralWrist: .init(x: 0.45, y: 0.50),
            rightNeutralWrist: .init(x: 0.55, y: 0.50),
            shoulderDistance: 0.30
        )

        let t0 = Date(timeIntervalSince1970: 0)

        func pose(leftWrist: CGPoint) -> Pose {
            Pose(joints: [
                .leftWrist: PoseJoint(location: leftWrist, confidence: 1),
                .rightWrist: PoseJoint(location: .init(x: 0.55, y: 0.50), confidence: 1),
            ])
        }

        _ = detector.ingest(pose: pose(leftWrist: .init(x: 0.45, y: 0.50)), baseline: baseline, now: t0)
        _ = detector.ingest(pose: pose(leftWrist: .init(x: 0.45, y: 0.60)), baseline: baseline, now: t0.addingTimeInterval(0.05))
        let first = detector.ingest(pose: pose(leftWrist: .init(x: 0.45, y: 0.50)), baseline: baseline, now: t0.addingTimeInterval(0.10))
        XCTAssertEqual(first?.kind, .leftUppercut)

        _ = detector.ingest(pose: pose(leftWrist: .init(x: 0.45, y: 0.60)), baseline: baseline, now: t0.addingTimeInterval(0.20))
        let second = detector.ingest(pose: pose(leftWrist: .init(x: 0.45, y: 0.50)), baseline: baseline, now: t0.addingTimeInterval(0.25))
        XCTAssertNil(second)
    }
}


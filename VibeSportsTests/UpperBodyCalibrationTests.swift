import XCTest
@testable import VibeSports

final class UpperBodyCalibrationTests: XCTestCase {
    func test_calibratesAfterStableWindowInBoxingGuardMode() {
        var calibration = UpperBodyCalibration(
            configuration: .init(
                mode: .boxingGuard,
                minJointConfidence: 0,
                stableDuration: 0.2,
                stabilityToleranceNormalized: 0.0,
                smoothingAlpha: 1.0,
                minShoulderDistance: 0.0,
                maxShoulderDistance: 1.0,
                guardWristAboveShoulderMinOffset: 0.0
            )
        )

        let base = Date(timeIntervalSince1970: 0)
        let pose = Pose(joints: [
            .leftShoulder: PoseJoint(location: .init(x: 0.4, y: 0.5), confidence: 1),
            .rightShoulder: PoseJoint(location: .init(x: 0.6, y: 0.5), confidence: 1),
            .leftElbow: PoseJoint(location: .init(x: 0.42, y: 0.45), confidence: 1),
            .rightElbow: PoseJoint(location: .init(x: 0.58, y: 0.45), confidence: 1),
            .leftWrist: PoseJoint(location: .init(x: 0.45, y: 0.55), confidence: 1),
            .rightWrist: PoseJoint(location: .init(x: 0.55, y: 0.55), confidence: 1),
        ])

        var out = calibration.ingest(pose: pose, now: base)
        XCTAssertNil(out.baseline)

        out = calibration.ingest(pose: pose, now: base.addingTimeInterval(0.25))
        XCTAssertNotNil(out.baseline)
        XCTAssertEqual(out.progress, 1, accuracy: 0.0001)
    }

    func test_requiresJointsToBePresent() {
        var calibration = UpperBodyCalibration(
            configuration: .init(
                mode: .generic,
                minJointConfidence: 0,
                stableDuration: 0.1,
                stabilityToleranceNormalized: 1.0,
                smoothingAlpha: 1.0,
                minShoulderDistance: 0.0,
                maxShoulderDistance: 1.0,
                guardWristAboveShoulderMinOffset: 0.0
            )
        )

        let poseMissingWrist = Pose(joints: [
            .leftShoulder: PoseJoint(location: .init(x: 0.4, y: 0.5), confidence: 1),
            .rightShoulder: PoseJoint(location: .init(x: 0.6, y: 0.5), confidence: 1),
            .leftElbow: PoseJoint(location: .init(x: 0.42, y: 0.45), confidence: 1),
            .rightElbow: PoseJoint(location: .init(x: 0.58, y: 0.45), confidence: 1),
            .leftWrist: PoseJoint(location: .init(x: 0.45, y: 0.55), confidence: 1),
        ])

        let out = calibration.ingest(pose: poseMissingWrist, now: Date(timeIntervalSince1970: 0))
        XCTAssertNil(out.baseline)
        XCTAssertNotNil(out.issue)
    }
}


import XCTest
@testable import VibeSports

final class HeadSteeringSignalTests: XCTestCase {
    func test_turnInputPositiveWhenNoseIsRightOfShoulderCenter() {
        let signal = HeadSteeringSignal()
        let pose = makePose(nose: .init(x: 0.56, y: 0.72), leftShoulder: .init(x: 0.40, y: 0.55), rightShoulder: .init(x: 0.60, y: 0.55))

        XCTAssertGreaterThan(signal.turnInput(from: pose), 0)
    }

    func test_turnInputNegativeWhenNoseIsLeftOfShoulderCenter() {
        let signal = HeadSteeringSignal()
        let pose = makePose(nose: .init(x: 0.44, y: 0.72), leftShoulder: .init(x: 0.40, y: 0.55), rightShoulder: .init(x: 0.60, y: 0.55))

        XCTAssertLessThan(signal.turnInput(from: pose), 0)
    }

    func test_turnInputIsScaleInvariantByShoulderDistance() {
        let signal = HeadSteeringSignal(configuration: .init(minConfidence: 0, deadzone: 0, responseGamma: 1.0, minimumShoulderDistance: 0.0001))
        let nearPose = makePose(
            nose: .init(x: 0.52, y: 0.72),
            leftShoulder: .init(x: 0.45, y: 0.55),
            rightShoulder: .init(x: 0.55, y: 0.55)
        )
        let farPose = makePose(
            nose: .init(x: 0.49, y: 0.72),
            leftShoulder: .init(x: 0.35, y: 0.55),
            rightShoulder: .init(x: 0.55, y: 0.55)
        )

        XCTAssertEqual(signal.turnInput(from: nearPose), signal.turnInput(from: farPose), accuracy: 0.001)
    }

    func test_turnInputReturnsZeroInsideDeadzone() {
        let signal = HeadSteeringSignal(configuration: .init(minConfidence: 0, deadzone: 0.2, responseGamma: 1.0, minimumShoulderDistance: 0.0001))
        let pose = makePose(nose: .init(x: 0.51, y: 0.72), leftShoulder: .init(x: 0.40, y: 0.55), rightShoulder: .init(x: 0.60, y: 0.55))

        XCTAssertEqual(signal.turnInput(from: pose), 0, accuracy: 0.0001)
    }

    func test_turnInputReturnsZeroWhenRequiredJointsMissing() {
        let signal = HeadSteeringSignal()

        let missingNose = Pose(joints: [
            .leftShoulder: PoseJoint(location: .init(x: 0.4, y: 0.5), confidence: 1),
            .rightShoulder: PoseJoint(location: .init(x: 0.6, y: 0.5), confidence: 1),
        ])

        let missingShoulder = Pose(joints: [
            .nose: PoseJoint(location: .init(x: 0.5, y: 0.7), confidence: 1),
            .leftShoulder: PoseJoint(location: .init(x: 0.4, y: 0.5), confidence: 1),
        ])

        XCTAssertEqual(signal.turnInput(from: missingNose), 0)
        XCTAssertEqual(signal.turnInput(from: missingShoulder), 0)
        XCTAssertEqual(signal.turnInput(from: nil), 0)
    }

    private func makePose(nose: CGPoint, leftShoulder: CGPoint, rightShoulder: CGPoint) -> Pose {
        Pose(joints: [
            .nose: PoseJoint(location: nose, confidence: 1),
            .leftShoulder: PoseJoint(location: leftShoulder, confidence: 1),
            .rightShoulder: PoseJoint(location: rightShoulder, confidence: 1),
        ])
    }
}

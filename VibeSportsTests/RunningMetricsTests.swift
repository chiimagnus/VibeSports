import XCTest
@testable import VibeSports

final class RunningMetricsTests: XCTestCase {
    func test_speedIncreasesWhenMovementQualityHigh() {
        var metrics = RunningMetrics()
        let t0 = Date(timeIntervalSince1970: 0)

        _ = metrics.ingest(pose: Self.pose(leftWrist: .init(x: 0.4, y: 0.4), rightWrist: .init(x: 0.6, y: 0.4)), now: t0)

        var now = t0
        for i in 1...20 {
            now = Date(timeIntervalSince1970: TimeInterval(i) * 0.05)
            let dy = (i % 2 == 0) ? 0.08 : -0.08
            _ = metrics.ingest(
                pose: Self.pose(
                    leftWrist: .init(x: 0.4, y: 0.4 + dy),
                    rightWrist: .init(x: 0.6, y: 0.4 - dy)
                ),
                now: now
            )
        }

        XCTAssertGreaterThan(metrics.speedModel.speedMetersPerSecond, 0)
        XCTAssertLessThanOrEqual(metrics.speedModel.speedMetersPerSecond, metrics.speedModel.configuration.maxSpeedMetersPerSecond)
    }

    func test_speedDecaysToZeroWhenNoPose() {
        var metrics = RunningMetrics()
        let t0 = Date(timeIntervalSince1970: 0)

        _ = metrics.ingest(
            pose: Self.pose(leftWrist: .init(x: 0.4, y: 0.5), rightWrist: .init(x: 0.6, y: 0.3)),
            now: t0
        )
        _ = metrics.ingest(
            pose: Self.pose(leftWrist: .init(x: 0.4, y: 0.3), rightWrist: .init(x: 0.6, y: 0.5)),
            now: Date(timeIntervalSince1970: 0.05)
        )

        for i in 1...80 {
            _ = metrics.ingest(pose: nil, now: Date(timeIntervalSince1970: 0.05 + TimeInterval(i) * 0.05))
        }

        XCTAssertEqual(metrics.speedModel.speedMetersPerSecond, 0, accuracy: 0.0001)
    }

    func test_stepsIncreaseWhenArmPhaseAlternates() {
        var metrics = RunningMetrics()
        metrics.stepDetector.configuration.minStepInterval = 0.01
        metrics.stepDetector.configuration.minQualityToCountStep = 0

        let base = Date(timeIntervalSince1970: 0)
        _ = metrics.ingest(pose: Self.pose(leftWrist: .init(x: 0.4, y: 0.6), rightWrist: .init(x: 0.6, y: 0.4)), now: base)
        _ = metrics.ingest(pose: Self.pose(leftWrist: .init(x: 0.4, y: 0.4), rightWrist: .init(x: 0.6, y: 0.6)), now: base.addingTimeInterval(0.05))
        _ = metrics.ingest(pose: Self.pose(leftWrist: .init(x: 0.4, y: 0.6), rightWrist: .init(x: 0.6, y: 0.4)), now: base.addingTimeInterval(0.10))

        XCTAssertGreaterThanOrEqual(metrics.stepDetector.stepCount, 2)
    }

    func test_closeUpModeUsesShoulderDistance() {
        var metrics = RunningMetrics()
        metrics.configuration.closeUpShoulderDistanceThreshold = 0.2
        metrics.configuration.closeUpUpperBodyConfidenceThreshold = 0

        let pose = Pose(joints: [
            .leftShoulder: PoseJoint(location: .init(x: 0.2, y: 0.5), confidence: 1),
            .rightShoulder: PoseJoint(location: .init(x: 0.5, y: 0.5), confidence: 1),
            .leftWrist: PoseJoint(location: .init(x: 0.2, y: 0.3), confidence: 1),
            .rightWrist: PoseJoint(location: .init(x: 0.5, y: 0.3), confidence: 1),
        ])

        let snapshot = metrics.ingest(pose: pose, now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(snapshot.isCloseUpMode)
    }

    private static func pose(leftWrist: CGPoint, rightWrist: CGPoint) -> Pose {
        Pose(joints: [
            .leftWrist: PoseJoint(location: leftWrist, confidence: 1),
            .rightWrist: PoseJoint(location: rightWrist, confidence: 1),
        ])
    }
}

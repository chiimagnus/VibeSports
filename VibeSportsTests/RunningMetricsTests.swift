import XCTest
@testable import VibeSports

final class RunningMetricsTests: XCTestCase {
    func test_stepsIncreaseOnHeadBobCycles() {
        var metrics = RunningMetrics()
        metrics.configuration.strideLengthMetersPerStep = 1.0
        metrics.configuration.stepDetectorConfiguration.minAmplitudeRatio = 0.15
        metrics.configuration.stepDetectorConfiguration.hysteresisRatio = 0.02
        metrics.configuration.stepDetectorConfiguration.minStepInterval = 0.0
        metrics.configuration.stepDetectorConfiguration.baselineSmoothingAlpha = 0
        metrics.configuration.cadenceConfiguration.minStepInterval = 0.0

        let faceHeight = 0.20
        let baseY = 0.50
        let base = Date(timeIntervalSince1970: 0)

        func obs(_ y: Double) -> RunningHeadObservation {
            RunningHeadObservation(
                noseX: 0.5,
                noseY: y,
                faceWidth: 0.2,
                faceHeight: faceHeight,
                confidence: 1.0,
                isDetected: true
            )
        }

        _ = metrics.ingest(observation: obs(baseY), now: base)

        // Step 1 (up+down).
        _ = metrics.ingest(observation: obs(baseY + 0.04), now: base.addingTimeInterval(0.10))
        _ = metrics.ingest(observation: obs(baseY - 0.04), now: base.addingTimeInterval(0.20))

        // Step 2 (up+down).
        _ = metrics.ingest(observation: obs(baseY + 0.04), now: base.addingTimeInterval(0.30))
        let snapshot = metrics.ingest(observation: obs(baseY - 0.04), now: base.addingTimeInterval(0.40))

        XCTAssertEqual(snapshot.steps, 2)
        XCTAssertGreaterThan(snapshot.cadenceStepsPerSecond, 0)
        XCTAssertGreaterThan(snapshot.speedMetersPerSecond, 0)
    }

    func test_minStepIntervalFiltersRapidCycles() {
        var metrics = RunningMetrics()
        metrics.configuration.stepDetectorConfiguration.minAmplitudeRatio = 0.15
        metrics.configuration.stepDetectorConfiguration.hysteresisRatio = 0.02
        metrics.configuration.stepDetectorConfiguration.minStepInterval = 0.5
        metrics.configuration.stepDetectorConfiguration.baselineSmoothingAlpha = 0

        let faceHeight = 0.20
        let baseY = 0.50
        let base = Date(timeIntervalSince1970: 0)

        func obs(_ y: Double) -> RunningHeadObservation {
            RunningHeadObservation(
                noseX: 0.5,
                noseY: y,
                faceWidth: 0.2,
                faceHeight: faceHeight,
                confidence: 1.0,
                isDetected: true
            )
        }

        _ = metrics.ingest(observation: obs(baseY), now: base)

        // First step counts.
        _ = metrics.ingest(observation: obs(baseY + 0.04), now: base.addingTimeInterval(0.10))
        _ = metrics.ingest(observation: obs(baseY - 0.04), now: base.addingTimeInterval(0.20))

        // Second step too soon (filtered).
        _ = metrics.ingest(observation: obs(baseY + 0.04), now: base.addingTimeInterval(0.30))
        let snapshot = metrics.ingest(observation: obs(baseY - 0.04), now: base.addingTimeInterval(0.40))

        XCTAssertEqual(snapshot.steps, 1)
    }

    func test_lostTrackingHoldsThenDecaysCadenceToZero() {
        let base = Date(timeIntervalSince1970: 0)
        var metrics = RunningMetrics()
        metrics.configuration.strideLengthMetersPerStep = 1.0
        metrics.configuration.stepDetectorConfiguration.minAmplitudeRatio = 0.15
        metrics.configuration.stepDetectorConfiguration.hysteresisRatio = 0.02
        metrics.configuration.stepDetectorConfiguration.minStepInterval = 0.0
        metrics.configuration.stepDetectorConfiguration.baselineSmoothingAlpha = 0
        metrics.configuration.cadenceConfiguration.holdDuration = 1.0
        metrics.configuration.cadenceConfiguration.decayDuration = 1.0

        let faceHeight = 0.20
        let baseY = 0.50

        func obs(_ y: Double) -> RunningHeadObservation {
            RunningHeadObservation(
                noseX: 0.5,
                noseY: y,
                faceWidth: 0.2,
                faceHeight: faceHeight,
                confidence: 1.0,
                isDetected: true
            )
        }

        _ = metrics.ingest(observation: obs(baseY), now: base)
        // Step 1.
        _ = metrics.ingest(observation: obs(baseY + 0.04), now: base.addingTimeInterval(0.10))
        _ = metrics.ingest(observation: obs(baseY - 0.04), now: base.addingTimeInterval(0.20))
        // Step 2 (creates cadence).
        _ = metrics.ingest(observation: obs(baseY + 0.04), now: base.addingTimeInterval(0.70))
        let tracked = metrics.ingest(observation: obs(baseY - 0.04), now: base.addingTimeInterval(0.80))

        XCTAssertGreaterThan(tracked.cadenceStepsPerSecond, 0)
        let startCadence = tracked.cadenceStepsPerSecond

        // Tracking lost: cadence holds.
        let held = metrics.ingest(observation: nil, now: base.addingTimeInterval(0.9))
        XCTAssertEqual(held.cadenceStepsPerSecond, startCadence, accuracy: 0.0001)

        // Decay after hold.
        let stillHeld = metrics.ingest(observation: nil, now: base.addingTimeInterval(1.7))
        XCTAssertEqual(stillHeld.cadenceStepsPerSecond, startCadence, accuracy: 0.0001)

        let decaying = metrics.ingest(observation: nil, now: base.addingTimeInterval(2.2))
        XCTAssertLessThan(decaying.cadenceStepsPerSecond, startCadence)
        XCTAssertGreaterThan(decaying.cadenceStepsPerSecond, 0)

        let zeroed = metrics.ingest(observation: nil, now: base.addingTimeInterval(3.1))
        XCTAssertEqual(zeroed.cadenceStepsPerSecond, 0, accuracy: 0.0001)
    }
}

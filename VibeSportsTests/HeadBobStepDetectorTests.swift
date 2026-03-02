import XCTest
@testable import VibeSports

final class HeadBobStepDetectorTests: XCTestCase {
    func test_countsStepOnUpDownCycle() {
        var detector = HeadBobStepDetector()
        detector.configuration.minAmplitudeRatio = 0.15
        detector.configuration.hysteresisRatio = 0.02
        detector.configuration.minStepInterval = 0.0
        detector.configuration.baselineSmoothingAlpha = 0
        detector.configuration.baselineFaceHeightSmoothingAlpha = 0

        let faceHeight = 0.20
        let baseY = 0.50

        let base = Date(timeIntervalSince1970: 0)

        func obs(noseY: Double) -> RunningHeadObservation {
            RunningHeadObservation(
                noseX: 0.5,
                noseY: noseY,
                faceWidth: 0.2,
                faceHeight: faceHeight,
                confidence: 1.0,
                isDetected: true
            )
        }

        _ = detector.ingest(observation: obs(noseY: baseY), now: base)
        _ = detector.ingest(observation: obs(noseY: baseY + 0.04), now: base.addingTimeInterval(0.1))
        let event = detector.ingest(observation: obs(noseY: baseY - 0.04), now: base.addingTimeInterval(0.2))

        XCTAssertNotNil(event)
        XCTAssertEqual(detector.stepCount, 1)
    }

    func test_respectsMinStepInterval() {
        var detector = HeadBobStepDetector()
        detector.configuration.minAmplitudeRatio = 0.15
        detector.configuration.hysteresisRatio = 0.02
        detector.configuration.minStepInterval = 0.5
        detector.configuration.baselineSmoothingAlpha = 0
        detector.configuration.baselineFaceHeightSmoothingAlpha = 0

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

        _ = detector.ingest(observation: obs(baseY), now: base)

        // First cycle counts.
        _ = detector.ingest(observation: obs(baseY + 0.04), now: base.addingTimeInterval(0.10))
        _ = detector.ingest(observation: obs(baseY - 0.04), now: base.addingTimeInterval(0.20))
        XCTAssertEqual(detector.stepCount, 1)

        // Second cycle too soon should be filtered.
        _ = detector.ingest(observation: obs(baseY + 0.04), now: base.addingTimeInterval(0.30))
        _ = detector.ingest(observation: obs(baseY - 0.04), now: base.addingTimeInterval(0.40))
        XCTAssertEqual(detector.stepCount, 1)

        // After min interval, should count again.
        _ = detector.ingest(observation: obs(baseY + 0.04), now: base.addingTimeInterval(0.70))
        _ = detector.ingest(observation: obs(baseY - 0.04), now: base.addingTimeInterval(0.80))
        XCTAssertEqual(detector.stepCount, 2)
    }

    func test_ignoresLowConfidenceOrUndetected() {
        var detector = HeadBobStepDetector()
        detector.configuration.minAmplitudeRatio = 0.10
        detector.configuration.minStepInterval = 0.0
        detector.configuration.minConfidence = 0.7
        detector.configuration.baselineSmoothingAlpha = 0
        detector.configuration.baselineFaceHeightSmoothingAlpha = 0

        let base = Date(timeIntervalSince1970: 0)

        let faceHeight = 0.20
        let baseY = 0.50

        func obs(confidence: Double, isDetected: Bool, y: Double) -> RunningHeadObservation {
            RunningHeadObservation(
                noseX: 0.5,
                noseY: y,
                faceWidth: 0.2,
                faceHeight: faceHeight,
                confidence: confidence,
                isDetected: isDetected
            )
        }

        _ = detector.ingest(observation: obs(confidence: 1.0, isDetected: true, y: baseY), now: base)
        _ = detector.ingest(observation: obs(confidence: 0.2, isDetected: true, y: baseY + 0.04), now: base.addingTimeInterval(0.1))
        _ = detector.ingest(observation: obs(confidence: 1.0, isDetected: false, y: baseY - 0.04), now: base.addingTimeInterval(0.2))

        XCTAssertEqual(detector.stepCount, 0)
    }
}

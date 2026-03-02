import XCTest
@testable import VibeSports

final class CadenceModelTests: XCTestCase {
    func test_fixedStepIntervalConvergesCadence() {
        var model = CadenceModel()
        let base = Date(timeIntervalSince1970: 0)

        model.ingestStep(now: base)
        for index in 1...8 {
            model.ingestStep(now: base.addingTimeInterval(TimeInterval(index) * 0.5))
        }

        XCTAssertEqual(model.cadenceStepsPerSecond, 2.0, accuracy: 0.2)
        XCTAssertEqual(model.cadenceStepsPerMinute, 120.0, accuracy: 12.0)
    }

    func test_timeoutResetsCadenceToZero() {
        var model = CadenceModel()
        model.configuration.holdDuration = 0
        model.configuration.decayDuration = 0
        model.configuration.maxStepInterval = 1.0
        let base = Date(timeIntervalSince1970: 0)

        model.ingestStep(now: base)
        model.ingestStep(now: base.addingTimeInterval(0.5))
        XCTAssertGreaterThan(model.cadenceStepsPerSecond, 0)

        model.update(now: base.addingTimeInterval(1.6), isTracking: true)
        XCTAssertEqual(model.cadenceStepsPerSecond, 0, accuracy: 0.0001)
    }

    func test_filtersTooFastIntervalsAndResetsOnTooSlowIntervals() {
        var model = CadenceModel()
        model.configuration.holdDuration = 0
        model.configuration.decayDuration = 0
        let base = Date(timeIntervalSince1970: 0)

        model.ingestStep(now: base)
        model.ingestStep(now: base.addingTimeInterval(0.1))
        XCTAssertEqual(model.cadenceStepsPerSecond, 0, accuracy: 0.0001)

        model.ingestStep(now: base.addingTimeInterval(0.5))
        XCTAssertGreaterThan(model.cadenceStepsPerSecond, 0)

        model.ingestStep(now: base.addingTimeInterval(2.5))
        XCTAssertEqual(model.cadenceStepsPerSecond, 0, accuracy: 0.0001)
    }

    func test_intervalDrivenIngestMatchesTimestampDrivenIngest() {
        var timestampModel = CadenceModel()
        var intervalModel = CadenceModel()
        timestampModel.configuration.holdDuration = 0
        timestampModel.configuration.decayDuration = 0
        intervalModel.configuration.holdDuration = 0
        intervalModel.configuration.decayDuration = 0

        let base = Date(timeIntervalSince1970: 0)
        let timestamps: [TimeInterval] = [0.0, 0.55, 1.00, 1.52, 2.05]

        timestampModel.ingestStep(now: base.addingTimeInterval(timestamps[0]))
        intervalModel.ingestStep(now: base.addingTimeInterval(timestamps[0]), intervalSincePreviousStep: nil)

        for index in 1..<timestamps.count {
            let now = base.addingTimeInterval(timestamps[index])
            let interval = timestamps[index] - timestamps[index - 1]
            timestampModel.ingestStep(now: now)
            intervalModel.ingestStep(now: now, intervalSincePreviousStep: interval)
        }

        XCTAssertEqual(
            intervalModel.cadenceStepsPerSecond,
            timestampModel.cadenceStepsPerSecond,
            accuracy: 0.0001
        )
    }

    func test_lostTrackingHoldsThenDecaysToZero() {
        var model = CadenceModel()
        model.configuration.holdDuration = 1.0
        model.configuration.decayDuration = 1.0
        let base = Date(timeIntervalSince1970: 0)

        model.ingestStep(now: base)
        model.ingestStep(now: base.addingTimeInterval(0.5))
        let startCadence = model.cadenceStepsPerSecond
        XCTAssertGreaterThan(startCadence, 0)

        // Mark tracking as lost.
        model.update(now: base.addingTimeInterval(0.6), isTracking: false)

        // During hold window, cadence stays constant.
        model.update(now: base.addingTimeInterval(1.4), isTracking: false)
        XCTAssertEqual(model.cadenceStepsPerSecond, startCadence, accuracy: 0.0001)

        // After hold, cadence decays toward 0.
        model.update(now: base.addingTimeInterval(1.8), isTracking: false)
        XCTAssertLessThan(model.cadenceStepsPerSecond, startCadence)
        XCTAssertGreaterThan(model.cadenceStepsPerSecond, 0)

        model.update(now: base.addingTimeInterval(2.7), isTracking: false)
        XCTAssertEqual(model.cadenceStepsPerSecond, 0, accuracy: 0.0001)
    }
}

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
        let base = Date(timeIntervalSince1970: 0)

        model.ingestStep(now: base)
        model.ingestStep(now: base.addingTimeInterval(0.5))
        XCTAssertGreaterThan(model.cadenceStepsPerSecond, 0)

        model.update(now: base.addingTimeInterval(1.6))
        XCTAssertEqual(model.cadenceStepsPerSecond, 0, accuracy: 0.0001)
    }

    func test_filtersTooFastIntervalsAndResetsOnTooSlowIntervals() {
        var model = CadenceModel()
        let base = Date(timeIntervalSince1970: 0)

        model.ingestStep(now: base)
        model.ingestStep(now: base.addingTimeInterval(0.1))
        XCTAssertEqual(model.cadenceStepsPerSecond, 0, accuracy: 0.0001)

        model.ingestStep(now: base.addingTimeInterval(0.5))
        XCTAssertGreaterThan(model.cadenceStepsPerSecond, 0)

        model.ingestStep(now: base.addingTimeInterval(2.5))
        XCTAssertEqual(model.cadenceStepsPerSecond, 0, accuracy: 0.0001)
    }
}

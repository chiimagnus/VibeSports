import XCTest
@testable import VibeSports

final class ClockTests: XCTestCase {
    func test_systemClockNowReturnsCurrentDate() {
        let clock: any Clock = SystemClock()
        let before = Date()
        let now = clock.now
        let after = Date()

        XCTAssertGreaterThanOrEqual(now, before)
        XCTAssertLessThanOrEqual(now, after)
    }
}


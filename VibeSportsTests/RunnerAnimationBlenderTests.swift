import XCTest
@testable import VibeSports

final class RunnerAnimationBlenderTests: XCTestCase {
    func test_speedBelowIdleThreshold_isAllIdle() {
        let blender = RunnerAnimationBlender()
        let blend = blender.blend(speedMetersPerSecond: 0)

        XCTAssertEqual(blend.idleWeight, 1, accuracy: 0.000001)
        XCTAssertEqual(blend.slowRunWeight, 0, accuracy: 0.000001)
        XCTAssertEqual(blend.fastRunWeight, 0, accuracy: 0.000001)
        XCTAssertEqual(blend.idleWeight + blend.slowRunWeight + blend.fastRunWeight, 1, accuracy: 0.000001)
    }

    func test_speedAroundMinRun_isMostlySlow() {
        var blender = RunnerAnimationBlender()
        blender.configuration.idleThresholdMetersPerSecond = 0.1
        blender.configuration.minRunSpeedMetersPerSecond = 1.5
        blender.configuration.maxRunSpeedMetersPerSecond = 4.5

        let blend = blender.blend(speedMetersPerSecond: 1.5)

        XCTAssertEqual(blend.idleWeight, 0, accuracy: 0.000001)
        XCTAssertEqual(blend.slowRunWeight, 1, accuracy: 0.000001)
        XCTAssertEqual(blend.fastRunWeight, 0, accuracy: 0.000001)
        XCTAssertEqual(blend.idleWeight + blend.slowRunWeight + blend.fastRunWeight, 1, accuracy: 0.000001)
    }

    func test_speedAboveMaxRun_isAllFast() {
        var blender = RunnerAnimationBlender()
        blender.configuration.maxRunSpeedMetersPerSecond = 4.5

        let blend = blender.blend(speedMetersPerSecond: 99)

        XCTAssertEqual(blend.idleWeight, 0, accuracy: 0.000001)
        XCTAssertEqual(blend.slowRunWeight, 0, accuracy: 0.000001)
        XCTAssertEqual(blend.fastRunWeight, 1, accuracy: 0.000001)
        XCTAssertEqual(blend.idleWeight + blend.slowRunWeight + blend.fastRunWeight, 1, accuracy: 0.000001)
    }

    func test_playbackRate_isClamped() {
        var blender = RunnerAnimationBlender()
        blender.configuration.baseSpeedMetersPerSecond = 2
        blender.configuration.minPlaybackRate = 0.3
        blender.configuration.maxPlaybackRate = 3.0

        XCTAssertEqual(blender.blend(speedMetersPerSecond: 0).playbackRate, 0.3, accuracy: 0.000001)
        XCTAssertEqual(blender.blend(speedMetersPerSecond: 2).playbackRate, 1.0, accuracy: 0.000001)
        XCTAssertEqual(blender.blend(speedMetersPerSecond: 100).playbackRate, 3.0, accuracy: 0.000001)
    }
}


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

    func test_cameraRunningTuning_reachesFastBlendAtHighCadenceSpeed() {
        var blender = RunnerAnimationBlender()
        blender.configuration = RunnerSceneRenderer.Tuning.default.blender

        let blend = blender.blend(speedMetersPerSecond: 2.6)

        XCTAssertGreaterThan(blend.fastRunWeight, 0.7)
        XCTAssertLessThan(blend.slowRunWeight, 0.3)
        XCTAssertEqual(blend.idleWeight + blend.slowRunWeight + blend.fastRunWeight, 1, accuracy: 0.000001)
    }
}

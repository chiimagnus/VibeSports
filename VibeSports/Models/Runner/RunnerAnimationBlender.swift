import Foundation

struct RunnerAnimationBlend: Sendable, Equatable {
    var idleWeight: Double
    var slowRunWeight: Double
    var fastRunWeight: Double
    var playbackRate: Double
}

struct RunnerAnimationBlender: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var idleThresholdMetersPerSecond: Double = 0.10
        var minRunSpeedMetersPerSecond: Double = 1.50
        var maxRunSpeedMetersPerSecond: Double = 4.50

        var baseSpeedMetersPerSecond: Double = 2.00
        var minPlaybackRate: Double = 0.30
        var maxPlaybackRate: Double = 3.00
    }

    var configuration = Configuration()

    func blend(speedMetersPerSecond: Double) -> RunnerAnimationBlend {
        let speed = max(0, speedMetersPerSecond)

        let idleThreshold = configuration.idleThresholdMetersPerSecond
        let minRun = max(idleThreshold, configuration.minRunSpeedMetersPerSecond)
        let maxRun = max(minRun, configuration.maxRunSpeedMetersPerSecond)

        let idleWeight: Double
        let slowWeight: Double
        let fastWeight: Double

        if speed < idleThreshold {
            idleWeight = 1
            slowWeight = 0
            fastWeight = 0
        } else if speed < minRun {
            let t = (speed - idleThreshold) / max(0.0001, minRun - idleThreshold)
            idleWeight = 1 - t
            slowWeight = t
            fastWeight = 0
        } else {
            let t = ((speed - minRun) / max(0.0001, maxRun - minRun)).clamped(to: 0...1)
            idleWeight = 0
            slowWeight = 1 - t
            fastWeight = t
        }

        let playbackRate = (speed / max(0.0001, configuration.baseSpeedMetersPerSecond))
            .clamped(to: configuration.minPlaybackRate...configuration.maxPlaybackRate)

        return RunnerAnimationBlend(
            idleWeight: idleWeight,
            slowRunWeight: slowWeight,
            fastRunWeight: fastWeight,
            playbackRate: playbackRate
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}


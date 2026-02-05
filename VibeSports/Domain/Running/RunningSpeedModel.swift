import Foundation

struct RunningSpeedModel: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var maxSpeedMetersPerSecond: Double = 6
        var accelerationMetersPerSecondSquared: Double = 2.4
        var decelerationMetersPerSecondSquared: Double = 2.4
    }

    var configuration = Configuration()
    private(set) var speedMetersPerSecond: Double = 0

    mutating func update(isMoving: Bool, deltaTime: TimeInterval) {
        let dt = max(0, deltaTime)

        if isMoving {
            speedMetersPerSecond = min(
                configuration.maxSpeedMetersPerSecond,
                speedMetersPerSecond + configuration.accelerationMetersPerSecondSquared * dt
            )
        } else {
            speedMetersPerSecond = max(
                0,
                speedMetersPerSecond - configuration.decelerationMetersPerSecondSquared * dt
            )
        }
    }
}


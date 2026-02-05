import Foundation

struct CaloriesEstimator: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var adjustmentFactor: Double = 0.7
    }

    var configuration = Configuration()
    private(set) var caloriesBurned: Double = 0

    mutating func reset() {
        caloriesBurned = 0
    }

    mutating func ingest(speedMetersPerSecond: Double, userWeightKg: Double, deltaTime: TimeInterval) {
        guard speedMetersPerSecond > 0 else { return }

        let speedKmh = speedMetersPerSecond * 3.6
        let met: Double

        if speedKmh < 7 {
            met = 4.5
        } else if speedKmh < 12 {
            met = 7.5
        } else {
            met = 9.5
        }

        let dtHours = max(0, deltaTime) / 3600.0
        let kcal = met * max(0, userWeightKg) * dtHours * configuration.adjustmentFactor
        caloriesBurned += kcal
    }
}


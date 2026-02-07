struct RunnerMotion: Sendable, Equatable {
    var speedMetersPerSecond: Double
    var cadenceStepsPerSecond: Double
    var cadenceStepsPerMinute: Double

    static let zero = RunnerMotion(
        speedMetersPerSecond: 0,
        cadenceStepsPerSecond: 0,
        cadenceStepsPerMinute: 0
    )
}

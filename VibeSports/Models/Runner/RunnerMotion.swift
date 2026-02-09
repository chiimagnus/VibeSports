struct RunnerMotion: Sendable, Equatable {
    var speedMetersPerSecond: Double
    var cadenceStepsPerSecond: Double
    var cadenceStepsPerMinute: Double
    var forwardInput: Double
    var turnInput: Double
    var headingYaw: Double

    static let zero = RunnerMotion(
        speedMetersPerSecond: 0,
        cadenceStepsPerSecond: 0,
        cadenceStepsPerMinute: 0,
        forwardInput: 0,
        turnInput: 0,
        headingYaw: 0
    )
}

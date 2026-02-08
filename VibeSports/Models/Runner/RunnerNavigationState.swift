struct RunnerNavigationState: Sendable, Equatable {
    var positionX: Double
    var positionZ: Double
    var headingYaw: Double

    static let zero = RunnerNavigationState(
        positionX: 0,
        positionZ: 0,
        headingYaw: 0
    )
}

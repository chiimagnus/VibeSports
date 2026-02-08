struct RunnerControlInput: Sendable, Equatable {
    var turnInput: Double
    var forwardInput: Double

    static let zero = RunnerControlInput(turnInput: 0, forwardInput: 0)

    var hasInput: Bool {
        abs(turnInput) > 0.0001 || abs(forwardInput) > 0.0001
    }

    func clamped() -> RunnerControlInput {
        RunnerControlInput(
            turnInput: turnInput.clamped(to: -1...1),
            forwardInput: forwardInput.clamped(to: -1...1)
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

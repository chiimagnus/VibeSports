import Foundation

struct CadenceModel: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var minStepInterval: TimeInterval = 0.15
        var maxStepInterval: TimeInterval = 1.5
        var smoothingAlpha: Double = 0.25
        var timeoutToZero: TimeInterval = 1.0
    }

    var configuration = Configuration()

    private(set) var cadenceStepsPerSecond: Double = 0
    var cadenceStepsPerMinute: Double { cadenceStepsPerSecond * 60.0 }

    private var lastStepTime: Date?

    mutating func reset() {
        cadenceStepsPerSecond = 0
        lastStepTime = nil
    }

    mutating func ingestStep(now: Date) {
        ingestStep(
            now: now,
            intervalSincePreviousStep: lastStepTime.map { now.timeIntervalSince($0) }
        )
    }

    mutating func ingestStep(now: Date, intervalSincePreviousStep: TimeInterval?) {
        if let intervalSincePreviousStep {
            guard applyInterval(intervalSincePreviousStep) else { return }
        }

        lastStepTime = now
    }

    mutating func update(now: Date) {
        guard let lastStepTime else {
            cadenceStepsPerSecond = 0
            return
        }

        if now.timeIntervalSince(lastStepTime) >= configuration.timeoutToZero {
            cadenceStepsPerSecond = 0
        }
    }

    private mutating func applyInterval(_ interval: TimeInterval) -> Bool {
        if interval < configuration.minStepInterval {
            return false
        }

        if interval > configuration.maxStepInterval {
            cadenceStepsPerSecond = 0
            return true
        }

        let instantaneousCadence = 1.0 / max(interval, 0.0001)
        if cadenceStepsPerSecond == 0 {
            cadenceStepsPerSecond = instantaneousCadence
        } else {
            let alpha = min(max(configuration.smoothingAlpha, 0), 1)
            cadenceStepsPerSecond = (1 - alpha) * cadenceStepsPerSecond + alpha * instantaneousCadence
        }
        return true
    }
}

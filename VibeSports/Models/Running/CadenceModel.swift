import Foundation

struct CadenceModel: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var minStepInterval: TimeInterval = 0.15
        var maxStepInterval: TimeInterval = 1.5
        var smoothingAlpha: Double = 0.25
        var holdDuration: TimeInterval = 0.8
        var decayDuration: TimeInterval = 0.8
    }

    var configuration = Configuration()

    private(set) var cadenceStepsPerSecond: Double = 0
    var cadenceStepsPerMinute: Double { cadenceStepsPerSecond * 60.0 }

    private var lastStepTime: Date?
    private var lostTrackingSince: Date?
    private var cadenceAtTrackingLoss: Double?

    mutating func reset() {
        cadenceStepsPerSecond = 0
        lastStepTime = nil
        lostTrackingSince = nil
        cadenceAtTrackingLoss = nil
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

    /// Updates cadence for "no step" and "lost tracking" conditions.
    ///
    /// - `isTracking` should represent whether the upstream detector has a valid subject signal.
    mutating func update(now: Date, isTracking: Bool) {
        if isTracking {
            lostTrackingSince = nil
            cadenceAtTrackingLoss = nil
            updateNoStepWhileTracking(now: now)
            return
        }

        if lostTrackingSince == nil {
            lostTrackingSince = now
            cadenceAtTrackingLoss = cadenceStepsPerSecond
        }

        let hold = max(0, configuration.holdDuration)
        let decay = max(0, configuration.decayDuration)

        let elapsed = now.timeIntervalSince(lostTrackingSince ?? now)
        let startValue = max(0, cadenceAtTrackingLoss ?? cadenceStepsPerSecond)

        if elapsed <= hold {
            cadenceStepsPerSecond = startValue
            return
        }

        guard decay > 0 else {
            cadenceStepsPerSecond = 0
            return
        }

        let t = min(1, max(0, (elapsed - hold) / decay))
        cadenceStepsPerSecond = (1 - t) * startValue
    }

    private mutating func updateNoStepWhileTracking(now: Date) {
        guard let lastStepTime else {
            cadenceStepsPerSecond = 0
            return
        }

        if now.timeIntervalSince(lastStepTime) >= configuration.maxStepInterval {
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

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
        if let lastStepTime {
            let interval = now.timeIntervalSince(lastStepTime)

            if interval < configuration.minStepInterval {
                return
            }

            if interval > configuration.maxStepInterval {
                cadenceStepsPerSecond = 0
                self.lastStepTime = now
                return
            }

            let instantaneousCadence = 1.0 / max(interval, 0.0001)
            if cadenceStepsPerSecond == 0 {
                cadenceStepsPerSecond = instantaneousCadence
            } else {
                let alpha = min(max(configuration.smoothingAlpha, 0), 1)
                cadenceStepsPerSecond = (1 - alpha) * cadenceStepsPerSecond + alpha * instantaneousCadence
            }
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
}

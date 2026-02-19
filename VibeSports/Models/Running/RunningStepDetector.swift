import Foundation

struct RunningStepDetector: Sendable, Equatable {
    struct StepEvent: Sendable, Equatable {
        let intervalSincePreviousStep: TimeInterval?
    }

    enum ArmPhase: Sendable, Equatable {
        case neutral
        case leftUp
        case rightUp
    }

    struct Configuration: Sendable, Equatable {
        var armPhaseThreshold: Double = 0.06
        var minStepInterval: TimeInterval = 0.25
        var minQualityToCountStep: Double = 0.25
    }

    var configuration = Configuration()

    private(set) var stepCount: Int = 0
    private var lastStepTime: Date?
    private var lastPhase: ArmPhase = .neutral

    mutating func reset() {
        stepCount = 0
        lastStepTime = nil
        lastPhase = .neutral
    }

    mutating func ingest(pose: Pose?, movementQuality: Double, now: Date) -> StepEvent? {
        ingest(pose: pose, movementQuality: movementQuality, scale: nil, now: now)
    }

    mutating func ingest(pose: Pose?, movementQuality: Double, scale: Double?, now: Date) -> StepEvent? {
        guard movementQuality >= configuration.minQualityToCountStep else {
            lastPhase = .neutral
            return nil
        }

        let scale = max(0.0001, scale ?? 1.0)
        let phase = Self.detectArmPhase(from: pose, threshold: configuration.armPhaseThreshold, scale: scale)
        guard phase != .neutral else {
            lastPhase = .neutral
            return nil
        }

        let phaseChanged = phase != lastPhase && !(phase == .neutral && lastPhase == .neutral)
        guard phaseChanged else { return nil }

        let intervalSincePreviousStep: TimeInterval?
        if let lastStepTime {
            let interval = now.timeIntervalSince(lastStepTime)
            guard interval >= configuration.minStepInterval else { return nil }
            intervalSincePreviousStep = interval
        } else {
            intervalSincePreviousStep = nil
        }

        stepCount += 1
        lastStepTime = now
        lastPhase = phase
        return StepEvent(intervalSincePreviousStep: intervalSincePreviousStep)
    }

    private static func detectArmPhase(from pose: Pose?, threshold: Double, scale: Double) -> ArmPhase {
        guard
            let left = pose?.joint(.leftWrist),
            let right = pose?.joint(.rightWrist)
        else { return .neutral }

        let deltaNormalized = Double(left.location.y - right.location.y) / max(0.0001, scale)
        if deltaNormalized > threshold {
            return .leftUp
        } else if deltaNormalized < -threshold {
            return .rightUp
        } else {
            return .neutral
        }
    }
}

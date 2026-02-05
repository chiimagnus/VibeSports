import Foundation

struct RunningStepDetector: Sendable, Equatable {
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

    mutating func ingest(pose: Pose?, movementQuality: Double, now: Date) {
        guard movementQuality >= configuration.minQualityToCountStep else {
            lastPhase = .neutral
            return
        }

        let phase = Self.detectArmPhase(from: pose, threshold: configuration.armPhaseThreshold)
        guard phase != .neutral else {
            lastPhase = .neutral
            return
        }

        let phaseChanged = phase != lastPhase && !(phase == .neutral && lastPhase == .neutral)
        guard phaseChanged else { return }

        if let lastStepTime {
            guard now.timeIntervalSince(lastStepTime) >= configuration.minStepInterval else { return }
        }

        stepCount += 1
        lastStepTime = now
        lastPhase = phase
    }

    private static func detectArmPhase(from pose: Pose?, threshold: Double) -> ArmPhase {
        guard
            let left = pose?.joint(.leftWrist),
            let right = pose?.joint(.rightWrist)
        else { return .neutral }

        let delta = left.location.y - right.location.y
        if delta > threshold {
            return .leftUp
        } else if delta < -threshold {
            return .rightUp
        } else {
            return .neutral
        }
    }
}


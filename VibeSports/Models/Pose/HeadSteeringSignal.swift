import Foundation

struct HeadSteeringSignal: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var minConfidence: Double = 0.35
        var deadzone: Double = 0.08
        var responseGamma: Double = 1.2
        var minimumShoulderDistance: Double = 0.0001
    }

    var configuration = Configuration()

    func turnInput(from pose: Pose?) -> Double {
        guard
            let nose = pose?.joint(.nose),
            let leftShoulder = pose?.joint(.leftShoulder),
            let rightShoulder = pose?.joint(.rightShoulder)
        else {
            return 0
        }

        let minConfidence = max(0, configuration.minConfidence)
        guard nose.confidence >= minConfidence else { return 0 }
        guard leftShoulder.confidence >= minConfidence else { return 0 }
        guard rightShoulder.confidence >= minConfidence else { return 0 }

        let centerX = (leftShoulder.location.x + rightShoulder.location.x) * 0.5
        let shoulderDx = leftShoulder.location.x - rightShoulder.location.x
        let shoulderDy = leftShoulder.location.y - rightShoulder.location.y
        let shoulderDistance = max(configuration.minimumShoulderDistance, sqrt(shoulderDx * shoulderDx + shoulderDy * shoulderDy))

        let raw = Double((nose.location.x - centerX) / shoulderDistance)
        return applyResponseCurve(to: raw)
    }

    private func applyResponseCurve(to input: Double) -> Double {
        let clamped = min(1, max(-1, input))
        let sign: Double = clamped >= 0 ? 1 : -1
        let magnitude = abs(clamped)

        let deadzone = min(max(configuration.deadzone, 0), 0.95)
        guard magnitude > deadzone else { return 0 }

        let normalized = (magnitude - deadzone) / (1 - deadzone)
        let gamma = max(0.01, configuration.responseGamma)
        let curved = pow(normalized, gamma)
        return sign * min(1, max(0, curved))
    }
}

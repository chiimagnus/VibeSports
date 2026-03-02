import Foundation

struct RunningHeadSteeringSignal: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var minConfidence: Double = 0.35
        var deadzone: Double = 0.08
        var responseGamma: Double = 1.2
        var minimumFaceWidth: Double = 0.0001
    }

    var configuration = Configuration()

    func turnInput(from observation: RunningHeadObservation?) -> Double {
        guard let observation else { return 0 }

        let minConfidence = max(0, configuration.minConfidence)
        guard observation.isDetected, observation.confidence >= minConfidence else { return 0 }

        let faceWidth = max(configuration.minimumFaceWidth, observation.faceWidth)
        let raw = (observation.noseX - 0.5) / faceWidth
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


import Foundation

struct HeadBobStepDetector: Sendable, Equatable {
    struct StepEvent: Sendable, Equatable {
        let intervalSincePreviousStep: TimeInterval?
    }

    struct Configuration: Sendable, Equatable {
        var minAmplitudeRatio: Double = 0.015
        var hysteresisRatio: Double = 0.004
        var minStepInterval: TimeInterval = 0.20
        var minConfidence: Double = 0.15

        var baselineSmoothingAlpha: Double = 0.01
        /// Separately smooth the baseline scale used for normalization so forward/back movement doesn't break amplitude.
        var baselineFaceHeightSmoothingAlpha: Double = 0.03
        /// Only update the baseline when very close to baseline, otherwise it will "chase" the bob and erase amplitude.
        var baselineUpdateMaxDisplacementRatio: Double = 0.004
    }

    enum Phase: Sendable, Equatable {
        case neutral
        case sawUp
        case sawDown
    }

    var configuration = Configuration()

    private(set) var stepCount: Int = 0

    private var baselineNoseY: Double?
    private var baselineFaceHeight: Double?
    private var phase: Phase = .neutral
    private var lastStepTime: Date?

    mutating func reset() {
        stepCount = 0
        baselineNoseY = nil
        baselineFaceHeight = nil
        phase = .neutral
        lastStepTime = nil
    }

    mutating func ingest(observation: RunningHeadObservation?, now: Date) -> StepEvent? {
        guard let observation else {
            phase = .neutral
            return nil
        }

        let minConfidence = max(0, configuration.minConfidence)
        guard observation.isDetected, observation.confidence >= minConfidence else {
            phase = .neutral
            return nil
        }

        let faceHeight = max(0.0001, observation.faceHeight)

        if baselineNoseY == nil {
            baselineNoseY = observation.noseY
            baselineFaceHeight = faceHeight
            phase = .neutral
            return nil
        }

        let baseline = baselineNoseY ?? observation.noseY
        let normalizationHeight = max(0.0001, baselineFaceHeight ?? faceHeight)
        let displacementRatio = (observation.noseY - baseline) / normalizationHeight

        updateBaselineIfNeeded(
            observation: observation,
            faceHeight: faceHeight,
            displacementRatio: displacementRatio,
            phase: phase
        )

        let threshold = max(0, configuration.minAmplitudeRatio)
        let hysteresis = min(max(0, configuration.hysteresisRatio), threshold)

        let upperTrigger = threshold
        let lowerTrigger = -threshold
        let upperRelease = threshold - hysteresis
        let lowerRelease = -threshold + hysteresis

        switch phase {
        case .neutral:
            if displacementRatio >= upperTrigger {
                phase = .sawUp
            } else if displacementRatio <= lowerTrigger {
                phase = .sawDown
            }
            return nil

        case .sawUp:
            if displacementRatio <= lowerTrigger {
                return commitStepIfAllowed(now: now)
            }
            if displacementRatio <= upperRelease {
                // Allow re-arming on noise around the upper threshold.
                phase = .neutral
            }
            return nil

        case .sawDown:
            if displacementRatio >= upperTrigger {
                return commitStepIfAllowed(now: now)
            }
            if displacementRatio >= lowerRelease {
                phase = .neutral
            }
            return nil
        }
    }

    private mutating func commitStepIfAllowed(now: Date) -> StepEvent? {
        let minInterval = max(0, configuration.minStepInterval)

        let intervalSincePreviousStep: TimeInterval?
        if let lastStepTime {
            let interval = now.timeIntervalSince(lastStepTime)
            guard interval >= minInterval else {
                phase = .neutral
                return nil
            }
            intervalSincePreviousStep = interval
        } else {
            intervalSincePreviousStep = nil
        }

        stepCount += 1
        lastStepTime = now
        phase = .neutral
        return StepEvent(intervalSincePreviousStep: intervalSincePreviousStep)
    }

    private mutating func updateBaselineIfNeeded(
        observation: RunningHeadObservation,
        faceHeight: Double,
        displacementRatio: Double,
        phase: Phase
    ) {
        guard phase == .neutral else { return }

        let faceAlpha = min(1, max(0, configuration.baselineFaceHeightSmoothingAlpha))
        if faceAlpha > 0 {
            let current = baselineFaceHeight ?? faceHeight
            baselineFaceHeight = (1 - faceAlpha) * current + faceAlpha * faceHeight
        }

        let maxUpdateRatio = max(0, configuration.baselineUpdateMaxDisplacementRatio)
        guard abs(displacementRatio) <= maxUpdateRatio else { return }

        let alpha = min(1, max(0, configuration.baselineSmoothingAlpha))
        guard alpha > 0 else { return }

        let baseline = baselineNoseY ?? observation.noseY
        baselineNoseY = (1 - alpha) * baseline + alpha * observation.noseY
    }
}

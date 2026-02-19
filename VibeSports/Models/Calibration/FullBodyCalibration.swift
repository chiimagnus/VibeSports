import CoreGraphics
import Foundation

struct FullBodyCalibration: Sendable, Equatable {
    enum Issue: Sendable, Equatable {
        case noPose
        case missingJoints([PoseJointName])
        case subjectTooClose
        case subjectTooFar
        case unstable

        var message: String {
            switch self {
            case .noPose:
                return "No pose detected."
            case .missingJoints:
                return "Keep your full body in frame (including ankles)."
            case .subjectTooClose:
                return "Too close — move back."
            case .subjectTooFar:
                return "Too far — move closer."
            case .unstable:
                return "Hold still…"
            }
        }
    }

    struct Baseline: Sendable, Equatable {
        var leftShoulder: CGPoint
        var rightShoulder: CGPoint
        var leftHip: CGPoint
        var rightHip: CGPoint
        var leftAnkle: CGPoint
        var rightAnkle: CGPoint

        var shoulderDistance: Double
        var hipDistance: Double
        var ankleDistance: Double
    }

    struct Output: Sendable, Equatable {
        var progress: Double
        var issue: Issue?
        var baseline: Baseline?
    }

    struct Configuration: Sendable, Equatable {
        var minJointConfidence: Double = 0.25

        var stableDuration: TimeInterval = 0.9
        var stabilityToleranceNormalized: Double = 0.07
        var smoothingAlpha: Double = 0.25

        var minShoulderDistance: Double = 0.12
        var maxShoulderDistance: Double = 0.42
    }

    var configuration = Configuration()

    private struct State: Sendable, Equatable {
        var candidate: Baseline?
        var stableSince: Date?
        var lastIssue: Issue?
    }

    private var state = State()

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    mutating func reset() {
        state = State()
    }

    mutating func ingest(pose: Pose?, now: Date) -> Output {
        guard let pose else {
            state.lastIssue = .noPose
            state.stableSince = nil
            return Output(progress: 0, issue: state.lastIssue, baseline: nil)
        }

        let required: [PoseJointName] = [
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftAnkle, .rightAnkle,
        ]

        var missing: [PoseJointName] = []
        missing.reserveCapacity(required.count)

        func point(_ name: PoseJointName) -> CGPoint? {
            guard let joint = pose.joint(name) else {
                missing.append(name)
                return nil
            }
            if joint.confidence < configuration.minJointConfidence {
                missing.append(name)
                return nil
            }
            return joint.location
        }

        guard
            let leftShoulder = point(.leftShoulder),
            let rightShoulder = point(.rightShoulder),
            let leftHip = point(.leftHip),
            let rightHip = point(.rightHip),
            let leftAnkle = point(.leftAnkle),
            let rightAnkle = point(.rightAnkle)
        else {
            state.lastIssue = .missingJoints(missing)
            state.stableSince = nil
            return Output(progress: 0, issue: state.lastIssue, baseline: nil)
        }

        let shoulderDistance = distance(leftShoulder, rightShoulder)
        if shoulderDistance > configuration.maxShoulderDistance {
            state.lastIssue = .subjectTooClose
            state.stableSince = nil
            return Output(progress: 0, issue: state.lastIssue, baseline: nil)
        }
        if shoulderDistance < configuration.minShoulderDistance {
            state.lastIssue = .subjectTooFar
            state.stableSince = nil
            return Output(progress: 0, issue: state.lastIssue, baseline: nil)
        }

        let measurement = Baseline(
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftHip: leftHip,
            rightHip: rightHip,
            leftAnkle: leftAnkle,
            rightAnkle: rightAnkle,
            shoulderDistance: shoulderDistance,
            hipDistance: distance(leftHip, rightHip),
            ankleDistance: distance(leftAnkle, rightAnkle)
        )

        if var candidate = state.candidate {
            let alpha = min(1, max(0, configuration.smoothingAlpha))
            candidate.leftShoulder = filter(previous: candidate.leftShoulder, current: measurement.leftShoulder, alpha: alpha)
            candidate.rightShoulder = filter(previous: candidate.rightShoulder, current: measurement.rightShoulder, alpha: alpha)
            candidate.leftHip = filter(previous: candidate.leftHip, current: measurement.leftHip, alpha: alpha)
            candidate.rightHip = filter(previous: candidate.rightHip, current: measurement.rightHip, alpha: alpha)
            candidate.leftAnkle = filter(previous: candidate.leftAnkle, current: measurement.leftAnkle, alpha: alpha)
            candidate.rightAnkle = filter(previous: candidate.rightAnkle, current: measurement.rightAnkle, alpha: alpha)
            candidate.shoulderDistance = (1 - alpha) * candidate.shoulderDistance + alpha * measurement.shoulderDistance
            candidate.hipDistance = (1 - alpha) * candidate.hipDistance + alpha * measurement.hipDistance
            candidate.ankleDistance = (1 - alpha) * candidate.ankleDistance + alpha * measurement.ankleDistance
            state.candidate = candidate
        } else {
            state.candidate = measurement
        }

        let candidate = state.candidate ?? measurement
        let normalizedMaxDelta = maxNormalizedDelta(candidate: candidate, measurement: measurement)
        let isStable = normalizedMaxDelta <= configuration.stabilityToleranceNormalized

        if isStable {
            if state.stableSince == nil {
                state.stableSince = now
            }
            let elapsed = now.timeIntervalSince(state.stableSince ?? now)
            let duration = max(0.001, configuration.stableDuration)
            let progress = min(1, max(0, elapsed / duration))
            state.lastIssue = nil
            if elapsed >= duration {
                return Output(progress: 1, issue: nil, baseline: candidate)
            }
            return Output(progress: progress, issue: .unstable, baseline: nil)
        } else {
            state.stableSince = nil
            state.lastIssue = .unstable
            return Output(progress: 0, issue: state.lastIssue, baseline: nil)
        }
    }

    private func maxNormalizedDelta(candidate: Baseline, measurement: Baseline) -> Double {
        let scale = max(0.0001, candidate.shoulderDistance)
        let deltas: [Double] = [
            distance(candidate.leftShoulder, measurement.leftShoulder) / scale,
            distance(candidate.rightShoulder, measurement.rightShoulder) / scale,
            distance(candidate.leftHip, measurement.leftHip) / scale,
            distance(candidate.rightHip, measurement.rightHip) / scale,
            distance(candidate.leftAnkle, measurement.leftAnkle) / scale,
            distance(candidate.rightAnkle, measurement.rightAnkle) / scale,
        ]
        return deltas.max() ?? 0
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return sqrt(dx * dx + dy * dy)
    }

    private func filter(previous: CGPoint, current: CGPoint, alpha: Double) -> CGPoint {
        let a = min(1, max(0, alpha))
        return CGPoint(
            x: (1 - a) * previous.x + a * current.x,
            y: (1 - a) * previous.y + a * current.y
        )
    }
}


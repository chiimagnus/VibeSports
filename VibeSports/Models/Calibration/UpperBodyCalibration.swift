import CoreGraphics
import Foundation

struct UpperBodyCalibration: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        case generic
        case boxingGuard
    }

    enum Issue: Sendable, Equatable {
        case noPose
        case missingJoints([PoseJointName])
        case subjectTooClose
        case subjectTooFar
        case unstable
        case guardPoseNotMet

        var message: String {
            switch self {
            case .noPose:
                return "No pose detected."
            case .missingJoints:
                return "Keep shoulders, elbows, and wrists in frame."
            case .subjectTooClose:
                return "Too close — move back a bit."
            case .subjectTooFar:
                return "Too far — move closer."
            case .unstable:
                return "Hold still…"
            case .guardPoseNotMet:
                return "Raise both fists near your face (guard)."
            }
        }
    }

    struct Baseline: Sendable, Equatable {
        var leftShoulder: CGPoint
        var rightShoulder: CGPoint
        var leftElbow: CGPoint
        var rightElbow: CGPoint
        var leftWrist: CGPoint
        var rightWrist: CGPoint
        var shoulderDistance: Double
    }

    struct Output: Sendable, Equatable {
        var progress: Double
        var issue: Issue?
        var baseline: Baseline?
    }

    struct Configuration: Sendable, Equatable {
        var mode: Mode = .generic
        var minJointConfidence: Double = 0.25

        var stableDuration: TimeInterval = 0.9
        var stabilityToleranceNormalized: Double = 0.06
        var smoothingAlpha: Double = 0.25

        var minShoulderDistance: Double = 0.16
        var maxShoulderDistance: Double = 0.55

        var guardWristAboveShoulderMinOffset: Double = 0.02
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
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
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
            let leftElbow = point(.leftElbow),
            let rightElbow = point(.rightElbow),
            let leftWrist = point(.leftWrist),
            let rightWrist = point(.rightWrist)
        else {
            state.lastIssue = .missingJoints(missing)
            state.stableSince = nil
            return Output(progress: 0, issue: state.lastIssue, baseline: nil)
        }

        let dx = Double(leftShoulder.x - rightShoulder.x)
        let dy = Double(leftShoulder.y - rightShoulder.y)
        let shoulderDistance = max(0.0001, sqrt(dx * dx + dy * dy))

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

        if configuration.mode == .boxingGuard {
            let shoulderCenterY = (Double(leftShoulder.y) + Double(rightShoulder.y)) * 0.5
            let minOffset = configuration.guardWristAboveShoulderMinOffset
            if Double(leftWrist.y) < shoulderCenterY + minOffset || Double(rightWrist.y) < shoulderCenterY + minOffset {
                state.lastIssue = .guardPoseNotMet
                state.stableSince = nil
                return Output(progress: 0, issue: state.lastIssue, baseline: nil)
            }
        }

        let measurement = Baseline(
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            leftElbow: leftElbow,
            rightElbow: rightElbow,
            leftWrist: leftWrist,
            rightWrist: rightWrist,
            shoulderDistance: shoulderDistance
        )

        if var candidate = state.candidate {
            let alpha = min(1, max(0, configuration.smoothingAlpha))
            candidate.leftShoulder = filter(previous: candidate.leftShoulder, current: measurement.leftShoulder, alpha: alpha)
            candidate.rightShoulder = filter(previous: candidate.rightShoulder, current: measurement.rightShoulder, alpha: alpha)
            candidate.leftElbow = filter(previous: candidate.leftElbow, current: measurement.leftElbow, alpha: alpha)
            candidate.rightElbow = filter(previous: candidate.rightElbow, current: measurement.rightElbow, alpha: alpha)
            candidate.leftWrist = filter(previous: candidate.leftWrist, current: measurement.leftWrist, alpha: alpha)
            candidate.rightWrist = filter(previous: candidate.rightWrist, current: measurement.rightWrist, alpha: alpha)
            candidate.shoulderDistance = (1 - alpha) * candidate.shoulderDistance + alpha * measurement.shoulderDistance
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
            hypot(Double(candidate.leftShoulder.x - measurement.leftShoulder.x), Double(candidate.leftShoulder.y - measurement.leftShoulder.y)) / scale,
            hypot(Double(candidate.rightShoulder.x - measurement.rightShoulder.x), Double(candidate.rightShoulder.y - measurement.rightShoulder.y)) / scale,
            hypot(Double(candidate.leftElbow.x - measurement.leftElbow.x), Double(candidate.leftElbow.y - measurement.leftElbow.y)) / scale,
            hypot(Double(candidate.rightElbow.x - measurement.rightElbow.x), Double(candidate.rightElbow.y - measurement.rightElbow.y)) / scale,
            hypot(Double(candidate.leftWrist.x - measurement.leftWrist.x), Double(candidate.leftWrist.y - measurement.leftWrist.y)) / scale,
            hypot(Double(candidate.rightWrist.x - measurement.rightWrist.x), Double(candidate.rightWrist.y - measurement.rightWrist.y)) / scale,
        ]
        return deltas.max() ?? 0
    }

    private func filter(previous: CGPoint, current: CGPoint, alpha: Double) -> CGPoint {
        let a = min(1, max(0, alpha))
        return CGPoint(
            x: (1 - a) * previous.x + a * current.x,
            y: (1 - a) * previous.y + a * current.y
        )
    }
}

import CoreGraphics
import Foundation

struct RunningMetricsSnapshot: Sendable, Equatable {
    var poseDetected: Bool
    var movementQualityPercent: Int
    var cadenceStepsPerSecond: Double
    var cadenceStepsPerMinute: Double
    var speedMetersPerSecond: Double
    var speedKilometersPerHour: Double
    var steps: Int
    var isCloseUpMode: Bool
    var shoulderDistance: Double?

    var motion: RunnerMotion {
        RunnerMotion(
            speedMetersPerSecond: speedMetersPerSecond,
            cadenceStepsPerSecond: cadenceStepsPerSecond,
            cadenceStepsPerMinute: cadenceStepsPerMinute
        )
    }
}

struct RunningMetrics: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var movementThreshold: Double = 1.0
        var smoothingAlpha: Double = 0.2
        var strideLengthMetersPerStep: Double = 1.0
        var cadenceConfiguration: CadenceModel.Configuration = .init()

        var closeUpShoulderDistanceThreshold: Double = 0.24
        var closeUpUpperBodyConfidenceThreshold: Double = 0.5
        var closeUpMovementThresholdMultiplier: Double = 0.7
    }

    var configuration = Configuration()
    var cadenceModel = CadenceModel()
    var stepDetector = RunningStepDetector()

    private var lastUpdateTime: Date?
    private var lastQuality: Double = 0
    private var previousPositions: [PoseJointName: CGPoint] = [:]

    private(set) var isCloseUpMode = false
    private(set) var shoulderDistance: Double?

    mutating func reset() {
        cadenceModel = CadenceModel()
        cadenceModel.configuration = configuration.cadenceConfiguration
        stepDetector.reset()
        lastUpdateTime = nil
        lastQuality = 0
        previousPositions.removeAll(keepingCapacity: true)
        isCloseUpMode = false
        shoulderDistance = nil
    }

    mutating func ingest(pose: Pose?, now: Date) -> RunningMetricsSnapshot {
        let poseDetected = pose != nil

        let dt: TimeInterval
        if let lastUpdateTime {
            dt = max(0.001, now.timeIntervalSince(lastUpdateTime))
        } else {
            dt = 1.0 / 20.0
        }
        lastUpdateTime = now

        updateCloseUpMode(with: pose)

        let rawQuality = movementQuality(from: pose, deltaTime: dt)
        let smoothedQuality = (1 - configuration.smoothingAlpha) * lastQuality + configuration.smoothingAlpha * rawQuality
        lastQuality = smoothedQuality

        cadenceModel.configuration = configuration.cadenceConfiguration
        if stepDetector.ingest(pose: pose, movementQuality: smoothedQuality, now: now) != nil {
            cadenceModel.ingestStep(now: now)
        }
        cadenceModel.update(now: now)

        let speedMetersPerSecond = cadenceModel.cadenceStepsPerSecond * max(0, configuration.strideLengthMetersPerStep)
        let speedKmh = speedMetersPerSecond * 3.6

        return RunningMetricsSnapshot(
            poseDetected: poseDetected,
            movementQualityPercent: Int((smoothedQuality * 100).rounded()),
            cadenceStepsPerSecond: cadenceModel.cadenceStepsPerSecond,
            cadenceStepsPerMinute: cadenceModel.cadenceStepsPerMinute,
            speedMetersPerSecond: speedMetersPerSecond,
            speedKilometersPerHour: speedKmh,
            steps: stepDetector.stepCount,
            isCloseUpMode: isCloseUpMode,
            shoulderDistance: shoulderDistance
        )
    }

    private mutating func updateCloseUpMode(with pose: Pose?) {
        guard
            let left = pose?.joint(.leftShoulder),
            let right = pose?.joint(.rightShoulder)
        else {
            isCloseUpMode = false
            shoulderDistance = nil
            return
        }

        let dx = left.location.x - right.location.x
        let dy = left.location.y - right.location.y
        let distance = sqrt(dx * dx + dy * dy)
        shoulderDistance = distance

        let upperBodyConfidence = (left.confidence + right.confidence) / 2
        isCloseUpMode = distance >= configuration.closeUpShoulderDistanceThreshold
            && upperBodyConfidence >= configuration.closeUpUpperBodyConfidenceThreshold
    }

    private mutating func movementQuality(from pose: Pose?, deltaTime: TimeInterval) -> Double {
        guard let pose else {
            previousPositions.removeAll(keepingCapacity: true)
            return 0
        }

        let dt = max(0.001, deltaTime)

        let candidateJoints: [PoseJointName] = [
            .leftWrist, .rightWrist,
            .leftKnee, .rightKnee
        ]

        var totalVelocity: Double = 0
        var count: Double = 0

        for jointName in candidateJoints {
            guard let joint = pose.joint(jointName) else { continue }
            let current = joint.location

            if let previous = previousPositions[jointName] {
                let vx = Double((current.x - previous.x) / dt)
                let vy = Double((current.y - previous.y) / dt)
                totalVelocity += abs(vx) + abs(vy)
                count += 1
            }

            previousPositions[jointName] = current
        }

        guard count > 0 else { return 0 }
        var threshold = configuration.movementThreshold

        if isCloseUpMode {
            threshold *= configuration.closeUpMovementThresholdMultiplier
        } else if pose.joint(.leftKnee) == nil && pose.joint(.rightKnee) == nil {
            threshold *= 0.7
        }

        let averageVelocity = totalVelocity / count
        let normalized = min(1, averageVelocity / max(0.0001, threshold))
        return pow(normalized, 1.5)
    }
}

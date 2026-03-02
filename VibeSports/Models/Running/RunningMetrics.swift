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
            cadenceStepsPerMinute: cadenceStepsPerMinute,
            forwardInput: 0,
            turnInput: 0,
            headingYaw: 0
        )
    }
}

struct RunningMetrics: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var strideLengthMetersPerStep: Double = 1.0
        var stepDetectorConfiguration: HeadBobStepDetector.Configuration = .init()
        var cadenceConfiguration: CadenceModel.Configuration = .init()
    }

    var configuration = Configuration()
    var cadenceModel = CadenceModel()
    var stepDetector = HeadBobStepDetector()

    mutating func reset() {
        cadenceModel = CadenceModel()
        cadenceModel.configuration = configuration.cadenceConfiguration
        stepDetector.reset()
        stepDetector.configuration = configuration.stepDetectorConfiguration
    }

    mutating func ingest(observation: RunningHeadObservation?, now: Date) -> RunningMetricsSnapshot {
        stepDetector.configuration = configuration.stepDetectorConfiguration
        cadenceModel.configuration = configuration.cadenceConfiguration
        if let stepEvent = stepDetector.ingest(observation: observation, now: now) {
            cadenceModel.ingestStep(
                now: now,
                intervalSincePreviousStep: stepEvent.intervalSincePreviousStep
            )
        }
        cadenceModel.update(now: now, isTracking: observation?.isDetected == true)

        let speedMetersPerSecond = cadenceModel.cadenceStepsPerSecond * max(0, configuration.strideLengthMetersPerStep)
        let speedKmh = speedMetersPerSecond * 3.6

        return RunningMetricsSnapshot(
            poseDetected: observation?.isDetected == true,
            movementQualityPercent: 0,
            cadenceStepsPerSecond: cadenceModel.cadenceStepsPerSecond,
            cadenceStepsPerMinute: cadenceModel.cadenceStepsPerMinute,
            speedMetersPerSecond: speedMetersPerSecond,
            speedKilometersPerHour: speedKmh,
            steps: stepDetector.stepCount,
            isCloseUpMode: false,
            shoulderDistance: nil
        )
    }
}

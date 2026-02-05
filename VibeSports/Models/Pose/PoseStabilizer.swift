import CoreGraphics
import Foundation

struct PoseStabilizer: Sendable {
    struct Configuration: Sendable, Equatable {
        var onConfidenceThreshold: Double = 0.35
        var offConfidenceThreshold: Double = 0.20
        var holdDuration: TimeInterval = 0.20

        /// 0 = no smoothing, 1 = no inertia.
        var smoothingAlpha: Double = 0.35
    }

    var configuration = Configuration()

    private struct JointState: Sendable {
        var isVisible: Bool = false
        var lastSeenAt: Date?
        var filteredLocation: CGPoint?
    }

    private var jointStates: [PoseJointName: JointState] = {
        var states: [PoseJointName: JointState] = [:]
        states.reserveCapacity(PoseJointName.allCases.count)
        for name in PoseJointName.allCases {
            states[name] = JointState()
        }
        return states
    }()

    mutating func reset() {
        for name in PoseJointName.allCases {
            jointStates[name] = JointState()
        }
    }

    mutating func ingest(pose: Pose?, now: Date) -> Pose? {
        guard let pose else {
            // Keep last-known joints for a short time to reduce flicker when frames drop.
            return makePoseUsingHoldOnly(now: now)
        }

        var outputJoints: [PoseJointName: PoseJoint] = [:]
        outputJoints.reserveCapacity(PoseJointName.allCases.count)

        for name in PoseJointName.allCases {
            let measurement = pose.joint(name)
            var state = jointStates[name] ?? JointState()

            let confidence = measurement?.confidence ?? 0
            let shouldTurnOn = confidence >= configuration.onConfidenceThreshold
            let shouldTurnOff = confidence > 0 && confidence < configuration.offConfidenceThreshold

            if state.isVisible {
                if shouldTurnOff {
                    // Allow hold window before hiding.
                    if let lastSeenAt = state.lastSeenAt, now.timeIntervalSince(lastSeenAt) > configuration.holdDuration {
                        state.isVisible = false
                        state.filteredLocation = nil
                    }
                }
            } else if shouldTurnOn {
                state.isVisible = true
            }

            if let measurement, confidence > 0 {
                state.lastSeenAt = now

                if state.isVisible {
                    state.filteredLocation = filter(
                        previous: state.filteredLocation ?? measurement.location,
                        current: measurement.location,
                        alpha: configuration.smoothingAlpha
                    )
                } else {
                    // Track filtered position even when not visible so that turning on is less jumpy.
                    state.filteredLocation = filter(
                        previous: state.filteredLocation ?? measurement.location,
                        current: measurement.location,
                        alpha: min(1.0, configuration.smoothingAlpha + 0.20)
                    )
                }
            }

            if state.isVisible {
                if
                    let filtered = state.filteredLocation,
                    let lastSeenAt = state.lastSeenAt,
                    now.timeIntervalSince(lastSeenAt) <= configuration.holdDuration
                {
                    // Ensure overlay keeps drawing while visible/held.
                    outputJoints[name] = PoseJoint(location: filtered, confidence: 1.0)
                }
            }

            jointStates[name] = state
        }

        return outputJoints.isEmpty ? nil : Pose(joints: outputJoints)
    }

    private func makePoseUsingHoldOnly(now: Date) -> Pose? {
        var outputJoints: [PoseJointName: PoseJoint] = [:]
        outputJoints.reserveCapacity(PoseJointName.allCases.count)

        for (name, state) in jointStates {
            guard state.isVisible else { continue }
            guard let lastSeenAt = state.lastSeenAt else { continue }
            guard now.timeIntervalSince(lastSeenAt) <= configuration.holdDuration else { continue }
            guard let filtered = state.filteredLocation else { continue }
            outputJoints[name] = PoseJoint(location: filtered, confidence: 1.0)
        }

        return outputJoints.isEmpty ? nil : Pose(joints: outputJoints)
    }

    private func filter(previous: CGPoint, current: CGPoint, alpha: Double) -> CGPoint {
        let a = min(1, max(0, alpha))
        let x = (1 - a) * previous.x + a * current.x
        let y = (1 - a) * previous.y + a * current.y
        return CGPoint(x: x, y: y)
    }
}


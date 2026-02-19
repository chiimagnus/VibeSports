import CoreGraphics
import Foundation

struct BoxingPunchDetector: Sendable, Equatable {
    var configuration = BoxingConfiguration()

    private enum Hand: Sendable, Equatable {
        case left
        case right
    }

    private struct HandState: Sendable, Equatable {
        var lastSampleAt: Date?
        var previousDelta: CGPoint?

        var isArmed = true
        var lastPunchAt: Date?

        var peakNormalizedDx: Double = 0
        var peakNormalizedDy: Double = 0
        var peakNormalizedDistance: Double = 0
        var peakSpeed: Double = 0
        var peakKind: BoxingPunchKind?
        var peakAt: Date?
    }

    private var left = HandState()
    private var right = HandState()
    private var pendingEvents: [BoxingPunchEvent] = []

    mutating func reset() {
        left = HandState()
        right = HandState()
        pendingEvents.removeAll(keepingCapacity: true)
    }

    mutating func ingest(pose: Pose?, baseline: BoxingCalibrationBaseline, now: Date) -> BoxingPunchEvent? {
        if !pendingEvents.isEmpty {
            return pendingEvents.removeFirst()
        }

        let leftEvent = ingestHand(.left, pose: pose, baseline: baseline, now: now)
        let rightEvent = ingestHand(.right, pose: pose, baseline: baseline, now: now)

        if let leftEvent { pendingEvents.append(leftEvent) }
        if let rightEvent { pendingEvents.append(rightEvent) }

        return pendingEvents.isEmpty ? nil : pendingEvents.removeFirst()
    }

    private mutating func ingestHand(
        _ hand: Hand,
        pose: Pose?,
        baseline: BoxingCalibrationBaseline,
        now: Date
    ) -> BoxingPunchEvent? {
        let jointName: PoseJointName
        let neutralWrist: CGPoint
        switch hand {
        case .left:
            jointName = .leftWrist
            neutralWrist = baseline.leftNeutralWrist
        case .right:
            jointName = .rightWrist
            neutralWrist = baseline.rightNeutralWrist
        }

        let wrist = pose?.joint(jointName)
        let confidence = wrist?.confidence ?? 0
        guard confidence >= configuration.minJointConfidence else {
            updateState(hand: hand) { state in
                state.previousDelta = nil
                state.lastSampleAt = now
            }
            return nil
        }

        let shoulderDistance = max(0.0001, baseline.shoulderDistance)
        let delta = CGPoint(
            x: wrist!.location.x - neutralWrist.x,
            y: wrist!.location.y - neutralWrist.y
        )
        let normalizedDx = Double(delta.x) / shoulderDistance
        let normalizedDy = Double(delta.y) / shoulderDistance
        let normalizedDistance = hypot(normalizedDx, normalizedDy)

        let (normalizedSpeed, dt) = updateSpeedEstimate(hand: hand, delta: delta, now: now, shoulderDistance: shoulderDistance)

        // If we are in the "re-armed" state, look for a new punch start (distance threshold).
        var shouldArm = false
        var shouldDisarm = false

        let isArmed = state(hand).isArmed
        if isArmed {
            shouldDisarm = normalizedDistance >= configuration.minNormalizedDistanceToArm
        } else {
            shouldArm = normalizedDistance <= configuration.returnNormalizedDistance
        }

        if shouldDisarm {
            let classified = classify(hand: hand, normalizedDx: normalizedDx, normalizedDy: normalizedDy)
            updateState(hand: hand) { state in
                state.isArmed = false
                state.peakNormalizedDx = normalizedDx
                state.peakNormalizedDy = normalizedDy
                state.peakNormalizedDistance = normalizedDistance
                state.peakSpeed = normalizedSpeed
                state.peakKind = classified
                state.peakAt = now
            }
            return nil
        }

        if !isArmed {
            // While disarmed (mid-punch), track peak displacement/speed for classification.
            let classified = classify(hand: hand, normalizedDx: normalizedDx, normalizedDy: normalizedDy)
            updateState(hand: hand) { state in
                if normalizedDistance >= state.peakNormalizedDistance {
                    state.peakNormalizedDx = normalizedDx
                    state.peakNormalizedDy = normalizedDy
                    state.peakNormalizedDistance = normalizedDistance
                    state.peakSpeed = max(state.peakSpeed, normalizedSpeed)
                    state.peakKind = classified
                    state.peakAt = now
                } else {
                    state.peakSpeed = max(state.peakSpeed, normalizedSpeed)
                }
            }
        }

        if shouldArm {
            // Punch ended. Emit event at peak.
            let emitted = emitIfAllowed(hand: hand, now: now)
            updateState(hand: hand) { state in
                state.isArmed = true
            }
            return emitted
        }

        // If dt is very large, re-arm to avoid getting stuck.
        if dt >= 0.8 {
            let emitted = emitIfAllowed(hand: hand, now: now)
            updateState(hand: hand) { state in
                state.isArmed = true
                state.previousDelta = delta
                state.lastSampleAt = now
            }
            return emitted
        }

        return nil
    }

    private func classify(hand: Hand, normalizedDx: Double, normalizedDy: Double) -> BoxingPunchKind {
        let absDx = abs(normalizedDx)
        let absDy = abs(normalizedDy)

        if normalizedDy >= configuration.uppercutNormalizedDyThreshold {
            return hand == .left ? .leftUppercut : .rightUppercut
        }

        if -normalizedDy >= configuration.overhandNormalizedDyThreshold {
            return hand == .left ? .leftOverhand : .rightOverhand
        }

        if absDx >= configuration.hookNormalizedDxThreshold && absDx >= absDy {
            return hand == .left ? .leftHook : .rightHook
        }

        return hand == .left ? .leftStraight : .rightStraight
    }

    private mutating func updateSpeedEstimate(
        hand: Hand,
        delta: CGPoint,
        now: Date,
        shoulderDistance: Double
    ) -> (normalizedSpeed: Double, dt: TimeInterval) {
        let previousSampleAt = state(hand).lastSampleAt
        let dt = previousSampleAt.map { max(0.0001, now.timeIntervalSince($0)) } ?? (1.0 / 20.0)

        let speed: Double
        if let previousDelta = state(hand).previousDelta {
            let vx = Double(delta.x - previousDelta.x) / dt
            let vy = Double(delta.y - previousDelta.y) / dt
            let v = hypot(vx, vy)
            speed = v / max(0.0001, shoulderDistance)
        } else {
            speed = 0
        }

        updateState(hand: hand) { state in
            state.previousDelta = delta
            state.lastSampleAt = now
        }

        return (speed, dt)
    }

    private mutating func emitIfAllowed(hand: Hand, now: Date) -> BoxingPunchEvent? {
        let state = state(hand)
        guard let kind = state.peakKind else { return nil }
        let peakAt = state.peakAt ?? now

        let isAllowed: Bool
        if let lastPunchAt = state.lastPunchAt {
            isAllowed = peakAt.timeIntervalSince(lastPunchAt) >= configuration.minPunchInterval
        } else {
            isAllowed = true
        }

        let event: BoxingPunchEvent? = isAllowed
            ? BoxingPunchEvent(
                kind: kind,
                timestamp: peakAt,
                debug: .init(
                    normalizedDx: state.peakNormalizedDx,
                    normalizedDy: state.peakNormalizedDy,
                    normalizedSpeed: state.peakSpeed,
                    classifiedAs: kind
                )
            )
            : nil

        updateState(hand: hand) { state in
            if isAllowed {
                state.lastPunchAt = peakAt
            }
            state.peakKind = nil
            state.peakAt = nil
            state.peakSpeed = 0
            state.peakNormalizedDx = 0
            state.peakNormalizedDy = 0
            state.peakNormalizedDistance = 0
        }

        return event
    }

    private func state(_ hand: Hand) -> HandState {
        switch hand {
        case .left:
            return left
        case .right:
            return right
        }
    }

    private mutating func updateState(hand: Hand, _ mutate: (inout HandState) -> Void) {
        switch hand {
        case .left:
            mutate(&left)
        case .right:
            mutate(&right)
        }
    }
}

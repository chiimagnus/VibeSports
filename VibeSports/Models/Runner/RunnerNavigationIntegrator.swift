import Foundation

struct RunnerNavigationIntegrator: Sendable, Equatable {
    struct Configuration: Sendable, Equatable {
        var maxForwardSpeedMetersPerSecond: Double = 6.0
        var maxBackwardSpeedMetersPerSecond: Double = 3.0
        var maxYawSpeedRadiansPerSecond: Double = .pi
        var minimumDeltaTime: TimeInterval = 1.0 / 240.0
        var maximumDeltaTime: TimeInterval = 0.2
        var normalizeHeading: Bool = true
    }

    var configuration = Configuration()

    mutating func step(
        state: inout RunnerNavigationState,
        controlInput: RunnerControlInput,
        deltaTime: TimeInterval
    ) {
        let dt = sanitizeDeltaTime(deltaTime)
        guard dt > 0 else { return }

        let control = controlInput.clamped()
        let maxYawSpeed = max(0, configuration.maxYawSpeedRadiansPerSecond)
        let yawRate = control.turnInput * maxYawSpeed
        state.headingYaw += yawRate * dt

        if configuration.normalizeHeading {
            state.headingYaw = normalizeAngle(state.headingYaw)
        }

        let maxForward = max(0, configuration.maxForwardSpeedMetersPerSecond)
        let maxBackward = max(0, configuration.maxBackwardSpeedMetersPerSecond)
        let speed = control.forwardInput >= 0
            ? control.forwardInput * maxForward
            : control.forwardInput * maxBackward

        let dx = sin(state.headingYaw) * speed * dt
        let dz = cos(state.headingYaw) * speed * dt
        state.positionX += dx
        state.positionZ += dz
    }

    private func sanitizeDeltaTime(_ dt: TimeInterval) -> TimeInterval {
        guard dt.isFinite else { return 0 }
        let minDt = max(0, configuration.minimumDeltaTime)
        let maxDt = max(minDt, configuration.maximumDeltaTime)
        return min(maxDt, max(minDt, dt))
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        let twoPi = 2 * Double.pi
        var normalized = angle.truncatingRemainder(dividingBy: twoPi)
        if normalized > Double.pi {
            normalized -= twoPi
        } else if normalized < -Double.pi {
            normalized += twoPi
        }
        return normalized
    }
}

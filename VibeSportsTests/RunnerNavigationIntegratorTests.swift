import XCTest
@testable import VibeSports

final class RunnerNavigationIntegratorTests: XCTestCase {
    func test_turnInputPositiveIncreasesHeadingYaw() {
        var integrator = RunnerNavigationIntegrator(
            configuration: .init(
                maxForwardSpeedMetersPerSecond: 6,
                maxBackwardSpeedMetersPerSecond: 3,
                maxYawSpeedRadiansPerSecond: 2.0,
                minimumDeltaTime: 0.001,
                maximumDeltaTime: 0.5,
                normalizeHeading: false
            )
        )
        var state = RunnerNavigationState.zero

        integrator.step(
            state: &state,
            controlInput: RunnerControlInput(turnInput: 0.5, forwardInput: 0),
            deltaTime: 0.2
        )

        XCTAssertGreaterThan(state.headingYaw, 0)
    }

    func test_zeroTurnInputKeepsCurrentHeading() {
        var integrator = RunnerNavigationIntegrator()
        var state = RunnerNavigationState(positionX: 0, positionZ: 0, headingYaw: 1.25)

        integrator.step(
            state: &state,
            controlInput: RunnerControlInput(turnInput: 0, forwardInput: 0.8),
            deltaTime: 0.1
        )

        XCTAssertEqual(state.headingYaw, 1.25, accuracy: 0.0001)
    }

    func test_forwardMovementUsesHeadingDirection() {
        var integrator = RunnerNavigationIntegrator(
            configuration: .init(
                maxForwardSpeedMetersPerSecond: 4,
                maxBackwardSpeedMetersPerSecond: 2,
                maxYawSpeedRadiansPerSecond: 2,
                minimumDeltaTime: 0.001,
                maximumDeltaTime: 1.0,
                normalizeHeading: false
            )
        )
        var state = RunnerNavigationState(positionX: 0, positionZ: 0, headingYaw: .pi / 2)

        integrator.step(
            state: &state,
            controlInput: RunnerControlInput(turnInput: 0, forwardInput: 1),
            deltaTime: 0.5
        )

        XCTAssertGreaterThan(state.positionX, 0.1)
        XCTAssertEqual(state.positionZ, 0, accuracy: 0.001)
    }

    func test_clampsYawRateAndForwardSpeed() {
        var integrator = RunnerNavigationIntegrator(
            configuration: .init(
                maxForwardSpeedMetersPerSecond: 2.0,
                maxBackwardSpeedMetersPerSecond: 1.0,
                maxYawSpeedRadiansPerSecond: 1.0,
                minimumDeltaTime: 0.001,
                maximumDeltaTime: 0.1,
                normalizeHeading: false
            )
        )

        var yawState = RunnerNavigationState.zero
        integrator.step(
            state: &yawState,
            controlInput: RunnerControlInput(turnInput: 9, forwardInput: 0),
            deltaTime: 1.0
        )
        XCTAssertEqual(yawState.headingYaw, 0.1, accuracy: 0.0001)

        var speedState = RunnerNavigationState.zero
        integrator.step(
            state: &speedState,
            controlInput: RunnerControlInput(turnInput: 0, forwardInput: 9),
            deltaTime: 1.0
        )
        XCTAssertEqual(speedState.positionZ, 0.2, accuracy: 0.0001)
    }
}

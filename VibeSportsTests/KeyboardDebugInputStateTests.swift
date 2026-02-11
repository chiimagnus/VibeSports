import XCTest
@testable import VibeSports

final class KeyboardDebugInputStateTests: XCTestCase {
    private let slowForward = KeyboardDebugInputState.Defaults.slowForwardInput

    func test_adKeysMapToTurnInput() {
        var state = KeyboardDebugInputState()

        state.keyDown(.a)
        XCTAssertEqual(state.turnInput, 1)

        state.keyUp(.a)
        state.keyDown(.d)
        XCTAssertEqual(state.turnInput, -1)
    }

    func test_oppositeTurnKeysCancelOut() {
        var state = KeyboardDebugInputState()

        state.keyDown(.a)
        state.keyDown(.d)

        XCTAssertEqual(state.turnInput, 0)
    }

    func test_wsKeysMapToForwardInput() {
        var state = KeyboardDebugInputState()

        state.keyDown(.w)
        XCTAssertEqual(state.forwardInput, slowForward, accuracy: 0.0001)

        state.keyUp(.w)
        state.keyDown(.s)
        XCTAssertEqual(state.forwardInput, -1)
    }

    func test_shiftBoostsForwardInputToFullSpeed() {
        var state = KeyboardDebugInputState()

        state.setBoostPressed(true)
        state.keyDown(.w)
        XCTAssertEqual(state.forwardInput, 1, accuracy: 0.0001)
    }

    func test_shiftToggleUpdatesSpeedWhileHoldingW() {
        var state = KeyboardDebugInputState()

        state.keyDown(.w)
        XCTAssertEqual(state.forwardInput, slowForward, accuracy: 0.0001)

        state.setBoostPressed(true)
        XCTAssertEqual(state.forwardInput, 1, accuracy: 0.0001)

        state.setBoostPressed(false)
        XCTAssertEqual(state.forwardInput, slowForward, accuracy: 0.0001)
    }

    func test_oppositeForwardKeysCancelOut() {
        var state = KeyboardDebugInputState()

        state.keyDown(.w)
        state.keyDown(.s)

        XCTAssertEqual(state.forwardInput, 0)
    }

    func test_keyUpResetsInput() {
        var state = KeyboardDebugInputState()

        state.keyDown(.a)
        state.keyDown(.w)
        XCTAssertEqual(state.controlInput, RunnerControlInput(turnInput: 1, forwardInput: slowForward))

        state.keyUp(.a)
        state.keyUp(.w)
        XCTAssertEqual(state.controlInput, .zero)
    }
}

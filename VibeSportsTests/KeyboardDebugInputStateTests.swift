import XCTest
@testable import VibeSports

final class KeyboardDebugInputStateTests: XCTestCase {
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
        XCTAssertEqual(state.forwardInput, 1)

        state.keyUp(.w)
        state.keyDown(.s)
        XCTAssertEqual(state.forwardInput, -1)
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
        XCTAssertEqual(state.controlInput, RunnerControlInput(turnInput: 1, forwardInput: 1))

        state.keyUp(.a)
        state.keyUp(.w)
        XCTAssertEqual(state.controlInput, .zero)
    }
}

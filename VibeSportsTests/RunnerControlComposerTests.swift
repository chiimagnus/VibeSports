import XCTest
@testable import VibeSports

final class RunnerControlComposerTests: XCTestCase {
    func test_cameraModeUsesCameraInputOnly() {
        let composer = RunnerControlComposer(mode: .camera)
        let output = composer.compose(
            cameraInput: RunnerControlInput(turnInput: 0.5, forwardInput: 0.2),
            keyboardInput: RunnerControlInput(turnInput: -1, forwardInput: 1)
        )

        XCTAssertEqual(output, RunnerControlInput(turnInput: 0.5, forwardInput: 0.2))
    }

    func test_keyboardModeUsesKeyboardInputOnly() {
        let composer = RunnerControlComposer(mode: .keyboard)
        let output = composer.compose(
            cameraInput: RunnerControlInput(turnInput: 0.7, forwardInput: 0.8),
            keyboardInput: RunnerControlInput(turnInput: -1, forwardInput: -1)
        )

        XCTAssertEqual(output, RunnerControlInput(turnInput: -1, forwardInput: -1))
    }

    func test_keyboardModeWorksWhenCameraInputMissing() {
        let composer = RunnerControlComposer(mode: .keyboard)
        let output = composer.compose(
            cameraInput: nil,
            keyboardInput: RunnerControlInput(turnInput: 0.3, forwardInput: 1)
        )

        XCTAssertEqual(output, RunnerControlInput(turnInput: 0.3, forwardInput: 1))
    }

    func test_mixedModePrefersKeyboardWhenKeyboardHasInput() {
        let composer = RunnerControlComposer(mode: .mixed)
        let output = composer.compose(
            cameraInput: RunnerControlInput(turnInput: 0.4, forwardInput: 0),
            keyboardInput: RunnerControlInput(turnInput: -1, forwardInput: 0.5)
        )

        XCTAssertEqual(output, RunnerControlInput(turnInput: -1, forwardInput: 0.5))
    }

    func test_mixedModeFallsBackToCameraWhenKeyboardIsNeutral() {
        let composer = RunnerControlComposer(mode: .mixed)
        let output = composer.compose(
            cameraInput: RunnerControlInput(turnInput: 0.4, forwardInput: 0.3),
            keyboardInput: .zero
        )

        XCTAssertEqual(output, RunnerControlInput(turnInput: 0.4, forwardInput: 0.3))
    }

    func test_inputIsClampedToUnitRange() {
        let composer = RunnerControlComposer(mode: .keyboard)
        let output = composer.compose(
            cameraInput: nil,
            keyboardInput: RunnerControlInput(turnInput: 3, forwardInput: -5)
        )

        XCTAssertEqual(output, RunnerControlInput(turnInput: 1, forwardInput: -1))
    }

    func test_missingInputsFallbackToZero() {
        let composer = RunnerControlComposer(mode: .camera)
        XCTAssertEqual(composer.compose(cameraInput: nil, keyboardInput: nil), .zero)
    }
}

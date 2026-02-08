struct RunnerControlComposer: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        case camera
        case keyboard
        case mixed
    }

    var mode: Mode = .camera

    func compose(
        cameraInput: RunnerControlInput?,
        keyboardInput: RunnerControlInput?
    ) -> RunnerControlInput {
        let camera = (cameraInput ?? .zero).clamped()
        let keyboard = (keyboardInput ?? .zero).clamped()

        switch mode {
        case .camera:
            return camera
        case .keyboard:
            return keyboard
        case .mixed:
            return keyboard.hasInput ? keyboard : camera
        }
    }
}

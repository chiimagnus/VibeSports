struct RunnerControlComposer: Sendable, Equatable {
    enum Mode: Sendable, Equatable, Hashable, CaseIterable {
        case camera
        case keyboard
        case mixed

        var debugTitle: String {
            switch self {
            case .camera:
                return "Camera"
            case .keyboard:
                return "Keyboard"
            case .mixed:
                return "Mixed"
            }
        }
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

import SwiftUI

private struct ShowPoseOverlayFocusedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct MirrorCameraFocusedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct PoseStabilizationFocusedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct ShowWorldAxesFocusedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct ShowRunnerAxesFocusedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct ControlModeFocusedKey: FocusedValueKey {
    typealias Value = Binding<RunnerControlComposer.Mode>
}

extension FocusedValues {
    var showPoseOverlay: Binding<Bool>? {
        get { self[ShowPoseOverlayFocusedKey.self] }
        set { self[ShowPoseOverlayFocusedKey.self] = newValue }
    }

    var mirrorCamera: Binding<Bool>? {
        get { self[MirrorCameraFocusedKey.self] }
        set { self[MirrorCameraFocusedKey.self] = newValue }
    }

    var poseStabilizationEnabled: Binding<Bool>? {
        get { self[PoseStabilizationFocusedKey.self] }
        set { self[PoseStabilizationFocusedKey.self] = newValue }
    }

    var showWorldAxes: Binding<Bool>? {
        get { self[ShowWorldAxesFocusedKey.self] }
        set { self[ShowWorldAxesFocusedKey.self] = newValue }
    }

    var showRunnerAxes: Binding<Bool>? {
        get { self[ShowRunnerAxesFocusedKey.self] }
        set { self[ShowRunnerAxesFocusedKey.self] = newValue }
    }

    var controlMode: Binding<RunnerControlComposer.Mode>? {
        get { self[ControlModeFocusedKey.self] }
        set { self[ControlModeFocusedKey.self] = newValue }
    }
}

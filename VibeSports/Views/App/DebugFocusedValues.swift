import SwiftUI

private struct ShowPoseOverlayFocusedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct MirrorCameraFocusedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
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
}


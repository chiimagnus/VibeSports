import SwiftUI

struct DebugCommands: Commands {
    @FocusedValue(\.showPoseOverlay) private var showPoseOverlay
    @FocusedValue(\.mirrorCamera) private var mirrorCamera
    @FocusedValue(\.poseStabilizationEnabled) private var poseStabilizationEnabled

#if DEBUG
    @Environment(\.openWindow) private var openWindow
#endif

    var body: some Commands {
        CommandMenu("Debug") {
            if let showPoseOverlay {
                Toggle("Pose Overlay", isOn: showPoseOverlay)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            } else {
                Button("Pose Overlay") {}
                    .disabled(true)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            if let mirrorCamera {
                Toggle("Mirror Camera", isOn: mirrorCamera)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            } else {
                Button("Mirror Camera") {}
                    .disabled(true)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }

            Divider()

            if let poseStabilizationEnabled {
                Toggle("Pose Stabilization", isOn: poseStabilizationEnabled)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            } else {
                Button("Pose Stabilization") {}
                    .disabled(true)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }

#if DEBUG
            Divider()

            Button("Runner Animations…") {
                openWindow(id: "runner-animations")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
#endif
        }
    }
}

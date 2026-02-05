import SwiftUI

struct DebugCommands: Commands {
    @FocusedValue(\.showPoseOverlay) private var showPoseOverlay
    @FocusedValue(\.mirrorCamera) private var mirrorCamera
    @FocusedValue(\.poseStabilizationEnabled) private var poseStabilizationEnabled

    var body: some Commands {
        CommandMenu("Debug") {
            if let showPoseOverlay {
                Toggle("骨骼叠加", isOn: showPoseOverlay)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            } else {
                Button("骨骼叠加") {}
                    .disabled(true)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            if let mirrorCamera {
                Toggle("水平镜像", isOn: mirrorCamera)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            } else {
                Button("水平镜像") {}
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
        }
    }
}

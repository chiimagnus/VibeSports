import SwiftUI

struct DebugCommands: Commands {
    @FocusedValue(\.showPoseOverlay) private var showPoseOverlay
    @FocusedValue(\.mirrorCamera) private var mirrorCamera
    @FocusedValue(\.poseStabilizationEnabled) private var poseStabilizationEnabled
    @FocusedValue(\.showWorldAxes) private var showWorldAxes
    @FocusedValue(\.showRunnerAxes) private var showRunnerAxes
    @FocusedValue(\.controlMode) private var controlMode

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

            if let showWorldAxes {
                Toggle("World Axes", isOn: showWorldAxes)
            } else {
                Button("World Axes") {}
                    .disabled(true)
            }

            if let showRunnerAxes {
                Toggle("Runner Axes", isOn: showRunnerAxes)
            } else {
                Button("Runner Axes") {}
                    .disabled(true)
            }

            if let controlMode {
                Menu("Control Input") {
                    Button {
                        controlMode.wrappedValue = .camera
                    } label: {
                        Text(controlMode.wrappedValue == .camera ? "✓ Camera" : "Camera")
                    }

                    Button {
                        controlMode.wrappedValue = .keyboard
                    } label: {
                        Text(controlMode.wrappedValue == .keyboard ? "✓ Keyboard" : "Keyboard")
                    }

                    Button {
                        controlMode.wrappedValue = .mixed
                    } label: {
                        Text(controlMode.wrappedValue == .mixed ? "✓ Mixed" : "Mixed")
                    }
                }
            } else {
                Button("Control Input") {}
                    .disabled(true)
            }
            Divider()

            Button("Runner Animations…") {
                openWindow(id: "runner-animations")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Runner Tuning…") {
                openWindow(id: "runner-tuning")
            }
#endif
        }
    }
}

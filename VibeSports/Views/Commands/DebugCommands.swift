import SwiftUI

struct DebugCommands: Commands {
    @ObservedObject var runnerCommands: RunnerCommandCenter

#if DEBUG
    @Environment(\.openWindow) private var openWindow
#endif

    private var poseOverlayBinding: Binding<Bool> {
        Binding(
            get: { runnerCommands.showPoseOverlay },
            set: { runnerCommands.setShowPoseOverlay($0) }
        )
    }

    private var mirrorCameraBinding: Binding<Bool> {
        Binding(
            get: { runnerCommands.mirrorCamera },
            set: { runnerCommands.setMirrorCamera($0) }
        )
    }

    private var poseStabilizationBinding: Binding<Bool> {
        Binding(
            get: { runnerCommands.poseStabilizationEnabled },
            set: { runnerCommands.setPoseStabilizationEnabled($0) }
        )
    }

    private var showWorldAxesBinding: Binding<Bool> {
        Binding(
            get: { runnerCommands.showWorldAxes },
            set: { runnerCommands.setShowWorldAxes($0) }
        )
    }

    private var showRunnerAxesBinding: Binding<Bool> {
        Binding(
            get: { runnerCommands.showRunnerAxes },
            set: { runnerCommands.setShowRunnerAxes($0) }
        )
    }

    private var controlModeValue: RunnerControlComposer.Mode {
        runnerCommands.controlMode
    }

    var body: some Commands {
        CommandMenu("Debug") {
            Toggle("Pose Overlay", isOn: poseOverlayBinding)
                .disabled(!runnerCommands.isRunnerAttached)
                .keyboardShortcut("p", modifiers: [.command, .shift])

            Toggle("Mirror Camera", isOn: mirrorCameraBinding)
                .disabled(!runnerCommands.isRunnerAttached)
                .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()

            Toggle("Pose Stabilization", isOn: poseStabilizationBinding)
                .disabled(!runnerCommands.isRunnerAttached)
                .keyboardShortcut("s", modifiers: [.command, .shift])

#if DEBUG
            Divider()

            Toggle("World Axes", isOn: showWorldAxesBinding)
                .disabled(!runnerCommands.isRunnerAttached)

            Toggle("Runner Axes", isOn: showRunnerAxesBinding)
                .disabled(!runnerCommands.isRunnerAttached)

            Menu("Control Input") {
                Button {
                    runnerCommands.setControlMode(.camera)
                } label: {
                    Text(controlModeValue == .camera ? "✓ Camera" : "Camera")
                }

                Button {
                    runnerCommands.setControlMode(.keyboard)
                } label: {
                    Text(controlModeValue == .keyboard ? "✓ Keyboard" : "Keyboard")
                }

                Button {
                    runnerCommands.setControlMode(.mixed)
                } label: {
                    Text(controlModeValue == .mixed ? "✓ Mixed" : "Mixed")
                }
            }
            .disabled(!runnerCommands.isRunnerAttached)
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

import SwiftUI

struct RunnerSettingsView: View {
    @EnvironmentObject private var runnerCommands: RunnerCommandCenter

    var body: some View {
        TabView {
            cameraPoseSettings
                .tabItem {
                    Label("Camera & Pose", systemImage: "camera.aperture")
                }

            sceneControlSettings
                .tabItem {
                    Label("Scene & Control", systemImage: "gamecontroller")
                }

            RunnerAnimationDebugView()
                .tabItem {
                    Label("Runner Animations", systemImage: "figure.run")
                }

            RunnerTuningDebugView()
                .tabItem {
                    Label("Runner Tuning", systemImage: "slider.horizontal.3")
                }
        }
    }

    private var cameraPoseSettings: some View {
        Form {
            Section("Status") {
                statusText
            }

            Section("Camera Overlay") {
                Toggle("Pose Overlay", isOn: poseOverlayBinding)
                    .disabled(!runnerCommands.isRunnerAttached)

                Toggle("Mirror Camera", isOn: mirrorCameraBinding)
                    .disabled(!runnerCommands.isRunnerAttached)
            }

            Section("Pose Processing") {
                Toggle("Pose Stabilization", isOn: poseStabilizationBinding)
                    .disabled(!runnerCommands.isRunnerAttached)
            }
        }
         .formStyle(.grouped)
    }

    private var sceneControlSettings: some View {
        Form {
            Section("Status") {
                statusText
            }

            Section("Scene Debug") {
                Toggle("World Axes", isOn: worldAxesBinding)
                    .disabled(!runnerCommands.isRunnerAttached)

                Toggle("Runner Axes", isOn: runnerAxesBinding)
                    .disabled(!runnerCommands.isRunnerAttached)
            }

            Section("Control Input") {
                Picker("Control Mode", selection: controlModeBinding) {
                    ForEach(RunnerControlComposer.Mode.allCases, id: \.self) { mode in
                        Text(mode.debugTitle)
                            .tag(mode)
                    }
                }
                .disabled(!runnerCommands.isRunnerAttached)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusText: some View {
        if runnerCommands.isRunnerAttached {
            Text("Attached to active runner session.")
                .foregroundStyle(.secondary)
        } else {
            Text("Not attached. Open the main game window to enable controls.")
                .foregroundStyle(.secondary)
        }
    }

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

    private var worldAxesBinding: Binding<Bool> {
        Binding(
            get: { runnerCommands.showWorldAxes },
            set: { runnerCommands.setShowWorldAxes($0) }
        )
    }

    private var runnerAxesBinding: Binding<Bool> {
        Binding(
            get: { runnerCommands.showRunnerAxes },
            set: { runnerCommands.setShowRunnerAxes($0) }
        )
    }

    private var controlModeBinding: Binding<RunnerControlComposer.Mode> {
        Binding(
            get: { runnerCommands.controlMode },
            set: { runnerCommands.setControlMode($0) }
        )
    }
}

#Preview {
    RunnerSettingsView()
        .environmentObject(DebugToolsStore())
        .environmentObject(RunnerCommandCenter())
}

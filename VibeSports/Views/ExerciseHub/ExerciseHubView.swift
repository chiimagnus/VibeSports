import SwiftUI

struct ExerciseHubView: View {
    let dependencies: AppDependencies

    @StateObject private var viewModel: ExerciseHubViewModel
    @EnvironmentObject private var debugTools: DebugToolsStore
    @EnvironmentObject private var runnerCommands: RunnerCommandCenter

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: ExerciseHubViewModel(dependencies: dependencies))
    }

    var body: some View {
        ZStack {
            RunnerSceneView(renderer: viewModel.sceneRenderer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            KeyboardInputCaptureView(
                onKeyDown: { key in
                    viewModel.handleKeyDown(key)
                },
                onKeyUp: { key in
                    viewModel.handleKeyUp(key)
                },
                onBoostModifierChanged: { isPressed in
                    viewModel.handleBoostModifierChanged(isPressed)
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)

            VStack {
                headerBar
                Spacer(minLength: 0)
            }
            .padding(16)

            if viewModel.sessionState.isIdle {
                idleOverlay
            } else if viewModel.sessionState.kind == .boxing {
                boxingPlaceholderOverlay
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            debugTools.attach(sceneRenderer: viewModel.sceneRenderer)
            runnerCommands.attach(
                snapshot: runnerCommandSnapshot,
                handlers: makeRunnerCommandHandlers()
            )
            viewModel.updateStrideLengthMetersPerStep(debugTools.runnerTuning.cadence.strideLengthMetersPerStep)
            viewModel.updateShowWorldAxes(viewModel.showWorldAxes)
            viewModel.updateShowRunnerAxes(viewModel.showRunnerAxes)
        }
        .onChange(of: debugTools.runnerTuning.cadence) { _, cadence in
            viewModel.updateStrideLengthMetersPerStep(
                cadence.strideLengthMetersPerStep
            )
        }
        .onChange(of: runnerCommandSnapshot) { _, snapshot in
            runnerCommands.apply(snapshot: snapshot)
        }
        .onDisappear {
            debugTools.detach(sceneRenderer: viewModel.sceneRenderer)
            runnerCommands.detach()
            viewModel.resetKeyboardInput()
            viewModel.stopIfNeeded()
        }
    }

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VibeSports")
                    .font(.headline)
                statusText
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Text("Control: \(viewModel.controlMode.debugTitle)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Spacer()

            if !viewModel.sessionState.isIdle {
                Button("End") {
                    viewModel.stopTapped()
                }
                .buttonStyle(.bordered)
            }

            cameraPreview
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch viewModel.cameraSession.state {
        case .idle:
            Text("Not started")
        case .requestingAuthorization:
            Text("Requesting camera permission…")
        case .unauthorized:
            Text("Camera access denied (System Settings → Privacy & Security → Camera)")
        case .failed(let message):
            Text("Camera failed to start: \(message)")
        case .running:
            switch viewModel.sessionState {
            case .idle:
                Text("Camera on")
            case .calibrating(let kind):
                Text("\(kind.title) • Calibrating…")
            case .running(let kind):
                if kind == .running {
                    Text("Running • \(String(format: "%.1f", viewModel.metrics.speedKilometersPerHour)) km/h")
                } else {
                    Text("\(kind.title) • Running")
                }
            }
        }
    }

    @ViewBuilder
    private var cameraPreview: some View {
        switch viewModel.cameraSession.state {
        case .running:
            CameraPreviewView(
                session: viewModel.cameraSession.captureSession,
                isMirroredHorizontally: viewModel.mirrorCamera
            )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12))
                }
                .overlay {
                    if viewModel.showPoseOverlay {
                        ZStack(alignment: .topLeading) {
                            let pose = viewModel.poseStabilizationEnabled ? viewModel.stabilizedPose : viewModel.latestPose
                            if let pose {
                                PoseOverlayView(pose: pose, isMirroredHorizontally: viewModel.mirrorCamera)
                            }

                            if viewModel.showPoseArmDebugOverlay {
                                PoseArmDebugOverlay(
                                    rawPose: viewModel.latestPose,
                                    stabilizedPose: viewModel.poseStabilizationEnabled ? viewModel.stabilizedPose : nil,
                                    isStabilizationEnabled: viewModel.poseStabilizationEnabled
                                )
                                .padding(8)
                            }
                        }
                    }
                }
                .frame(width: 260, height: 180)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
        default:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
                .frame(width: 260, height: 180)
        }
    }

    private var idleOverlay: some View {
        VStack(spacing: 12) {
            Text("Ready")
                .font(.title2.bold())
            Text(idleSubtitle)
                .foregroundStyle(.secondary)

            Picker("Exercise", selection: selectedExerciseBinding) {
                ForEach(ExerciseKind.allCases, id: \.self) { kind in
                    Text(kind.title)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Button("Start") {
                viewModel.startTapped()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.1))
                }
        }
            .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
    }

    private var selectedExerciseBinding: Binding<ExerciseKind> {
        Binding(
            get: { viewModel.selectedExerciseKind },
            set: { viewModel.updateSelectedExerciseKind($0) }
        )
    }

    private var idleSubtitle: String {
        switch viewModel.selectedExerciseKind {
        case .running:
            return "Press Start to use camera pose detection to drive the 3D scene."
        case .boxing:
            return "Press Start to begin Boxing (calibration + debug UI will be added in P1)."
        }
    }

    private var boxingPlaceholderOverlay: some View {
        VStack(spacing: 10) {
            Text("Boxing (WIP)")
                .font(.title3.bold())
            Text("P1 will add full-screen camera + upper-body calibration + punch debug panel.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.1))
                }
        }
        .shadow(color: .black.opacity(0.25), radius: 22, y: 12)
    }

    private var runnerCommandSnapshot: RunnerCommandCenter.Snapshot {
        RunnerCommandCenter.Snapshot(
            showPoseOverlay: viewModel.showPoseOverlay,
            mirrorCamera: viewModel.mirrorCamera,
            poseStabilizationEnabled: viewModel.poseStabilizationEnabled,
            showPoseArmDebugOverlay: viewModel.showPoseArmDebugOverlay,
            showWorldAxes: viewModel.showWorldAxes,
            showRunnerAxes: viewModel.showRunnerAxes,
            controlMode: viewModel.controlMode
        )
    }

    private func makeRunnerCommandHandlers() -> RunnerCommandCenter.Handlers {
        let vm = viewModel
        return RunnerCommandCenter.Handlers(
            updateShowPoseOverlay: { [weak vm] in vm?.updateShowPoseOverlay($0) },
            updateMirrorCamera: { [weak vm] in vm?.updateMirrorCamera($0) },
            updatePoseStabilizationEnabled: { [weak vm] in vm?.updatePoseStabilizationEnabled($0) },
            updateShowPoseArmDebugOverlay: { [weak vm] in vm?.updateShowPoseArmDebugOverlay($0) },
            updateShowWorldAxes: { [weak vm] in vm?.updateShowWorldAxes($0) },
            updateShowRunnerAxes: { [weak vm] in vm?.updateShowRunnerAxes($0) },
            updateControlMode: { [weak vm] in vm?.updateControlMode($0) }
        )
    }
}

#Preview {
    ExerciseHubView(dependencies: .preview())
}

private struct PoseArmDebugOverlay: View {
    let rawPose: Pose?
    let stabilizedPose: Pose?
    let isStabilizationEnabled: Bool

    private let joints: [(PoseJointName, String)] = [
        (.leftElbow, "LE"),
        (.rightElbow, "RE"),
        (.leftWrist, "LW"),
        (.rightWrist, "RW"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Arms • stab \(isStabilizationEnabled ? "on" : "off")")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))

            ForEach(joints, id: \.0) { joint, label in
                let raw = confidenceString(in: rawPose, joint: joint)
                let out = stabilizedPose?.joint(joint) != nil ? "1" : "0"
                Text("\(label) raw \(raw) out \(out)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(6)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }

    private func confidenceString(in pose: Pose?, joint: PoseJointName) -> String {
        guard let c = pose?.joint(joint)?.confidence else { return "—" }
        return String(format: "%.2f", c)
    }
}

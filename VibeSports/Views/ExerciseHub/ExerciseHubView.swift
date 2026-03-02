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
            if viewModel.sessionState.kind == .boxing && !viewModel.sessionState.isIdle {
                if let session = viewModel.boxingSession {
                    BoxingView(
                        sessionViewModel: session,
                        cameraSession: viewModel.cameraSession,
                        isMirroredHorizontally: viewModel.mirrorCamera,
                        showPoseOverlay: viewModel.showPoseOverlay,
                        pose: viewModel.poseStabilizationEnabled ? viewModel.stabilizedPose : viewModel.latestPose
                    )
                } else {
                    Color.black.ignoresSafeArea()
                }
            } else {
                RunnerSceneView(renderer: viewModel.runningSession.sceneRenderer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }

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
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            debugTools.attach(sceneRenderer: viewModel.runningSession.sceneRenderer)
            runnerCommands.attach(
                snapshot: runnerCommandSnapshot,
                handlers: makeRunnerCommandHandlers()
            )
            viewModel.updateStrideLengthMetersPerStep(debugTools.runnerTuning.cadence.strideLengthMetersPerStep)
            viewModel.runningSession.updateShowWorldAxes(viewModel.runningSession.showWorldAxes)
            viewModel.runningSession.updateShowRunnerAxes(viewModel.runningSession.showRunnerAxes)
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
            debugTools.detach(sceneRenderer: viewModel.runningSession.sceneRenderer)
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
                Text("Control: \(viewModel.runningSession.controlMode.debugTitle)")
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
                    let steps = viewModel.runningSession.metrics.steps
                    let spm = Int(viewModel.runningSession.metrics.cadenceStepsPerMinute.rounded())
                    Text("Running • \(steps) steps • \(spm) spm")
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
                                PoseArmDebugOverlayView(
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
            return "Press Start to begin Running (head-only detection)."
        case .boxing:
            return "Press Start to calibrate and begin Boxing."
        }
    }

    private var runnerCommandSnapshot: RunnerCommandCenter.Snapshot {
        RunnerCommandCenter.Snapshot(
            showPoseOverlay: viewModel.showPoseOverlay,
            mirrorCamera: viewModel.mirrorCamera,
            poseStabilizationEnabled: viewModel.poseStabilizationEnabled,
            showPoseArmDebugOverlay: viewModel.showPoseArmDebugOverlay,
            showWorldAxes: viewModel.runningSession.showWorldAxes,
            showRunnerAxes: viewModel.runningSession.showRunnerAxes,
            controlMode: viewModel.runningSession.controlMode
        )
    }

    private func makeRunnerCommandHandlers() -> RunnerCommandCenter.Handlers {
        let vm = viewModel
        return RunnerCommandCenter.Handlers(
            updateShowPoseOverlay: { [weak vm] in vm?.updateShowPoseOverlay($0) },
            updateMirrorCamera: { [weak vm] in vm?.updateMirrorCamera($0) },
            updatePoseStabilizationEnabled: { [weak vm] in vm?.updatePoseStabilizationEnabled($0) },
            updateShowPoseArmDebugOverlay: { [weak vm] in vm?.updateShowPoseArmDebugOverlay($0) },
            updateShowWorldAxes: { [weak vm] in vm?.runningSession.updateShowWorldAxes($0) },
            updateShowRunnerAxes: { [weak vm] in vm?.runningSession.updateShowRunnerAxes($0) },
            updateControlMode: { [weak vm] in vm?.runningSession.updateControlMode($0) }
        )
    }
}

#Preview {
    ExerciseHubView(dependencies: .preview())
}

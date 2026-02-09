import SwiftUI

struct RunnerGameView: View {
    let dependencies: AppDependencies

    @StateObject private var viewModel: RunnerGameViewModel
    @EnvironmentObject private var debugTools: DebugToolsStore
    @EnvironmentObject private var runnerCommands: RunnerCommandCenter

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: RunnerGameViewModel(dependencies: dependencies))
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
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)

            VStack {
                headerBar
                Spacer(minLength: 0)
            }
            .padding(16)

            if viewModel.mode == .idle {
                idleOverlay
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            debugTools.attach(sceneRenderer: viewModel.sceneRenderer)
            let vm = viewModel
            runnerCommands.attach(
                snapshot: makeRunnerCommandSnapshot(),
                handlers: RunnerCommandCenter.Handlers(
                    updateShowPoseOverlay: { [weak vm] in vm?.updateShowPoseOverlay($0) },
                    updateMirrorCamera: { [weak vm] in vm?.updateMirrorCamera($0) },
                    updatePoseStabilizationEnabled: { [weak vm] in vm?.updatePoseStabilizationEnabled($0) },
                    updateShowWorldAxes: { [weak vm] in vm?.updateShowWorldAxes($0) },
                    updateShowRunnerAxes: { [weak vm] in vm?.updateShowRunnerAxes($0) },
                    updateControlMode: { [weak vm] in vm?.updateControlMode($0) }
                )
            )
            viewModel.updateStrideLengthMetersPerStep(debugTools.runnerTuning.cadence.strideLengthMetersPerStep)
            viewModel.updateShowWorldAxes(viewModel.showWorldAxes)
            viewModel.updateShowRunnerAxes(viewModel.showRunnerAxes)
        }
        .onChange(of: debugTools.runnerTuning.cadence) { cadence in
            viewModel.updateStrideLengthMetersPerStep(cadence.strideLengthMetersPerStep)
        }
        .onChange(of: viewModel.showPoseOverlay) { _, _ in
            syncRunnerCommands()
        }
        .onChange(of: viewModel.mirrorCamera) { _, _ in
            syncRunnerCommands()
        }
        .onChange(of: viewModel.poseStabilizationEnabled) { _, _ in
            syncRunnerCommands()
        }
        .onChange(of: viewModel.showWorldAxes) { _, _ in
            syncRunnerCommands()
        }
        .onChange(of: viewModel.showRunnerAxes) { _, _ in
            syncRunnerCommands()
        }
        .onChange(of: viewModel.controlMode) { _, _ in
            syncRunnerCommands()
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

            if viewModel.mode == .running {
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
            Text("Running • \(String(format: "%.1f", viewModel.metrics.speedKilometersPerHour)) km/h")
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
                    let pose = viewModel.poseStabilizationEnabled ? viewModel.stabilizedPose : viewModel.latestPose
                    if viewModel.showPoseOverlay, let pose {
                        PoseOverlayView(pose: pose, isMirroredHorizontally: viewModel.mirrorCamera)
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
            Text("Press Start to use camera pose detection to drive the 3D scene.")
                .foregroundStyle(.secondary)
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

    private func syncRunnerCommands() {
        runnerCommands.apply(snapshot: makeRunnerCommandSnapshot())
    }

    private func makeRunnerCommandSnapshot() -> RunnerCommandCenter.Snapshot {
        RunnerCommandCenter.Snapshot(
            showPoseOverlay: viewModel.showPoseOverlay,
            mirrorCamera: viewModel.mirrorCamera,
            poseStabilizationEnabled: viewModel.poseStabilizationEnabled,
            showWorldAxes: viewModel.showWorldAxes,
            showRunnerAxes: viewModel.showRunnerAxes,
            controlMode: viewModel.controlMode
        )
    }
}

#Preview {
    RunnerGameView(dependencies: .preview())
}

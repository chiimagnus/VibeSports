import AppKit
import SwiftUI

struct ExerciseWindowView: View {
    let dependencies: AppDependencies

    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var navState: AppNavigationState
    @EnvironmentObject private var debugTools: DebugToolsStore
    @EnvironmentObject private var runnerCommands: RunnerCommandCenter

    @StateObject private var viewModel: ExerciseHubViewModel
    @State private var window: NSWindow?
    @State private var didStart = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: ExerciseHubViewModel(dependencies: dependencies))
    }

    var body: some View {
        ZStack {
            content

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

            if viewModel.sessionState.kind == .running && !viewModel.sessionState.isIdle {
                if case .calibrating(let progress, let message) = viewModel.runningSession.state {
                    RunningCalibrationOverlayView(progress: progress, message: message)
                }
            }
        }
        .background(.black.opacity(0.06))
        .overlay(alignment: .topLeading) {
            topLeftHUD
                .padding(16)
                .zIndex(10)
        }
        .overlay(alignment: .topTrailing) {
            topRightHUD
                .padding(16)
                .zIndex(10)
        }
        .overlay {
            WindowReferenceReader { window in
                self.window = window
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            attachDebugTools()
            startIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)) { notification in
            guard let window else { return }
            guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
            viewModel.stopIfNeeded()
            DispatchQueue.main.async { openWindow(id: "home") }
        }
        .onChange(of: debugTools.runnerTuning.cadence) { _, cadence in
            viewModel.updateStrideLengthMetersPerStep(cadence.strideLengthMetersPerStep)
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

    @ViewBuilder
    private var content: some View {
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
    }

    private var topLeftHUD: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VibeSports")
                .font(.headline)

            statusText
                .foregroundStyle(.secondary)
                .font(.subheadline)

            if viewModel.sessionState.kind == .running {
                Text("Control: \(viewModel.runningSession.controlMode.debugTitle)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.10))
                }
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
    }

    private var topRightHUD: some View {
        VStack(alignment: .trailing, spacing: 10) {
            cameraPreview
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch viewModel.cameraSession.state {
        case .idle:
            Text("Starting…")
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
                    Text("Running • \(String(format: "%.1f", viewModel.runningSession.metrics.speedKilometersPerHour)) km/h")
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

    private func attachDebugTools() {
        debugTools.attach(sceneRenderer: viewModel.runningSession.sceneRenderer)
        runnerCommands.attach(
            snapshot: runnerCommandSnapshot,
            handlers: makeRunnerCommandHandlers()
        )
        viewModel.updateStrideLengthMetersPerStep(debugTools.runnerTuning.cadence.strideLengthMetersPerStep)
        viewModel.runningSession.updateShowWorldAxes(viewModel.runningSession.showWorldAxes)
        viewModel.runningSession.updateShowRunnerAxes(viewModel.runningSession.showRunnerAxes)
    }

    private func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        viewModel.updateSelectedExerciseKind(navState.selectedExerciseKind)
        viewModel.startTapped()
    }
}

#Preview {
    ExerciseWindowView(dependencies: .preview())
        .environmentObject(DebugToolsStore())
        .environmentObject(RunnerCommandCenter())
        .environmentObject(AppNavigationState())
}

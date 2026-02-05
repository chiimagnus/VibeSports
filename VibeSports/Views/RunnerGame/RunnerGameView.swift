import SwiftUI

struct RunnerGameView: View {
    let dependencies: AppDependencies

    @StateObject private var viewModel: RunnerGameViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: RunnerGameViewModel(dependencies: dependencies))
    }

    var body: some View {
        ZStack {
            RunnerSceneView(renderer: viewModel.sceneRenderer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack {
                headerBar
                Spacer(minLength: 0)
                footerOverlay
            }
            .padding(16)

            if viewModel.mode == .idle {
                idleOverlay
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .focusedSceneValue(
            \.showPoseOverlay,
            Binding(
                get: { viewModel.showPoseOverlay },
                set: { viewModel.updateShowPoseOverlay($0) }
            )
        )
        .focusedSceneValue(
            \.mirrorCamera,
            Binding(
                get: { viewModel.mirrorCamera },
                set: { viewModel.updateMirrorCamera($0) }
            )
        )
        .focusedSceneValue(
            \.poseStabilizationEnabled,
            Binding(
                get: { viewModel.poseStabilizationEnabled },
                set: { viewModel.updatePoseStabilizationEnabled($0) }
            )
        )
        .onDisappear {
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

    private var footerOverlay: some View {
        ZStack(alignment: .bottom) {
            RunnerAvatarView(speedMetersPerSecond: viewModel.metrics.speedMetersPerSecond)
        }
        .frame(maxWidth: .infinity)
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
}

#Preview {
    RunnerGameView(dependencies: .preview())
}

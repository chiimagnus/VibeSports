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
                Button("结束") {
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
            Text("未开始")
        case .requestingAuthorization:
            Text("请求摄像头权限中…")
        case .unauthorized:
            Text("未获得摄像头权限（系统设置 → 隐私与安全性 → 摄像头）")
        case .failed(let message):
            Text("摄像头启动失败：\(message)")
        case .running:
            Text("运动中 • \(String(format: "%.1f", viewModel.metrics.speedKilometersPerHour)) km/h")
        }
    }

    @ViewBuilder
    private var cameraPreview: some View {
        switch viewModel.cameraSession.state {
        case .running:
            CameraPreviewView(session: viewModel.cameraSession.captureSession, isMirroredHorizontally: true)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12))
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
            Text("准备开始")
                .font(.title2.bold())
            Text("点击开始后，将使用摄像头姿态检测来驱动 3D 场景。")
                .foregroundStyle(.secondary)
            Button("开始运动") {
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

import SwiftUI

struct RunnerGameSessionView: View {
    let dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: RunnerGameSessionViewModel

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: RunnerGameSessionViewModel(dependencies: dependencies))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("运动中")
                    .font(.title2.bold())
                Spacer()
                Button("结束") {
                    viewModel.stop()
                    dismiss()
                }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Text("体重")
                    .foregroundStyle(.secondary)
                TextField(
                    "kg",
                    value: Binding(
                        get: { viewModel.userWeightKg },
                        set: { viewModel.updateUserWeightKg($0) }
                    ),
                    format: .number
                )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                Text("kg")
                    .foregroundStyle(.secondary)

                Spacer()

                Text(viewModel.metrics.debugText)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 16) {
                Toggle(
                    "骨骼叠加",
                    isOn: Binding(
                        get: { viewModel.showPoseOverlay },
                        set: { viewModel.updateShowPoseOverlay($0) }
                    )
                )
                    .toggleStyle(.switch)
                Toggle(
                    "水平镜像",
                    isOn: Binding(
                        get: { viewModel.mirrorPoseOverlay },
                        set: { viewModel.updateMirrorPoseOverlay($0) }
                    )
                )
                    .toggleStyle(.switch)

                Spacer()
            }

            switch viewModel.cameraSession.state {
            case .idle, .requestingAuthorization:
                ContentUnavailableView(
                    "正在准备摄像头",
                    systemImage: "camera",
                    description: Text("首次运行会弹出摄像头权限请求。")
                )
            case .unauthorized:
                ContentUnavailableView(
                    "未获得摄像头权限",
                    systemImage: "camera.fill",
                    description: Text("请到 系统设置 → 隐私与安全性 → 摄像头 中为 VibeSports 开启权限。")
                )
            case .failed(let message):
                ContentUnavailableView(
                    "摄像头启动失败",
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text(message)
                )
            case .running:
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        CameraPreviewView(
                            session: viewModel.cameraSession.captureSession,
                            isMirroredHorizontally: viewModel.mirrorPoseOverlay
                        )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.quaternary)
                            }
                            .overlay {
                                if viewModel.showPoseOverlay, let pose = viewModel.latestPose {
                                    PoseOverlayView(pose: pose, isMirroredHorizontally: viewModel.mirrorPoseOverlay)
                                }
                            }
                            .frame(width: 420, height: 315)

                        VStack(alignment: .leading, spacing: 8) {
                            metricsRow(title: "Speed", value: String(format: "%.1f km/h", viewModel.metrics.speedKilometersPerHour))
                                .font(.title2.bold())
                            metricsRow(title: "Steps", value: "\(viewModel.metrics.steps)")
                                .font(.title3.bold())
                            metricsRow(title: "Calories", value: String(format: "%.2f kcal", viewModel.metrics.calories))
                                .font(.title3.bold())
                            metricsRow(title: "Quality", value: "\(viewModel.metrics.movementQualityPercent)%")
                                .font(.callout.bold())
                        }
                        .padding(.top, 4)

                        Spacer(minLength: 0)
                    }

                    RunnerSceneView(renderer: viewModel.sceneRenderer)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.quaternary)
                        }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private func metricsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

#Preview {
    RunnerGameSessionView(dependencies: .preview())
}

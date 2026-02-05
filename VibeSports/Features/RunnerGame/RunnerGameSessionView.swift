import SwiftUI

struct RunnerGameSessionView: View {
    let dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    @AppStorage("runner.userWeightKg") private var userWeightKg: Double = 60
    @AppStorage("runner.debug.showPoseOverlay") private var showPoseOverlay = false
    @AppStorage("runner.debug.mirrorPoseOverlay") private var mirrorPoseOverlay = false
    @StateObject private var session: RunnerGameSession

    init(dependencies: AppDependencies, userWeightKg: Double) {
        self.dependencies = dependencies
        _userWeightKg = AppStorage(wrappedValue: userWeightKg, "runner.userWeightKg")
        _session = StateObject(wrappedValue: RunnerGameSession(dependencies: dependencies, userWeightKg: userWeightKg))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("运动中")
                    .font(.title2.bold())
                Spacer()
                Button("结束") {
                    session.stop()
                    dismiss()
                }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Text("体重")
                    .foregroundStyle(.secondary)
                TextField("kg", value: $userWeightKg, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                Text("kg")
                    .foregroundStyle(.secondary)

                Spacer()

                Text(session.metrics.debugText)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 16) {
                Toggle("骨骼叠加", isOn: $showPoseOverlay)
                    .toggleStyle(.switch)
                Toggle("水平镜像", isOn: $mirrorPoseOverlay)
                    .toggleStyle(.switch)

                Spacer()
            }

            switch session.cameraSession.state {
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
                            session: session.cameraSession.captureSession,
                            isMirroredHorizontally: mirrorPoseOverlay
                        )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.quaternary)
                            }
                            .overlay {
                                if showPoseOverlay, let pose = session.latestPose {
                                    PoseOverlayView(pose: pose, isMirroredHorizontally: mirrorPoseOverlay)
                                }
                            }
                            .frame(width: 420, height: 315)

                        VStack(alignment: .leading, spacing: 8) {
                            metricsRow(title: "Speed", value: String(format: "%.1f km/h", session.metrics.speedKilometersPerHour))
                                .font(.title2.bold())
                            metricsRow(title: "Steps", value: "\(session.metrics.steps)")
                                .font(.title3.bold())
                            metricsRow(title: "Calories", value: String(format: "%.2f kcal", session.metrics.calories))
                                .font(.title3.bold())
                            metricsRow(title: "Quality", value: "\(session.metrics.movementQualityPercent)%")
                                .font(.callout.bold())
                        }
                        .padding(.top, 4)

                        Spacer(minLength: 0)
                    }

                    RunnerSceneView(renderer: session.sceneRenderer)
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
            await session.start()
        }
        .onDisappear {
            session.stop()
        }
        .onChange(of: userWeightKg) { _, newValue in
            session.userWeightKg = newValue
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
    RunnerGameSessionView(dependencies: .live(), userWeightKg: 60)
}

import SwiftUI

struct RunnerGameSessionView: View {
    let dependencies: AppDependencies
    let userWeightKg: Double
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cameraSession = CameraSession()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("运动中")
                    .font(.title2.bold())
                Spacer()
                Button("结束") {
                    cameraSession.stop()
                    dismiss()
                }
                    .buttonStyle(.bordered)
            }

            Text("体重：\(userWeightKg, format: .number) kg")
                .foregroundStyle(.secondary)

            Divider()

            switch cameraSession.state {
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
                    CameraPreviewView(session: cameraSession.captureSession)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.quaternary)
                        }
                        .frame(width: 420)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Speed")
                            .foregroundStyle(.secondary)
                        Text("0.0 km/h")
                            .font(.title.bold())

                        Text("Steps")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        Text("0")
                            .font(.title2.bold())

                        Text("Calories")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        Text("0.0 kcal")
                            .font(.title2.bold())

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await cameraSession.start()
        }
        .onDisappear {
            cameraSession.stop()
        }
    }
}

#Preview {
    RunnerGameSessionView(dependencies: .live(), userWeightKg: 60)
}

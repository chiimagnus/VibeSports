import SwiftUI

struct RunnerTuningDebugView: View {
    @EnvironmentObject private var debugTools: DebugToolsStore

    var body: some View {
        Form {
            Section("Status") {
                if debugTools.isRunnerAttached {
                    Text("Attached to running scene renderer.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not attached. Open the main game window and focus it.")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Reset Defaults") {
                        debugTools.runnerTuning = .default
                    }
                    .disabled(!debugTools.isRunnerAttached)
                }
            }

            Section {
                slider(
                    "Scale",
                    value: $debugTools.runnerTuning.runner.scale,
                    in: 0.001...0.05,
                    format: "%.4f"
                )
                slider(
                    "Yaw (rad)",
                    value: $debugTools.runnerTuning.runner.yawRadians,
                    in: (-Double.pi)...Double.pi,
                    format: "%.3f"
                )
                slider(
                    "Ahead Z",
                    value: $debugTools.runnerTuning.runner.aheadOffsetZ,
                    in: 1...20,
                    format: "%.2f"
                )
                slider(
                    "Ground Y Adj",
                    value: $debugTools.runnerTuning.runner.additionalGroundOffsetY,
                    in: -1...1,
                    format: "%.3f"
                )
                slider(
                    "X",
                    value: $debugTools.runnerTuning.runner.x,
                    in: -3...3,
                    format: "%.2f"
                )
            } header: {
                Text("Runner")
            } footer: {
                Text("Scale 是模型缩放（影响身高/地面偏移）；Ahead Z 是 runner 相对“前进进度 travelZ”的前置距离；Ground Y Adj 是脚底贴地的微调；Yaw 用来校准面向方向。")
                    .foregroundStyle(.secondary)
            }

            Section {
                slider(
                    "FOV (deg)",
                    value: $debugTools.runnerTuning.camera.fieldOfViewDegrees,
                    in: 20...110,
                    format: "%.0f"
                )
                slider(
                    "Height Y",
                    value: $debugTools.runnerTuning.camera.heightY,
                    in: 0.5...6,
                    format: "%.2f"
                )
                slider(
                    "Back Z",
                    value: $debugTools.runnerTuning.camera.backOffsetZ,
                    in: 1...20,
                    format: "%.2f"
                )
                slider(
                    "LookAt Y",
                    value: $debugTools.runnerTuning.camera.lookAtHeightY,
                    in: 0...4,
                    format: "%.2f"
                )
                slider(
                    "Base X",
                    value: $debugTools.runnerTuning.camera.baseX,
                    in: -2...2,
                    format: "%.2f"
                )
                slider(
                    "Bob Max",
                    value: $debugTools.runnerTuning.camera.bobMaxAmplitude,
                    in: 0...1.0,
                    format: "%.3f"
                )
                slider(
                    "Bob Gain",
                    value: $debugTools.runnerTuning.camera.bobSpeedToAmplitudeGain,
                    in: 0...0.2,
                    format: "%.3f"
                )
                slider(
                    "Bob Freq",
                    value: $debugTools.runnerTuning.camera.bobFrequency,
                    in: 0...12,
                    format: "%.2f"
                )
                slider(
                    "Sway Max",
                    value: $debugTools.runnerTuning.camera.swayMaxAmplitude,
                    in: 0...1.0,
                    format: "%.3f"
                )
                slider(
                    "Sway Gain",
                    value: $debugTools.runnerTuning.camera.swaySpeedToAmplitudeGain,
                    in: 0...0.2,
                    format: "%.3f"
                )
                slider(
                    "Sway Freq",
                    value: $debugTools.runnerTuning.camera.swayFrequency,
                    in: 0...12,
                    format: "%.2f"
                )
            } header: {
                Text("Camera")
            } footer: {
                Text("Height/Back/LookAt 决定第三人称相机位置与注视点；Bob/Sway 会随速度产生轻微镜头起伏/左右摆动：振幅 = min(Max, speed * Gain)。")
                    .foregroundStyle(.secondary)
            }

            Section {
                slider(
                    "Idle Threshold",
                    value: $debugTools.runnerTuning.blender.idleThresholdMetersPerSecond,
                    in: 0...1.0,
                    format: "%.2f"
                )
                slider(
                    "Min Run Speed",
                    value: $debugTools.runnerTuning.blender.minRunSpeedMetersPerSecond,
                    in: 0.1...6.0,
                    format: "%.2f"
                )
                slider(
                    "Max Run Speed",
                    value: $debugTools.runnerTuning.blender.maxRunSpeedMetersPerSecond,
                    in: 0.5...10.0,
                    format: "%.2f"
                )
                slider(
                    "Base Speed",
                    value: $debugTools.runnerTuning.blender.baseSpeedMetersPerSecond,
                    in: 0.5...6.0,
                    format: "%.2f"
                )
                slider(
                    "Min Rate",
                    value: $debugTools.runnerTuning.blender.minPlaybackRate,
                    in: 0.0...2.0,
                    format: "%.2f"
                )
                slider(
                    "Max Rate",
                    value: $debugTools.runnerTuning.blender.maxPlaybackRate,
                    in: 0.5...6.0,
                    format: "%.2f"
                )
                slider(
                    "Speed Smooth α",
                    value: $debugTools.runnerTuning.speedSmoothingAlpha,
                    in: 0.0...1.0,
                    format: "%.2f"
                )
            } header: {
                Text("Animation Blend")
            } footer: {
                Text("Idle Threshold：低于该速度时偏向 idle；Min/Max Run Speed：slow↔fast 的混合区间；Base Speed：动画 clip 的参考速度；Min/Max Rate：播放速率夹紧范围；Smooth α：速度低通滤波强度（越大越灵敏，越小越平滑）。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 520, minHeight: 700)
        .navigationTitle("Runner Tuning")
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        format: String
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 140, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }
}

#Preview {
    RunnerTuningDebugView()
        .environmentObject(DebugToolsStore())
}

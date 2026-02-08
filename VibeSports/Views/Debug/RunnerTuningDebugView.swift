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
            } header: {
                Text("Runner")
            } footer: {
                Text("Scale 是模型缩放（影响身高/地面偏移）。")
                    .foregroundStyle(.secondary)
            }

            Section {
                slider(
                    "Stride (m/step)",
                    value: $debugTools.runnerTuning.cadence.strideLengthMetersPerStep,
                    in: 0.2...2.0,
                    format: "%.2f"
                )
                slider(
                    "Steps / Loop",
                    value: $debugTools.runnerTuning.cadence.stepsPerLoop,
                    in: 0.5...4.0,
                    format: "%.2f"
                )
            } header: {
                Text("Cadence Motion")
            } footer: {
                Text("Stride 用于 cadence→speed 映射（speed = cadence * stride）；Steps/Loop 用于 cadence→动画速率映射。")
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
                Text("Idle Threshold：低于该速度时偏向 idle；Min/Max Run Speed：slow↔fast 的混合区间；Min/Max Rate：播放速率夹紧范围；Speed Smooth α：速度低通滤波强度（越大越灵敏，越小越平滑）。")
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

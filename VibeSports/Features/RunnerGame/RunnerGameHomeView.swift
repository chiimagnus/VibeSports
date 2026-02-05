//
//  RunnerGameHomeView.swift
//  VibeSports
//
//  Created by chii_magnus on 2026/2/5.
//

import SwiftUI

struct RunnerGameHomeView: View {
    @AppStorage("runner.userWeightKg") private var userWeightKg: Double = 60
    @State private var isPresentingSession = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Webcam Runner")
                    .font(.largeTitle.bold())

                Text("点击开始后，应用会使用摄像头与人体姿态检测来估计“原地跑步”的速度/步数/热量，并驱动 3D 场景前进。")
                    .foregroundStyle(.secondary)
            }

            Form {
                HStack {
                    Text("体重")
                    Spacer()
                    TextField("kg", value: $userWeightKg, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                    Text("kg")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Button("开始运动") {
                    isPresentingSession = true
                }
                .buttonStyle(.borderedProminent)

                Text("你可以随时结束会话。")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 360)
        .sheet(isPresented: $isPresentingSession) {
            RunnerGameSessionView(userWeightKg: userWeightKg)
        }
    }
}

#Preview {
    RunnerGameHomeView()
}


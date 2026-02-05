//
//  RunnerGameSessionView.swift
//  VibeSports
//
//  Created by chii_magnus on 2026/2/5.
//

import SwiftUI

struct RunnerGameSessionView: View {
    let userWeightKg: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("运动中")
                    .font(.title2.bold())
                Spacer()
                Button("结束") { dismiss() }
                    .buttonStyle(.bordered)
            }

            Text("体重：\(userWeightKg, format: .number) kg")
                .foregroundStyle(.secondary)

            Divider()

            ContentUnavailableView(
                "待接入摄像头与 3D 场景",
                systemImage: "camera",
                description: Text("下一步会在这里展示摄像头预览、姿态叠加（可选）、以及 3D 无限跑道。")
            )

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    RunnerGameSessionView(userWeightKg: 60)
}


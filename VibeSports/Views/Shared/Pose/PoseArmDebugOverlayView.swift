import SwiftUI

struct PoseArmDebugOverlayView: View {
    let rawPose: Pose?
    let stabilizedPose: Pose?
    let isStabilizationEnabled: Bool

    private let joints: [(PoseJointName, String)] = [
        (.leftElbow, "LE"),
        (.rightElbow, "RE"),
        (.leftWrist, "LW"),
        (.rightWrist, "RW"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Arms • stab \(isStabilizationEnabled ? "on" : "off")")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))

            ForEach(joints, id: \.0) { joint, label in
                let raw = confidenceString(in: rawPose, joint: joint)
                let out = stabilizedPose?.joint(joint) != nil ? "1" : "0"
                Text("\(label) raw \(raw) out \(out)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(6)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .allowsHitTesting(false)
    }

    private func confidenceString(in pose: Pose?, joint: PoseJointName) -> String {
        guard let c = pose?.joint(joint)?.confidence else { return "—" }
        return String(format: "%.2f", c)
    }
}


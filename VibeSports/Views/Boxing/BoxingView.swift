import SwiftUI

struct BoxingView: View {
    @ObservedObject var sessionViewModel: BoxingSessionViewModel
    let cameraSession: CameraSession

    var isMirroredHorizontally: Bool
    var showPoseOverlay: Bool
    var pose: Pose?

    var body: some View {
        ZStack {
            CameraPreviewView(session: cameraSession.captureSession, isMirroredHorizontally: isMirroredHorizontally)
                .ignoresSafeArea()

            if showPoseOverlay, let pose {
                PoseOverlayView(pose: pose, isMirroredHorizontally: isMirroredHorizontally)
                    .ignoresSafeArea()
            }

            switch sessionViewModel.state {
            case .calibrating(let progress, let message):
                BoxingCalibrationOverlayView(
                    progress: progress,
                    message: message,
                    isMirroredHorizontally: isMirroredHorizontally
                )
            case .running:
                runningOverlay
            }
        }
    }

    private var runningOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Boxing")
                .font(.headline)

            if let last = sessionViewModel.lastEvent {
                Text("Last: \(last.kind.rawValue)")
                    .font(.system(.subheadline, design: .monospaced))
            } else {
                Text("Last: —")
                    .foregroundStyle(.secondary)
                    .font(.system(.subheadline, design: .monospaced))
            }

            Divider()

            ForEach(BoxingPunchKind.allCases, id: \.self) { kind in
                let count = sessionViewModel.counts[kind, default: 0]
                HStack {
                    Text(kind.rawValue)
                        .font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text("\(count)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.10))
                }
        }
        .shadow(color: .black.opacity(0.20), radius: 18, y: 10)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}


import SwiftUI

struct RunningCalibrationOverlayView: View {
    let progress: Double
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Text("Running Calibration")
                .font(.headline)

            CalibrationSilhouettePreview(kind: .runningUpperBody)
                .frame(width: 360, height: 360)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.14))
                }

            ProgressView(value: min(1, max(0, progress)))
                .frame(width: 260)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
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
        .allowsHitTesting(false)
    }
}

#Preview {
    VStack(spacing: 24) {
        RunningCalibrationOverlayView(progress: 0.4, message: "Hold still…")
    }
    .padding()
}

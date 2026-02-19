import SwiftUI

struct BoxingCalibrationOverlayView: View {
    var progress: Double
    var message: String
    var isMirroredHorizontally: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                CalibrationSilhouettePreview(kind: .boxingGuard, isMirroredHorizontally: isMirroredHorizontally)
                    .frame(width: min(size.width * 0.55, 520), height: min(size.height * 0.75, 540))

                VStack(spacing: 10) {
                    Text("Calibration")
                        .font(.headline)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    ProgressView(value: min(1, max(0, progress)))
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.10))
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

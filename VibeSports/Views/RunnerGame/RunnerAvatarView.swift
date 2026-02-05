import SwiftUI

struct RunnerAvatarView: View {
    var speedMetersPerSecond: Double

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let intensity = min(1, max(0, speedMetersPerSecond) / 3.5)
            let freq = 6.0 + 10.0 * intensity
            let bounce = sin(t * freq) * (2.0 + 6.0 * intensity)
            let squash = 1.0 - (abs(sin(t * freq)) * 0.06 * intensity)

            Image(systemName: "figure.run")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary, .secondary)
                .font(.system(size: 44, weight: .semibold))
                .scaleEffect(x: 1.0, y: squash, anchor: .bottom)
                .offset(y: -bounce)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.white.opacity(0.08))
                        }
                }
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
        }
        .allowsHitTesting(false)
    }
}


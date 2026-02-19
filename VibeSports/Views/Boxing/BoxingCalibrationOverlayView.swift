import SwiftUI

struct BoxingCalibrationOverlayView: View {
    var progress: Double
    var message: String
    var isMirroredHorizontally: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                silhouetteGuide(in: size)

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

    private func silhouetteGuide(in size: CGSize) -> some View {
        let rectWidth = min(size.width * 0.55, 520)
        let rectHeight = min(size.height * 0.75, 540)
        let rect = CGRect(
            x: (size.width - rectWidth) * 0.5,
            y: (size.height - rectHeight) * 0.5,
            width: rectWidth,
            height: rectHeight
        )

        let head = CGRect(
            x: rect.midX - rect.width * 0.12,
            y: rect.minY + rect.height * 0.06,
            width: rect.width * 0.24,
            height: rect.width * 0.24
        )

        let shoulderLineY = rect.minY + rect.height * 0.24
        let leftFist = CGPoint(x: rect.midX - rect.width * 0.16, y: rect.minY + rect.height * 0.20)
        let rightFist = CGPoint(x: rect.midX + rect.width * 0.16, y: rect.minY + rect.height * 0.20)
        let fistRadius = rect.width * 0.06

        return Canvas { context, _ in
            let outline = Path(roundedRect: rect, cornerRadius: 26)
            context.stroke(outline, with: .color(.white.opacity(0.12)), style: .init(lineWidth: 2, dash: [10, 8]))

            context.stroke(Path(ellipseIn: head), with: .color(.white.opacity(0.12)), style: .init(lineWidth: 2, dash: [8, 6]))

            var shoulders = Path()
            shoulders.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: shoulderLineY))
            shoulders.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: shoulderLineY))
            context.stroke(shoulders, with: .color(.white.opacity(0.14)), style: .init(lineWidth: 2))

            let fistColor = Color.cyan.opacity(0.45)
            context.fill(Path(ellipseIn: CGRect(x: leftFist.x - fistRadius, y: leftFist.y - fistRadius, width: fistRadius * 2, height: fistRadius * 2)), with: .color(fistColor))
            context.fill(Path(ellipseIn: CGRect(x: rightFist.x - fistRadius, y: rightFist.y - fistRadius, width: fistRadius * 2, height: fistRadius * 2)), with: .color(fistColor))
        }
        .compositingGroup()
        .overlay {
            Text(isMirroredHorizontally ? "Mirror: On" : "Mirror: Off")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .padding(8)
                .background(.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}


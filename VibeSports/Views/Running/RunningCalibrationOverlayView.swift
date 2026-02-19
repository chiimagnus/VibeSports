import SwiftUI

struct RunningCalibrationOverlayView: View {
    let progress: Double
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Text("Running Calibration")
                .font(.headline)

            RunningCalibrationSilhouetteView()
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

private struct RunningCalibrationSilhouetteView: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let centerX = w * 0.5

            let stroke = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            let color = Color.white.opacity(0.24)

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * w, y: y * h)
            }

            func line(_ a: CGPoint, _ b: CGPoint) {
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(path, with: .color(color), style: stroke)
            }

            func circle(center: CGPoint, radius: CGFloat) {
                let rect = CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.stroke(Path(ellipseIn: rect), with: .color(color), style: stroke)
            }

            circle(center: CGPoint(x: centerX, y: h * 0.18), radius: min(w, h) * 0.075)

            let leftShoulder = point(0.34, 0.30)
            let rightShoulder = point(0.66, 0.30)
            line(leftShoulder, rightShoulder)

            let leftElbow = point(0.28, 0.42)
            let rightElbow = point(0.72, 0.42)
            let leftWrist = point(0.24, 0.54)
            let rightWrist = point(0.76, 0.54)

            line(leftShoulder, leftElbow)
            line(leftElbow, leftWrist)
            line(rightShoulder, rightElbow)
            line(rightElbow, rightWrist)

            let chestTop = point(0.50, 0.32)
            let chestBottom = point(0.50, 0.72)
            line(chestTop, chestBottom)
        }
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.18))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 24) {
        RunningCalibrationOverlayView(progress: 0.4, message: "Hold still…")
    }
    .padding()
}

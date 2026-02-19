import SwiftUI

enum CalibrationSilhouetteKind: Sendable, Equatable {
    case runningUpperBody
    case boxingGuard
}

struct CalibrationSilhouettePreview: View {
    let kind: CalibrationSilhouetteKind
    var isMirroredHorizontally: Bool? = nil

    var body: some View {
        switch kind {
        case .runningUpperBody:
            runningUpperBody
        case .boxingGuard:
            boxingGuard
        }
    }

    private var runningUpperBody: some View {
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
                .fill(.black.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var boxingGuard: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rectWidth = min(size.width * 0.75, 520)
            let rectHeight = min(size.height * 0.80, 540)
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

            Canvas { context, _ in
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
        }
        .compositingGroup()
        .overlay {
            if let isMirroredHorizontally {
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
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 18) {
        CalibrationSilhouettePreview(kind: .runningUpperBody)
            .frame(width: 360, height: 360)
        CalibrationSilhouettePreview(kind: .boxingGuard, isMirroredHorizontally: true)
            .frame(width: 360, height: 360)
    }
    .padding()
}


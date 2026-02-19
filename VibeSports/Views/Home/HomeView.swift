import AppKit
import SwiftUI

struct HomeView: View {
    let dependencies: AppDependencies
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var navState: AppNavigationState

    @State private var window: NSWindow?

    var body: some View {
        HStack(spacing: 16) {
            leftPanel
                .frame(width: 360)

            previewPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .background(.black.opacity(0.06))
        .overlay {
            WindowReferenceReader { window in
                self.window = window
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
            .frame(minWidth: 900, minHeight: 600)
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VibeSports")
                    .font(.title2.bold())
                Text("Select a mode • Double-click to start")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            VStack(spacing: 10) {
                ExerciseCard(
                    title: "Running",
                    subtitle: "Upper-body calibration → drive 3D scene",
                    isSelected: navState.selectedExerciseKind == .running,
                    onSelect: { navState.selectedExerciseKind = .running },
                    onActivate: { activate(.running) }
                )

                ExerciseCard(
                    title: "Boxing",
                    subtitle: "Guard calibration → punch events + debug UI",
                    isSelected: navState.selectedExerciseKind == .boxing,
                    onSelect: { navState.selectedExerciseKind = .boxing },
                    onActivate: { activate(.boxing) }
                )
            }

            Spacer(minLength: 0)

            Text("Tip: Home doesn’t use the camera. The exercise window will request camera access.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calibration Preview")
                .font(.headline)
                .foregroundStyle(.secondary)

            Group {
                switch navState.selectedExerciseKind {
                case .running:
                    RunningUpperBodySilhouettePreview()
                case .boxing:
                    BoxingGuardSilhouettePreview()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08))
                }
        }
    }

    private func activate(_ kind: ExerciseKind) {
        navState.selectedExerciseKind = kind
        openWindow(id: "exercise")
        DispatchQueue.main.async {
            window?.performClose(nil)
        }
    }
}

#Preview {
    HomeView(dependencies: .preview())
        .environmentObject(AppNavigationState())
}

private struct ExerciseCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if isSelected {
                    Text("Selected")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            Text(subtitle)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? .blue.opacity(0.10) : .white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? .blue.opacity(0.22) : .white.opacity(0.08))
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .highPriorityGesture(
            TapGesture(count: 2).onEnded(onActivate)
        )
        .simultaneousGesture(
            TapGesture().onEnded(onSelect)
        )
    }
}

private struct RunningUpperBodySilhouettePreview: View {
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
                .fill(.black.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BoxingGuardSilhouettePreview: View {
    var body: some View {
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
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

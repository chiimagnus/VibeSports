import SwiftUI

struct HomeView: View {
    let dependencies: AppDependencies
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var navState: AppNavigationState

    var body: some View {
        HStack(spacing: 16) {
            leftPanel
                .frame(width: 360)

            previewPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .background(.black.opacity(0.06))
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
                    CalibrationSilhouettePreview(kind: .runningUpperBody)
                case .boxing:
                    CalibrationSilhouettePreview(kind: .boxingGuard)
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
        DispatchQueue.main.async { dismissWindow(id: "home") }
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

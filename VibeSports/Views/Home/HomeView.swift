import SwiftUI

struct HomeView: View {
    let dependencies: AppDependencies
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var navState: AppNavigationState

    @State private var selectedKind: ExerciseKind = .running
    @State private var lastTapKind: ExerciseKind?
    @State private var lastTapAt: Date?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 360)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            selectedKind = navState.selectedExerciseKind
        }
    }

    private var sidebar: some View {
        List {
            ForEach(ExerciseKind.allCases, id: \.self) { kind in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(.headline)
                        Text(subtitle(for: kind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: symbolName(for: kind))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    handleTap(kind)
                }
                .listRowBackground(selectedKind == kind ? Color.accentColor.opacity(0.18) : Color.clear)
            }
        }
        .navigationTitle("VibeSports")
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text("Double-click a mode to start.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calibration Preview")
                .font(.headline)
                .foregroundStyle(.secondary)

            calibrationPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text("Tip: Home doesn’t use the camera. The exercise window will request camera access.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var calibrationPreview: some View {
        switch selectedKind {
        case .running:
            CalibrationSilhouettePreview(kind: .runningUpperBody)
        case .boxing:
            CalibrationSilhouettePreview(kind: .boxingGuard)
        }
    }

    private func subtitle(for kind: ExerciseKind) -> String {
        switch kind {
        case .running:
            return "Upper-body calibration → drive 3D scene"
        case .boxing:
            return "Guard calibration → punch events + debug UI"
        }
    }

    private func symbolName(for kind: ExerciseKind) -> String {
        switch kind {
        case .running:
            return "figure.run"
        case .boxing:
            return "figure.boxing"
        }
    }

    private func handleTap(_ kind: ExerciseKind) {
        let now = Date()

        selectedKind = kind
        navState.selectedExerciseKind = kind

        if lastTapKind == kind, let lastTapAt, now.timeIntervalSince(lastTapAt) < 0.35 {
            lastTapKind = nil
            self.lastTapAt = nil
            activate(kind)
            return
        }

        lastTapKind = kind
        lastTapAt = now
    }

    private func activate(_ kind: ExerciseKind) {
        selectedKind = kind
        navState.selectedExerciseKind = kind
        openWindow(id: "exercise")
        DispatchQueue.main.async { dismissWindow(id: "home") }
    }
}

#Preview {
    HomeView(dependencies: .preview())
        .environmentObject(AppNavigationState())
}

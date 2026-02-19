import SwiftUI

struct HomeView: View {
    let dependencies: AppDependencies
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var navState: AppNavigationState

    @State private var selectedKind: ExerciseKind? = nil

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
            if selectedKind == nil {
                selectedKind = navState.selectedExerciseKind
            }
        }
        .onChange(of: selectedKind) { _, newValue in
            guard let newValue else { return }
            guard navState.selectedExerciseKind != newValue else { return }
            DispatchQueue.main.async {
                navState.selectedExerciseKind = newValue
            }
        }
        .onChange(of: navState.selectedExerciseKind) { _, newValue in
            guard selectedKind != newValue else { return }
            selectedKind = newValue
        }
    }

    private var sidebar: some View {
        List(selection: $selectedKind) {
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
                .tag(kind)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture(count: 2).onEnded {
                    activate(kind)
                })
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
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Calibration Preview") {
                calibrationPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            }

            Text("Tip: Home doesn’t use the camera. The exercise window will request camera access.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var effectiveSelectedKind: ExerciseKind {
        selectedKind ?? navState.selectedExerciseKind
    }

    private var calibrationPreview: some View {
        Group {
            switch effectiveSelectedKind {
            case .running:
                CalibrationSilhouettePreview(kind: .runningUpperBody)
            case .boxing:
                CalibrationSilhouettePreview(kind: .boxingGuard)
            }
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

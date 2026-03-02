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
            }
        }
        .navigationTitle("VibeSports")
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text("Select a mode, then click Start.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }

    private var effectiveSelectedKind: ExerciseKind {
        selectedKind ?? navState.selectedExerciseKind
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            calibrationPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Start") {
                    activate(effectiveSelectedKind)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var calibrationPreview: some View {
        switch effectiveSelectedKind {
        case .running:
            VStack(spacing: 14) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 72, weight: .regular))
                    .foregroundStyle(.secondary)
                Text("Running (Head-only)")
                    .font(.title2.bold())
                Text("Use your head bob to count steps and drive the 3D scene.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        case .boxing:
            CalibrationSilhouettePreview(kind: .boxingGuard)
        }
    }

    private func subtitle(for kind: ExerciseKind) -> String {
        switch kind {
        case .running:
            return "Head-only detection → drive 3D scene"
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

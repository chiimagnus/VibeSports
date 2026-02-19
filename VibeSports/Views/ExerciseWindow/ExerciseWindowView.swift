import SwiftUI

struct ExerciseWindowView: View {
    let dependencies: AppDependencies

    var body: some View {
        Text("Exercise")
            .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ExerciseWindowView(dependencies: .preview())
        .environmentObject(DebugToolsStore())
        .environmentObject(RunnerCommandCenter())
        .environmentObject(AppNavigationState())
}


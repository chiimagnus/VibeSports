import SwiftUI

struct ContentView: View {
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live()) {
        self.dependencies = dependencies
    }

    var body: some View {
        RunnerGameHomeView(dependencies: dependencies)
    }
}

#Preview {
    ContentView()
}

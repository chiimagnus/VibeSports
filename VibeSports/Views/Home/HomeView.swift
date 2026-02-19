import SwiftUI

struct HomeView: View {
    let dependencies: AppDependencies

    var body: some View {
        Text("Home")
            .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    HomeView(dependencies: .preview())
        .environmentObject(AppNavigationState())
}


import SwiftUI
import SwiftData

@main
@MainActor
struct VibeSportsApp: App {
    private let modelContainer: ModelContainer
    private let dependencies: AppDependencies

    init() {
        do {
            modelContainer = try ModelContainer(for: AppSettings.self)
            dependencies = AppDependencies.live(modelContext: modelContainer.mainContext)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
        .modelContainer(modelContainer)
        .commands {
            DebugCommands()
        }
    }
}

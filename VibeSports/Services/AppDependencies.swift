import Foundation
import SwiftData

struct AppDependencies {
    var clock: any Clock

    var settingsRepository: any SettingsRepository

    var makeCameraSession: @MainActor () -> CameraSession
    var makeRunnerSceneRenderer: @MainActor () -> RunnerSceneRenderer

    @MainActor
    static func live(modelContext: ModelContext) -> AppDependencies {
        AppDependencies(
            clock: SystemClock(),
            settingsRepository: SwiftDataSettingsRepository(modelContext: modelContext),
            makeCameraSession: { CameraSession() },
            makeRunnerSceneRenderer: { RunnerSceneRenderer() }
        )
    }

    @MainActor
    static func preview() -> AppDependencies {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: AppSettings.self, configurations: configuration)
        return live(modelContext: container.mainContext)
    }
}
